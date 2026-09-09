"""
ObsidianVPN Key Server — deployed to /opt/obsidian/ on the VPN server.
Pure stdlib Python 3, no external dependencies.

Role: device tracking and key lifecycle (expiry, revocation).
The connection config is embedded in the key itself (see keys_codec.py),
so the client can connect even if the keyserver is unreachable.

Endpoints:
  GET  /health                — liveness probe
  POST /register              — register/refresh a device for a token
  POST /heartbeat             — periodic check-in, returns 403 if revoked/expired
  GET  /admin/keys            — list all tokens   [requires X-Admin-Token]
  POST /admin/keys            — create/update/delete/revoke_device

Environment variables:
  ADMIN_TOKEN      — secret for admin endpoints (required in production)
  KEYS_FILE        — path to keys JSON (default /opt/obsidian/keys.json)
  KEYSERVER_PORT   — listen port (default 8444)
"""

import datetime
import json
import os
import secrets
import string
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse

KEYS_FILE = os.environ.get("KEYS_FILE", "/opt/obsidian/keys.json")
REVOCATIONS_FILE = os.environ.get(
    "REVOCATIONS_FILE", "/opt/obsidian/revoked_clients.json"
)
ADMIN_TOKEN = os.environ.get("ADMIN_TOKEN", "")
PORT = int(os.environ.get("KEYSERVER_PORT", "8444"))
BIND_HOST = os.environ.get("KEYSERVER_BIND", "127.0.0.1")

_lock = threading.Lock()


# ── Storage ────────────────────────────────────────────────────────────────────

def _load() -> dict:
    if not os.path.isfile(KEYS_FILE):
        return {}
    with open(KEYS_FILE) as f:
        return json.load(f)


def _save(data: dict):
    tmp = KEYS_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
    os.replace(tmp, KEYS_FILE)
    _write_revocations(data)


def _write_revocations(keys: dict):
    """Publish a deny list that the VPN daemon reloads for each handshake."""
    revoked = []
    for kd in keys.values():
        public_key = str(kd.get("client_public_key", "")).lower()
        if len(public_key) != 64:
            continue
        if kd.get("revoked") or _is_expired(kd):
            revoked.append(public_key)
    tmp = REVOCATIONS_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"revoked_clients": sorted(set(revoked))}, f)
    os.replace(tmp, REVOCATIONS_FILE)


def _now() -> str:
    return datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")


def _is_expired(kd: dict) -> bool:
    exp = kd.get("expires_at")
    return bool(exp and _now() > exp)


def _gen_token() -> str:
    alphabet = string.ascii_uppercase + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(32))


# ── Handler ────────────────────────────────────────────────────────────────────

