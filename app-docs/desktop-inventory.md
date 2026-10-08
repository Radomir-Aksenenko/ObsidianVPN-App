Старый клиент удалён из репозитория 2026-10-08, исходники в истории git до коммита acff4ce.

# Old desktop client (Tauri): feature inventory

Sources: `desktop/src/{main.js,styles.css,index.html}`, `desktop/src-tauri/src/{lib.rs,vpn.rs,installer.rs,keys.rs,storage.rs}`, `desktop/src-tauri/resources/keyserver.py`. Go client in `core/cmd/client`.
Read the Rust/JS sources for exact details of any item below.

## Screens
- Home: power dial. disconnected "Подключить"; connecting "Отмена" + stage label + percent; connected "Отключить" + session clock HH:MM:SS, subline `host:port · REALITY`; error "Повторить" + red error. Server card (country tag, name, host, ping: green <80 ms, amber <160, red above). Split row summary "Выключено" / "Исключений: N" / "Только VPN: N". Own VPS: "Управление VPS" row. No servers: "Добавить сервер".
- Servers: rows with select, country tag, name, host, ping, IPv4 or IPv4+6. Gear for own VPS. Delete with confirm. Footer: "Ключ доступа" (add key), "Развернуть VPS" (deploy wizard).
- Server manage (own VPS): `user@host:port`, ping, badges (credentials, REALITY :443, IPv4/Dual-Stack). Warning if no SSH creds. SNI input + chips (microsoft.com, apple.com, google.com, samsung.com, vk.com, amazon.com) + "Применить новый SNI". IPv6 toggle. Core card: "Требуется обновление" + update, or "Актуально" + "Проверить обновления". "Обнулить сервер" + confirm. SSH creds form: host, user, port, auth (Пароль / SSH-ключ), password show/hide, key file picker or pasted key.
- Access: key count, own-server count, issued keys list (name, server code, device limit, days or "Бессрочно"), "Создать новый ключ".
- Settings: autostart, minimize to tray (default on), kill switch, device id XXXX-XXXX-XXXX (copy), version.
- Deploy wizard: step 1 IP, user (root), SSH port 22, SNI mask (www.microsoft.com), auth. Hint: clean Ubuntu 22.04/24.04 or Debian 12. Step 2 progress + live console. Step 3 owner key (copy) + admin token (shown once). Update mode: "Прошивка обновлена".
- Issue key: name ("Гость"), validity 7 / 30 (default) / 90 / Бессрочно, devices 1..20 (default 3).
- Issued key: QR, name, server code, key text, copy obsidian:// URI, copy OBSDN- key.
- Add key modal: paste, live preview "Распознано: host:port". Accepts obsidian://, vpn://, OBSDN-.
- Split modal: exclude / include, presets (Госуслуги и банки; VK/Яндекс/Кинопоиск/Дзен/Mail/Rutube; `*.ru *.рф *.su`; заблокированные сайты; AI-сервисы), one entry per line.

## VPN run (desktop)
- `obsidian-client.exe` + `wintun.dll` copied to `%APPDATA%\ObsidianVPN\runtime\`.
- Elevation: `net session` check; else relaunch via PowerShell `Start-Process -Verb RunAs -ArgumentList '--connect'`.
- Config `%APPDATA%\ObsidianVPN\<profile-id>.json`. `tun_address` = `10.8.0.(2 + n % 253)/24` from SHA-256 seed of profile. dns 10.8.0.1 rewritten to 1.1.1.1. MTU capped 1420.
- Spawn `obsidian-client.exe --config <path> --debug`, cwd runtime, pipes, CREATE_NO_WINDOW.
- Status from merged stdout/stderr (poll 250 ms):
  - `: ready` after last `session ended:` -> connected.
  - `session ended:` after ready -> back to connecting.
  - `connecting to` / `handshake` -> stage 1 "REALITY handshake (1/4)".
  - `wintun session started` / `creating adapter` / `session started` -> stage 2 "Wintun адаптер (2/4)".
  - `tun address set` / `set dns` / `tun mtu` -> stage 3 "Конфигурация сети (3/4)".
  - `clean all stale` / `bypass route` / `dual-stack ipv6` / `routes restored` -> stage 4 "Маршрутизация (4/4)".
  - Go logs "reconnecting in 3s" on drop.
- Exit errors humanized: `access is denied`/`administrator` -> needs admin; `failed to open TUN` -> TUN adapter; `connectex`/`did not properly respond` -> server not answering TCP 443; `i/o timeout`/`did not return a recognizable response` -> REALITY handshake timeout; else last line.
- Stop: close child stdin (Go treats EOF as parent exit), wait 1.5 s, kill, then cleanup.
- Windows cleanup (startup, disconnect, close): delete routes 0.0.0.0/1, 128.0.0.0/1, 1.1.1.1, 1.0.0.1, 8.8.8.8, 8.8.4.4; delete HKLM DNSClient policy `DisableSmartNameResolution`, `EnableMulticast`; delete netsh rules `ObsidianVPN-Block-{Physical,IPv6,Router}-DNS-{UDP,TCP}`; `ipconfig /flushdns`; remove NRPT rule `ObsidianVPN-NRPT`.

## Key formats (see keys.rs and core/obsidian/uri.go)
- Client JSON keys: protocol_version 2, server_host, server_port (443), server_public_key (hex), udp_port, enable_udp_data, enable_ipv6, no_tls, tun_address, dns, mtu, route_ips, split_tunnel_mode, split_sites, junk_count 7, junk_min 50, junk_max 1000, noise_min_sec 10, noise_max_sec 40, keepalive_sec 20, profile "fast-secure", jitter "off", signatures (two fixed strings), reality_enabled, reality_auth_key, reality_sni, sni, fingerprint "chrome", client_private_key, client_public_key. App metadata: _keyserver, _token, _expires, _max_devices, _label.
- OBSDN key: `OBSDN-` + base32 (RFC 4648, no padding) of zlib(best) of compact JSON, grouped in 4-char chunks with `-`. Compact keys: h, p, u, k, j, ns, nx, ka, d, mtu, pv, eu, v6, re/rk/rs (REALITY), ks (keyserver URL), t (token), e (expiry), m (max devices).
- URI: `obsidian://<pubkey>@<host>:<port>?udp_port=&udp_data=0&ipv6=1&security=reality&sni=&auth_key=&mtu=&keyserver=&token=&expires=&max_devices=#label`. Also `vpn://obsidian/...`, legacy aliases pk, pbk, sid, fp, sig. Default port 8443 when absent.