class _Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # use explicit print below for important events

    def _send(self, code: int, data: dict):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self) -> dict:
        n = int(self.headers.get("Content-Length", 0))
        return json.loads(self.rfile.read(n)) if n else {}

    def _admin_ok(self) -> bool:
        if not ADMIN_TOKEN:
            return True
        if self.headers.get("X-Admin-Token", "") == ADMIN_TOKEN:
            return True
        self._send(403, {"error": "unauthorized"})
        return False

    # ── GET ────────────────────────────────────────────────────────────────────

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/health":
            self._send(200, {"status": "ok"})
        elif path == "/admin/keys":
            if not self._admin_ok():
                return
            with _lock:
                self._send(200, _load())
        else:
            self._send(404, {"error": "not_found"})

    # ── POST ───────────────────────────────────────────────────────────────────

    def do_POST(self):
        path = urlparse(self.path).path
        body = self._body()

        if path == "/register":
            # Client registers a device for a token.
            # Token is embedded in the key by admin at key-creation time.
            token = body.get("token", "").strip()
            device_id = body.get("device_id", "").strip()
            device_name = body.get("device_name", "unknown")
            client_public_key = body.get("client_public_key", "").strip().lower()

            if not token or not device_id or len(client_public_key) != 64:
                self._send(400, {"error": "missing_fields"})
                return
            try:
                bytes.fromhex(client_public_key)
            except ValueError:
                self._send(400, {"error": "invalid_client_public_key"})
                return

            with _lock:
                keys = _load()
                kd = keys.get(token)
                if kd is None:
                    self._send(404, {"error": "token_not_found"})
                    return
                if _is_expired(kd):
                    self._send(403, {"error": "token_expired"})
                    return
                if kd.get("revoked"):
                    self._send(403, {"error": "token_revoked"})
                    return

                registered_key = kd.get("client_public_key", "")
                if registered_key and registered_key != client_public_key:
                    self._send(403, {"error": "token_bound_to_another_client_key"})
                    return
                kd["client_public_key"] = client_public_key

                devices: dict = kd.setdefault("devices", {})
                if device_id not in devices:
                    max_dev = kd.get("max_devices", 1)
                    if len(devices) >= max_dev:
                        self._send(403, {
                            "error": "device_limit_reached",
                            "max": max_dev,
                            "current": len(devices),
                        })
                        return
                    devices[device_id] = {
                        "name": device_name,
                        "activated_at": _now(),
                        "last_seen": _now(),
                    }
                    print(f"[register] token={token[:8]}... device={device_name} ({device_id[:8]}...)")
                else:
                    devices[device_id]["last_seen"] = _now()
                _save(keys)

            self._send(200, {"status": "ok"})

        elif path == "/heartbeat":
            token = body.get("token", "").strip()
            device_id = body.get("device_id", "").strip()

            with _lock:
                keys = _load()
                kd = keys.get(token)
                if kd is None:
                    self._send(404, {"error": "token_not_found"})
                    return
                if _is_expired(kd):
                    self._send(403, {"error": "token_expired"})
                    return
                if kd.get("revoked"):
                    self._send(403, {"error": "token_revoked"})
                    return
                if device_id not in kd.get("devices", {}):
                    self._send(403, {"error": "device_not_registered"})
                    return
                kd["devices"][device_id]["last_seen"] = _now()
                _save(keys)

            self._send(200, {"status": "ok"})

        elif path == "/admin/keys":
            if not self._admin_ok():
                return
            action = body.get("action", "")

            with _lock:
                keys = _load()

                if action == "create":
                    token = body.get("token") or _gen_token()
                    if token in keys:
                        self._send(409, {"error": "token_exists"})
                        return
                    keys[token] = {
                        "label": body.get("label", ""),
                        "created_at": _now(),
                        "expires_at": body.get("expires_at"),
                        "max_devices": int(body.get("max_devices", 1)),
                        "revoked": False,
                        "devices": {},
                    }
                    _save(keys)
                    self._send(200, {"token": token})

                elif action == "update":
                    token = body.get("token", "")
                    if token not in keys:
                        self._send(404, {"error": "not_found"})
                        return
                    kd = keys[token]
                    for field in ("expires_at", "max_devices", "label"):
                        if field in body:
                            kd[field] = body[field]
                    _save(keys)
                    self._send(200, {"status": "updated"})

                elif action == "revoke":
                    token = body.get("token", "")
                    if token in keys:
                        keys[token]["revoked"] = True
                        _save(keys)
                    self._send(200, {"status": "revoked"})

                elif action == "delete":
                    token = body.get("token", "")
                    keys.pop(token, None)
                    _save(keys)
                    self._send(200, {"status": "deleted"})

                elif action == "revoke_device":
                    token = body.get("token", "")
                    device_id = body.get("device_id", "")
                    kd = keys.get(token, {})
                    kd.get("devices", {}).pop(device_id, None)
                    _save(keys)
                    self._send(200, {"status": "revoked"})

                else:
                    self._send(400, {"error": f"unknown action: {action!r}"})

        else:
            self._send(404, {"error": "not_found"})


# ── Entry point ────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    if not ADMIN_TOKEN:
        print("WARNING: ADMIN_TOKEN not set — admin endpoints unprotected!")
    with _lock:
        _write_revocations(_load())
    srv = HTTPServer((BIND_HOST, PORT), _Handler)
    print(f"[keyserver] {BIND_HOST}:{PORT}  keys={KEYS_FILE}")
    srv.serve_forever()