## VPS management (installer.rs, russh)
- SSH: 12 s connect, 45 s inactivity, 10 s keepalive, password or key auth (15 s). `.pub` path switched to private key.
- Deploy: (4-12%) connect; (28%) install docker via get.docker.com if missing; (36%) ip_forward, IPv6 probe via ping6 2606:4700:4700::1111; pick TCP/UDP ports from [443, 8443] skipping foreign holders (`ss`); (48%) X25519 server keypair + 32-byte REALITY auth key, upload `obsidian-server-linux` to `/opt/obsidian/obsidian-server` (SFTP, stream fallback), `version.txt` = `0.1.0\n<sha256>`; write `/opt/obsidian/obsidian-server.json` (listen, reality target sni:443, tun0 10.8.0.1/24, out_interface from default route, dns_upstream 1.1.1.1:53, dns_listen 10.8.0.1:53, udp_socket_buffer_mb 16, allowed_clients [], revocation file, junk/noise/keepalive/signatures); (62%) `docker run -d --name obsidian-vpn --network host --cap-add NET_ADMIN --device /dev/net/tun --restart always -v /opt/obsidian:/opt/obsidian ubuntu:22.04 ...`, verify after 2 s, rollback on failure; (78%) key server container `obsidian-keyserver` python:3.11-slim keyserver.py, ADMIN_TOKEN random 24 bytes, bind 127.0.0.1:8444; (90%) NAT: MASQUERADE 10.8.0.0/24, FORWARD tun0<->uplink, MSS clamp 1380 / 1340 v6, INPUT accepts, 8444 only on lo, ufw allow; (100%) owner OBSDN key (3 devices, no expiry) + admin token.
- Update: backup .bak, upload new binary + keyserver, rewrite config, restart, verify, restore on failure, close legacy ports, setup_nat again.
- Version check: remote version.txt hash vs bundled binary sha256.
- Change SNI: edit reality_target, reality_backend, reality_backend_sni, reality_server_names; restart; verify.
- Reset: regenerate server keys + REALITY key, clear allowed_clients, keys.json, revocation; restart; issue a fresh owner key, drop other issued keys.
- keyserver.py: GET /health, POST /register, POST /heartbeat, GET/POST /admin/keys (X-Admin-Token).

## Storage (old)
servers.json (profiles incl. ssh creds, plaintext), issued.json, settings.json (autostart, minimize_to_tray, kill_switch, last_profile_id), device_id.txt (UUID v4), client.log.

## Other
- Tray: Open / Quit (Quit disconnects). Close hides to tray when enabled.
- Ping: TCP connect host:server_port, 1.2 s timeout, every 30 s.
- Country tags guessed from names (Frankfurt/Germany DE, Amsterdam NL, London, Paris, Warsaw, Helsinki, Moscow).

## Known gaps to fix in the new app
Kill switch never enforced; IPv6 toggle does not touch the VPS; SSH host keys not verified (new app: trust on first use, store fingerprint); secrets in plaintext; reconnecting state not shown; hard-coded version strings.
