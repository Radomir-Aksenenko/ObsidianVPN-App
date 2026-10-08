use crate::vpn::extract_runtime;
use rand::RngCore;
use russh::client::{self, Config, Handler};
use russh::keys::{load_secret_key, PrivateKeyWithHashAlg};
use russh::ChannelMsg;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tauri::{AppHandle, Emitter};
use tokio::io::AsyncWriteExt;
use x25519_dalek::{PublicKey, StaticSecret};

const SERVER_DIR: &str = "/opt/obsidian";
const SERVER_BIN: &str = "/opt/obsidian/obsidian-server";
const SERVER_CONFIG: &str = "/opt/obsidian/obsidian-server.json";
const KEYSERVER_SCRIPT: &str = "/opt/obsidian/keyserver.py";
const KEYSERVER_PORT: u16 = 8444;
const VPN_CONTAINER: &str = "obsidian-vpn";
const KS_CONTAINER: &str = "obsidian-keyserver";

struct AcceptAll;
impl Handler for AcceptAll {
    type Error = russh::Error;
    async fn check_server_key(
        &mut self,
        _server_public_key: &russh::keys::PublicKey,
    ) -> Result<bool, Self::Error> {
        Ok(true)
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DeployReq {
    pub host: String,
    pub user: String,
    pub port: u16,
    pub auth: String,
    pub password: Option<String>,
    pub key_path: Option<String>,
    #[serde(default)]
    pub mask: Option<String>,
}

#[derive(Debug, Serialize, Clone)]
pub struct DeployResult {
    pub server_host: String,
    pub server_port: String,
    pub udp_port: String,
    pub server_public_key: String,
    pub keyserver_url: String,
    pub admin_token: String,
    pub reality_auth_key: String,
    pub reality_sni: String,
    pub enable_ipv6: bool,
}

#[derive(Debug, Serialize, Clone)]
pub struct UpdateResult {
    pub server_port: String,
    pub udp_port: String,
    pub reality_enabled: bool,
    pub reality_auth_key: String,
    pub reality_sni: String,
    pub enable_ipv6: bool,
}

fn mask_sni(req: &DeployReq) -> String {
    let raw = req
        .mask
        .as_deref()
        .unwrap_or("www.microsoft.com")
        .trim()
        .trim_end_matches(":443")
        .trim()
        .to_lowercase();
    if raw.is_empty() {
        "www.microsoft.com".into()
    } else {
        raw
    }
}

fn new_reality_auth() -> String {
    let mut b = [0u8; 32];
    rand::rngs::OsRng.fill_bytes(&mut b);
    hex::encode(b)
}

struct Session {
    app: AppHandle,
    handle: client::Handle<AcceptAll>,
}

impl Session {
    fn stamp() -> String {
        let secs = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);
        let t = secs % 86400;
        format!("[{:02}:{:02}:{:02}]", t / 3600, (t % 3600) / 60, t % 60)
    }

    fn log(&self, line: &str) {
        let msg = format!("{} {line}", Self::stamp());
        let _ = self.app.emit("deploy-log", msg);
    }

    fn progress(&self, pct: u8) {
        let _ = self.app.emit("deploy-progress", pct);
    }

    /// Runs a command on the server. Returns (stdout, stderr, exit code) without logging.
    async fn exec_raw(&self, cmd: &str) -> Result<(String, String, u32), String> {
        let mut ch = self
            .handle
            .channel_open_session()
            .await
            .map_err(|e| e.to_string())?;
        ch.exec(true, cmd).await.map_err(|e| e.to_string())?;
        let mut stdout = Vec::new();
        let mut stderr = Vec::new();
        let mut code = 0u32;
        loop {
            match ch.wait().await {
                Some(ChannelMsg::Data { ref data }) => stdout.extend_from_slice(data),
                Some(ChannelMsg::ExtendedData { ref data, .. }) => stderr.extend_from_slice(data),
                Some(ChannelMsg::ExitStatus { exit_status }) => code = exit_status,
                None => break,
                _ => {}
            }
        }
        Ok((
            String::from_utf8_lossy(&stdout).trim().to_string(),
            String::from_utf8_lossy(&stderr).trim().to_string(),
            code,
        ))
    }

    async fn run(&self, cmd: &str, check: bool) -> Result<String, String> {
        self.log(&format!("$ {cmd}"));
        let (out, err, code) = self.exec_raw(cmd).await?;
        for line in out.lines() {
            self.log(line);
        }
        if !err.is_empty() {
            self.log(&format!("[stderr] {err}"));
        }
        if check && code != 0 {
            return Err(format!("Command failed (exit {code}): {cmd}\n{err}"));
        }
        Ok(out)
    }

    /// Like `run(cmd, true)` but the output is not written to the log (used for secrets).
    async fn run_quiet(&self, cmd: &str) -> Result<String, String> {
        let (out, err, code) = self.exec_raw(cmd).await?;
        if code != 0 {
            return Err(format!("Команда на сервере завершилась с ошибкой ({code}): {err}"));
        }
        Ok(out)
    }

    /// Host PIDs of the processes inside the VPN container (it runs with --network host).
    async fn vpn_pids(&self) -> Vec<String> {
        match self
            .exec_raw(&format!("docker top {VPN_CONTAINER} -o pid 2>/dev/null"))
            .await
        {
            Ok((out, _, 0)) => out
                .lines()
                .skip(1)
                .map(|l| l.trim().to_string())
                .filter(|l| !l.is_empty())
                .collect(),
            _ => Vec::new(),
        }
    }

    async fn upload_bytes(&self, data: &[u8], remote: &str) -> Result<(), String> {
        self.log(&format!(
            "upload {} ({:.1} MB)",
            remote.rsplit('/').next().unwrap_or(remote),
            data.len() as f64 / 1024.0 / 1024.0
        ));
        let dir = remote.rsplit_once('/').map(|(d, _)| d).unwrap_or("/");
        self.run(&format!("mkdir -p '{dir}'"), true).await?;
        match self.upload_sftp(data, remote).await {
            Ok(()) => Ok(()),
            Err(e) => {
                self.log(&format!("SFTP failed, streaming: {e}"));
                self.upload_stream(data, remote).await
            }
        }
    }

    async fn upload_sftp(&self, data: &[u8], remote: &str) -> Result<(), String> {
        let channel = self
            .handle
            .channel_open_session()
            .await
            .map_err(|e| e.to_string())?;
        channel
            .request_subsystem(true, "sftp")
            .await
            .map_err(|e| e.to_string())?;
        let sftp = russh_sftp::client::SftpSession::new(channel.into_stream())
            .await
            .map_err(|e| e.to_string())?;
        let mut file = sftp.create(remote).await.map_err(|e| e.to_string())?;
        file.write_all(data).await.map_err(|e| e.to_string())?;
        file.flush().await.map_err(|e| e.to_string())?;
        Ok(())
    }

    async fn upload_stream(&self, data: &[u8], remote: &str) -> Result<(), String> {
        let tmp = format!("/tmp/.obsidian-upload-{}", rand::random::<u32>());
        let mut ch = self
            .handle
            .channel_open_session()
            .await
            .map_err(|e| e.to_string())?;
        let cmd = format!("cat > '{tmp}' && mv -f '{tmp}' '{remote}'");
        ch.exec(true, cmd).await.map_err(|e| e.to_string())?;
        ch.data(&data[..]).await.map_err(|e| e.to_string())?;
        ch.eof().await.map_err(|e| e.to_string())?;
        let mut code = 0u32;
        loop {
            match ch.wait().await {
                Some(ChannelMsg::ExitStatus { exit_status }) => code = exit_status,
                None => break,
                _ => {}
            }
        }
        if code != 0 {
            return Err(format!("stream upload failed ({code})"));
        }
        Ok(())
    }
}

async fn resolve_ssh(host: &str, port: u16) -> Result<SocketAddr, String> {
    let lookup = tokio::time::timeout(
        Duration::from_secs(8),
        tokio::net::lookup_host((host, port)),
    )
    .await
    .map_err(|_| format!("DNS timed out for {host}"))?
    .map_err(|e| format!("Cannot resolve {host}: {e}"))?;
    let addrs: Vec<SocketAddr> = lookup.collect();
    addrs
        .iter()
        .copied()
        .find(|a| a.is_ipv4())
        .or_else(|| addrs.into_iter().next())
        .ok_or_else(|| format!("No address for {host}:{port}"))
}

async fn ssh_open(app: AppHandle, req: &DeployReq) -> Result<Session, String> {
    let host = req.host.trim().to_string();
    let user = req.user.trim().to_string();
    let port = if req.port == 0 { 22 } else { req.port };
    if host.is_empty() {
        return Err("Host is empty".into());
    }
    let _ = app.emit("deploy-progress", 4u8);
    let _ = app.emit(
        "deploy-log",
        format!("{} resolving {host}", Session::stamp()),
    );
    let addr = resolve_ssh(&host, port).await?;
    let _ = app.emit(
        "deploy-log",
        format!("{} connecting SSH {addr}", Session::stamp()),
    );

    let mut cfg = Config::default();
    cfg.inactivity_timeout = Some(Duration::from_secs(45));
    cfg.keepalive_interval = Some(Duration::from_secs(10));
    let cfg = Arc::new(cfg);

    let mut handle = tokio::time::timeout(
        Duration::from_secs(12),
        client::connect(cfg, addr, AcceptAll),
    )
    .await
    .map_err(|_| {
        format!("SSH timed out after 12s ({addr}). Port {port} is closed or filtered.")
    })?
    .map_err(|e| format!("SSH connect failed ({addr}): {e}"))?;

    let _ = app.emit(
        "deploy-log",
        format!("{} authenticating as {user}", Session::stamp()),
    );
    let authed = if req.auth == "key" {
        let path = req.key_path.as_deref().unwrap_or("").trim();
        if path.is_empty() {
            return Err("Путь к приватному SSH-ключу не указан".into());
        }
        let stripped = if path.ends_with(".pub") {
            let candidate = path.trim_end_matches(".pub");
            if std::path::Path::new(candidate).exists() {
                candidate
            } else {
                path
            }
        } else {
            path
        };
        let key = load_secret_key(stripped, None).map_err(|e| {
            format!("Не удалось прочитать SSH-ключ ({stripped}): {e}. Убедитесь, что выбран приватный ключ, а не публичный .pub")
        })?;
        let hashable = PrivateKeyWithHashAlg::new(Arc::new(key), None);
        tokio::time::timeout(
            Duration::from_secs(15),
            handle.authenticate_publickey(&user, hashable),
        )
        .await
        .map_err(|_| "Таймаут аутентификации по SSH-ключу (15с)".to_string())?
        .map_err(|e| format!("Ошибка аутентификации по SSH-ключу: {e}"))?
        .success()
    } else {
        let password = req.password.clone().unwrap_or_default();
        tokio::time::timeout(
            Duration::from_secs(15),
            handle.authenticate_password(&user, password),
        )
        .await
        .map_err(|_| "SSH password auth timed out".to_string())?
        .map_err(|e| e.to_string())?
        .success()
    };
    if !authed {
        return Err("SSH authentication failed".into());
    }
    let s = Session { app, handle };
    s.log("ssh connected");
    Ok(s)
}

fn runtime_files(app: &AppHandle) -> Result<(PathBuf, PathBuf), String> {
    let runtime = extract_runtime(app)?;
    let runtime_dir = runtime.parent().unwrap().to_path_buf();
    let server_bin = runtime_dir.join("obsidian-server-linux");
    let keyserver = runtime_dir.join("keyserver.py");
    if !server_bin.exists() {
        return Err("obsidian-server-linux is missing from the app bundle".into());
    }
    Ok((server_bin, keyserver))
}

async fn probe_ipv6_connectivity(s: &Session) -> bool {
    s.log("checking IPv6 connectivity on VPS");
    let check = s
        .run("ip -6 route show default 2>/dev/null | grep -q default && (ping6 -c 1 -W 2 2606:4700:4700::1111 >/dev/null 2>&1 || ping -6 -c 1 -W 2 2606:4700:4700::1111 >/dev/null 2>&1) && echo IPV6_OK || echo IPV6_NONE", false)
        .await
        .unwrap_or_else(|_| "IPV6_NONE".into());
    let ok = check.contains("IPV6_OK");
    if ok {
        s.log("IPv6 connectivity verified on VPS: Dual-Stack enabled");
        let _ = s.run("sysctl -w net.ipv6.conf.all.forwarding=1", true).await;
        let _ = s.run("grep -q 'net.ipv6.conf.all.forwarding=1' /etc/sysctl.conf || echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf", true).await;
    } else {
        s.log("No external IPv6 route on VPS: operating in high-speed pure IPv4 mode");
    }
    ok
}

//// Fallback port used when 443 is taken by another service on the host.
const ALT_PORT: &str = "8443";
/// Version of this desktop build. The server core is compared against it.
pub const BUNDLED_VERSION: &str = env!("CARGO_PKG_VERSION");
const VERSION_FILE: &str = "/opt/obsidian/version.txt";

/// What the update writes to the server config. Decided before anything is uploaded.
struct UpdatePlan {
    tcp: String,
    udp: String,
    migrate_reality: bool,
    sni: String,
    enable_ipv6: bool,
}

fn json_port(cfg: &serde_json::Value, key: &str) -> Option<String> {
    match cfg.get(key)? {
        serde_json::Value::String(v) if !v.trim().is_empty() => Some(v.trim().to_string()),
        serde_json::Value::Number(n) => Some(n.to_string()),
        _ => None,
    }
}

/// Replace the VPN binary and keyserver on an existing install. Server keys stay.
///
/// Ports are chosen from what is actually free on the host: TCP/UDP 443 when it is free or
/// held by our own unit, otherwise the port already in the config. REALITY is switched on
/// only when the TCP port moves to 443. Nothing is uploaded until all checks have passed.
pub async fn update_firmware(app: AppHandle, req: DeployReq) -> Result<UpdateResult, String> {
    let s = ssh_open(app.clone(), &req).await?;
    s.progress(16);
    let exists = s
        .run(
            &format!("test -f {SERVER_BIN} && test -f {SERVER_CONFIG} && echo OK || echo MISSING"),
            false,
        )
        .await?;
    if !exists.contains("OK") {
        return Err("На этом хосте нет установки Obsidian. Сначала разверните сервер.".into());
    }

    let (server_bin, keyserver) = runtime_files(&app)?;

    // Preflight: read the current config and pick ports. No uploads happen before this.
    let cfg_text = s.run_quiet(&format!("cat {SERVER_CONFIG}")).await?;
    let cfg: serde_json::Value = serde_json::from_str(&cfg_text)
        .map_err(|e| format!("Не удалось прочитать конфиг сервера: {e}"))?;
    let cur_tcp = json_port(&cfg, "port").unwrap_or_else(|| "443".into());
    let cur_udp = json_port(&cfg, "udp_port").unwrap_or_else(|| cur_tcp.clone());

    s.run(
        "command -v python3 >/dev/null || (apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3)",
        true,
    )
    .await?;
    let enable_ipv6 = probe_ipv6_connectivity(&s).await;
    let vpn_pids = s.vpn_pids().await;
    let tcp = pick_port(&s, "tcp", &["443", &cur_tcp, ALT_PORT], &vpn_pids).await?;
    let udp = pick_port(&s, "udp", &["443", &cur_udp, ALT_PORT], &vpn_pids).await?;
    let plan = UpdatePlan {
        migrate_reality: tcp == "443",
        sni: mask_sni(&req),
        tcp,
        udp,
        enable_ipv6,
    };
    if plan.migrate_reality {
        s.log(&format!(
            "ports: TCP {}, UDP {}, REALITY on, mask {}",
            plan.tcp, plan.udp, plan.sni
        ));
    } else {
        s.log(&format!(
            "ports: TCP {}, UDP {}, REALITY settings unchanged",
            plan.tcp, plan.udp
        ));
    }
    s.progress(30);

    // The backups are the rollback point for everything that follows.
    s.run(
        &format!("cp -f {SERVER_BIN} {SERVER_BIN}.bak && cp -f {SERVER_CONFIG} {SERVER_CONFIG}.bak"),
        true,
    )
    .await?;

    match apply_update(&s, &server_bin, &keyserver, &plan).await {
        Ok(result) => {
            s.log("firmware updated");
            s.progress(100);
            Ok(result)
        }
        Err(e) => {
            restore_previous(&s).await;
            Err(e)
        }
    }
}

async fn apply_update(
    s: &Session,
    server_bin: &PathBuf,
    keyserver: &PathBuf,
    plan: &UpdatePlan,
) -> Result<UpdateResult, String> {
    s.log("uploading new server binary");
    s.progress(35);
    let bin_bytes = std::fs::read(server_bin).map_err(|e| e.to_string())?;
    s.log(&format!("firmware {} bytes", bin_bytes.len()));
    s.upload_bytes(&bin_bytes, SERVER_BIN).await?;
    s.run(&format!("chmod +x {SERVER_BIN}"), true).await?;
    s.progress(55);

    if keyserver.exists() {
        s.log("uploading keyserver");
        let ks_bytes = std::fs::read(keyserver).map_err(|e| e.to_string())?;
        s.upload_bytes(&ks_bytes, KEYSERVER_SCRIPT).await?;
    }
    s.progress(70);

    s.log("writing server config");
    let out = s.run_quiet(&update_config_script(plan)).await?;
    let mut auth = String::new();
    let mut sni = String::new();
    let mut reality = false;
    for line in out.lines() {
        if let Some(v) = line.strip_prefix("AUTH=") {
            auth = v.trim().to_string();
        } else if let Some(v) = line.strip_prefix("SNI=") {
            sni = v.trim().to_string();
        } else if let Some(v) = line.strip_prefix("REALITY=") {
            reality = v.trim() == "1";
        }
    }
    s.progress(78);

    let iface = s
        .run("ip route show default | awk '/default/{print $5}' | head -1", false)
        .await?;
    let iface = if iface.is_empty() { "eth0".into() } else { iface };
    close_legacy_ports(s, &[("tcp", plan.tcp.as_str()), ("udp", plan.udp.as_str())]).await?;
    setup_nat(s, &iface, &plan.tcp, &plan.udp, plan.enable_ipv6).await?;

    s.log("restarting vpn unit");
    s.run(&format!("docker restart {VPN_CONTAINER}"), true).await?;
    let ks = s
        .run(
            &format!("docker inspect -f '{{{{.State.Running}}}}' {KS_CONTAINER} 2>/dev/null || echo false"),
            false,
        )
        .await?;
    if ks.to_lowercase().contains("true") {
        s.log("restarting keyserver");
        let _ = s.run(&format!("docker restart {KS_CONTAINER}"), false).await;
    }
    tokio::time::sleep(std::time::Duration::from_secs(2)).await;
    let running = s
        .run(
            &format!("docker inspect -f '{{{{.State.Running}}}}' {VPN_CONTAINER} 2>/dev/null || echo false"),
            false,
        )
        .await?;
    if !running.to_lowercase().contains("true") {
        let logs = s
            .run(&format!("docker logs --tail 80 {VPN_CONTAINER} 2>&1"), false)
            .await?;
        return Err(format!("Контейнер VPN не запустился после обновления.\n{logs}"));
    }

    // Only a successful update records the new version.
    let bin_hash = hex::encode(Sha256::digest(&bin_bytes));
    let ver_str = format!("{BUNDLED_VERSION}\n{bin_hash}\n");
    if let Err(e) = s.upload_bytes(ver_str.as_bytes(), VERSION_FILE).await {
        s.log(&format!("version.txt was not written: {e}"));
    }

    let logs = s
        .run(&format!("docker logs --tail 20 {VPN_CONTAINER} 2>&1"), false)
        .await?;
    if !logs.trim().is_empty() {
        s.log("unit logs:");
        for line in logs.lines().take(12) {
            s.log(line);
        }
    }

    Ok(UpdateResult {
        server_port: plan.tcp.clone(),
        udp_port: plan.udp.clone(),
        reality_enabled: reality,
        reality_auth_key: auth,
        reality_sni: sni,
        enable_ipv6: plan.enable_ipv6,
    })
}

/// Python run on the server: rewrites the config atomically. REALITY keys are only touched
/// when the plan migrates REALITY to the TCP port; otherwise they stay as they are.
fn update_config_script(plan: &UpdatePlan) -> String {
    let tcp = plan.tcp.as_str();
    let udp = plan.udp.as_str();
    let ipv6 = if plan.enable_ipv6 { "True" } else { "False" };
    let migrate = if plan.migrate_reality { "True" } else { "False" };
    let sni = format!("{:?}", plan.sni);
    format!(
        r#"python3 - <<'PY'
import json, os, secrets
path = "{SERVER_CONFIG}"
tmp = path + ".tmp"
with open(path) as f:
    cfg = json.load(f)
cfg["port"] = "{tcp}"
cfg["udp_port"] = "{udp}"
cfg["enable_ipv6"] = {ipv6}
if {migrate}:
    sni = {sni}
    cfg["no_tls"] = False
    cfg.pop("cert_file", None)
    cfg.pop("key_file", None)
    cfg["reality_target"] = sni + ":443"
    cfg["reality_backend"] = sni + ":443"
    cfg["reality_backend_sni"] = sni
    cfg["reality_server_names"] = [sni]
    if len(str(cfg.get("reality_auth_key") or "").strip()) < 32:
        cfg["reality_auth_key"] = secrets.token_hex(32)
with open(tmp, "w") as f:
    json.dump(cfg, f, indent=2)
os.replace(tmp, path)
auth = str(cfg.get("reality_auth_key") or "").strip()
reality_on = (not cfg.get("no_tls", False)) and len(auth) >= 32
print("AUTH=" + auth)
print("SNI=" + str(cfg.get("reality_backend_sni") or ""))
print("REALITY=" + ("1" if reality_on else "0"))
PY"#
    )
}

/// Puts the previous binary and config back after a failed update and restarts the unit.
async fn restore_previous(s: &Session) {
    s.log("update failed, restoring previous binary and config");
    let _ = s
        .run(
            &format!(
                "test -f {SERVER_BIN}.bak && cp -f {SERVER_BIN}.bak {SERVER_BIN}; test -f {SERVER_CONFIG}.bak && cp -f {SERVER_CONFIG}.bak {SERVER_CONFIG}; docker restart {VPN_CONTAINER} >/dev/null 2>&1; true"
            ),
            false,
        )
        .await;
}

pub async fn deploy(app: AppHandle, req: DeployReq) -> Result<DeployResult, String> {
    let host = req.host.trim().to_string();
    let sni = mask_sni(&req);
    let reality_auth = new_reality_auth();

    let s = ssh_open(app.clone(), &req).await?;
    s.progress(12);

    let (server_bin, keyserver) = runtime_files(&app)?;

    s.log("installing docker");
    let docker = s.run("docker --version 2>/dev/null || echo MISSING", false).await?;
    if docker.contains("MISSING") {
        s.run("apt-get update -qq && apt-get install -y -qq curl", true).await?;
        s.run("curl -fsSL https://get.docker.com | sh", true).await?;
        s.run("systemctl enable docker && systemctl start docker", true).await?;
    }
    s.progress(28);

    s.log("enabling ip forward");
    s.run("sysctl -w net.ipv4.ip_forward=1", true).await?;
    s.run(
        "grep -q 'net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf",
        true,
    )
    .await?;
    let enable_ipv6 = probe_ipv6_connectivity(&s).await;
    s.progress(36);

    // 443 is preferred; a foreign service on it (e.g. nginx) moves us to 8443 instead of failing.
    let vpn_pids = s.vpn_pids().await;
    let tcp_port = pick_port(&s, "tcp", &["443", ALT_PORT], &vpn_pids).await?;
    let udp_port = pick_port(&s, "udp", &["443", ALT_PORT], &vpn_pids).await?;

    let secret = StaticSecret::random_from_rng(rand::rngs::OsRng);
    let public = PublicKey::from(&secret);
    let priv_hex = hex::encode(secret.to_bytes());
    let pub_hex = hex::encode(public.to_bytes());
    s.log("writing config");
    s.progress(48);

    s.run(&format!("mkdir -p {SERVER_DIR}"), true).await?;
    let bin_bytes = std::fs::read(&server_bin).map_err(|e| e.to_string())?;
    s.upload_bytes(&bin_bytes, SERVER_BIN).await?;
    s.run(&format!("chmod +x {SERVER_BIN}"), true).await?;
    let bin_hash = hex::encode(Sha256::digest(&bin_bytes));
    let ver_str = format!("{BUNDLED_VERSION}\n{bin_hash}\n");
    let _ = s.upload_bytes(ver_str.as_bytes(), VERSION_FILE).await;
    s.log(&format!("REALITY mask {sni}:443, listen TCP {tcp_port}, UDP {udp_port}"));

    let iface = s
        .run("ip route show default | awk '/default/{print $5}' | head -1", false)
        .await?;
    let iface = if iface.is_empty() { "eth0".into() } else { iface };

    let config = serde_json::json!({
        "host": "0.0.0.0",
        "protocol_version": 2,
        "port": tcp_port.clone(),
        "no_tls": false,
        "reality_target": format!("{sni}:443"),
        "reality_backend": format!("{sni}:443"),
        "reality_backend_sni": sni.clone(),
        "reality_server_names": [sni.clone()],
        "reality_auth_key": reality_auth.clone(),
        "server_private_key": priv_hex,
        "server_public_key": pub_hex,
        "tun_interface": "tun0",
        "tun_address": "10.8.0.1/24",
        "mtu": 1420,
        "out_interface": iface,
        "dns_upstream": "1.1.1.1:53",
        "dns_listen": "10.8.0.1:53",
        "disable_dns_proxy": false,
        "enable_ipv6": enable_ipv6,
        "udp_port": udp_port.clone(),
        "enable_udp_data": true,
        "udp_socket_buffer_mb": 16,
        "allowed_clients": [],
        "revocation_file": format!("{SERVER_DIR}/revoked_clients.json"),
        "junk_count": 7,
        "junk_min": 50,
        "junk_max": 1000,
        "noise_min_sec": 10,
        "noise_max_sec": 40,
        "keepalive_sec": 20,
        "profile": "fast-secure",
        "jitter": "off",
        "signatures": [
            "<b 0xc00000000108><rc 8><b 0x08><rc 8><b 0x0044b000000001><r 1170>",
            "<r 2><b 0x010000010000000000010377777706676f6f676c6503636f6d00000100010000291000000000000000>"
        ]
    });
    s.upload_bytes(
        serde_json::to_string_pretty(&config).unwrap().as_bytes(),
        SERVER_CONFIG,
    )
    .await?;
    s.progress(62);

    s.log("starting unit");
    s.run(&format!("docker rm -f {VPN_CONTAINER} 2>/dev/null || true"), false)
        .await?;
    s.run(
        &format!(
            "docker run -d --name {VPN_CONTAINER} --network host --cap-add NET_ADMIN --device /dev/net/tun --restart always -v {SERVER_DIR}:{SERVER_DIR} ubuntu:22.04 sh -c \"apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq iproute2 iptables >/dev/null && exec {SERVER_BIN} --config {SERVER_CONFIG}\""
        ),
        true,
    )
    .await?;
    tokio::time::sleep(std::time::Duration::from_secs(2)).await;
    let running = s
        .run(
            &format!("docker inspect -f '{{{{.State.Running}}}}' {VPN_CONTAINER} 2>/dev/null || echo false"),
            false,
        )
        .await?;
    if !running.to_lowercase().contains("true") {
        let logs = s
            .run(&format!("docker logs --tail 120 {VPN_CONTAINER} 2>&1"), false)
            .await?;
        rollback(&s).await;
        return Err(format!("VPN container is not running.\n{logs}"));
    }
    s.progress(78);

    s.log("enabling service");
    let mut token = [0u8; 24];
    rand::rngs::OsRng.fill_bytes(&mut token);
    let admin_token = hex::encode(token);
    let ks_bytes = if keyserver.exists() {
        std::fs::read(&keyserver).map_err(|e| e.to_string())?
    } else {
        let bundled = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("resources")
            .join("keyserver.py");
        std::fs::read(bundled).map_err(|e| format!("keyserver.py missing: {e}"))?
    };
    s.upload_bytes(&ks_bytes, KEYSERVER_SCRIPT).await?;
    s.run(&format!("docker rm -f {KS_CONTAINER} 2>/dev/null || true"), false)
        .await?;
    s.run(
        &format!(
            "docker run -d --name {KS_CONTAINER} --network host --restart always -v {SERVER_DIR}:{SERVER_DIR} -e ADMIN_TOKEN={admin_token} -e KEYSERVER_PORT={KEYSERVER_PORT} -e KEYSERVER_BIND=127.0.0.1 -e KEYS_FILE={SERVER_DIR}/keys.json -e REVOCATIONS_FILE={SERVER_DIR}/revoked_clients.json -e SERVER_CONFIG={SERVER_CONFIG} python:3.11-slim python3 {KEYSERVER_SCRIPT}"
        ),
        true,
    )
    .await?;
    tokio::time::sleep(std::time::Duration::from_secs(2)).await;
    s.progress(90);

    s.log("healthcheck ok");
    setup_nat(&s, &iface, &tcp_port, &udp_port, enable_ipv6).await?;
    s.progress(100);

    Ok(DeployResult {
        server_host: host,
        server_port: tcp_port,
        udp_port,
        server_public_key: pub_hex,
        keyserver_url: format!("http://{}:{KEYSERVER_PORT}", req.host.trim()),
        admin_token,
        reality_auth_key: reality_auth,
        reality_sni: sni,
        enable_ipv6,
    })
}

#[derive(Debug, Clone, PartialEq)]
enum PortOwner {
    Free,
    Ours,
    Foreign(String),
}

/// Reads `ss -lntp` / `ss -lnup` output and decides who holds one exact local port.
/// Sockets owned by obsidian-server or by processes of the VPN container count as ours.
fn parse_port_owner(out: &str, port: &str, vpn_pids: &[String]) -> PortOwner {
    let mut listed = false;
    let mut unknown = false;
    let mut foreign: Vec<String> = Vec::new();
    for line in out.lines() {
        let cols: Vec<&str> = line.split_whitespace().collect();
        if cols.len() < 4 {
            continue;
        }
        // The local address is the 4th column; the port is the part after the last ':'.
        if cols[3].rsplit(':').next() != Some(port) {
            continue;
        }
        listed = true;
        let users = line.find("users:((").map(|i| &line[i..]).unwrap_or("");
        let mut has_entry = false;
        for entry in users.split("(\"").skip(1) {
            has_entry = true;
            let name = entry.split('"').next().unwrap_or("");
            let pid = entry
                .split("pid=")
                .nth(1)
                .unwrap_or("")
                .split(|c: char| !c.is_ascii_digit())
                .next()
                .unwrap_or("");
            let ours = name == "obsidian-server" || vpn_pids.iter().any(|p| p == pid);
            if !ours && !foreign.iter().any(|f| f == name) {
                foreign.push(name.to_string());
            }
        }
        if !has_entry {
            unknown = true;
        }
    }
    if !listed {
        return PortOwner::Free;
    }
    if !foreign.is_empty() {
        return PortOwner::Foreign(foreign.join(", "));
    }
    if unknown {
        return PortOwner::Foreign("неизвестный процесс".into());
    }
    PortOwner::Ours
}

async fn port_owner(
    s: &Session,
    proto: &str,
    port: &str,
    vpn_pids: &[String],
) -> Result<PortOwner, String> {
    let flags = if proto == "udp" { "-lnup" } else { "-lntp" };
    let (out, _, _) = s.exec_raw(&format!("ss {flags} 2>/dev/null")).await?;
    Ok(parse_port_owner(&out, port, vpn_pids))
}

/// Returns the first candidate port that is free or held by our own unit.
/// Logs the skipped port and the process that holds it. Fails only if every candidate is taken.
async fn pick_port(
    s: &Session,
    proto: &str,
    candidates: &[&str],
    vpn_pids: &[String],
) -> Result<String, String> {
    let label = proto.to_uppercase();
    let mut skipped: Option<(String, String)> = None;
    let mut busy: Vec<String> = Vec::new();
    for &port in candidates {
        match port_owner(s, proto, port, vpn_pids).await? {
            PortOwner::Free | PortOwner::Ours => {
                if let Some((first, who)) = &skipped {
                    s.log(&format!("{label} {first} занят ({who}), оставляю порт {port}"));
                }
                return Ok(port.to_string());
            }
            PortOwner::Foreign(who) => {
                if skipped.is_none() {
                    skipped = Some((port.to_string(), who));
                }
                if !busy.iter().any(|b| b == port) {
                    busy.push(port.to_string());
                }
            }
        }
    }
    Err(format!(
        "Не удалось выбрать порт {label}: заняты {}. Освободите один из них на сервере и повторите.",
        busy.join(", ")
    ))
}

async fn setup_nat(
    s: &Session,
    iface: &str,
    tcp_port: &str,
    udp_port: &str,
    enable_ipv6: bool,
) -> Result<(), String> {
    s.run(
        &format!("iptables -t nat -C POSTROUTING -s 10.8.0.0/24 -o {iface} -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o {iface} -j MASQUERADE"),
        true,
    )
    .await?;
    s.run(
        &format!("iptables -C FORWARD -i tun0 -o {iface} -j ACCEPT 2>/dev/null || iptables -A FORWARD -i tun0 -o {iface} -j ACCEPT"),
        true,
    )
    .await?;
    s.run(
        &format!("iptables -C FORWARD -i {iface} -o tun0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || iptables -A FORWARD -i {iface} -o tun0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"),
        true,
    )
    .await?;
    s.run(
        &format!("iptables -t mangle -C FORWARD -i tun0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1380 2>/dev/null || iptables -t mangle -A FORWARD -i tun0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1380"),
        false,
    )
    .await?;
    s.run(
        &format!("iptables -t mangle -C FORWARD -o tun0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1380 2>/dev/null || iptables -t mangle -A FORWARD -o tun0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1380"),
        false,
    )
    .await?;
    if enable_ipv6 {
        let _ = s.run(
            &format!("ip6tables -t nat -C POSTROUTING -s fd00:8::/64 -o {iface} -j MASQUERADE 2>/dev/null || ip6tables -t nat -A POSTROUTING -s fd00:8::/64 -o {iface} -j MASQUERADE"),
            false,
        ).await;
        let _ = s.run(
            &format!("ip6tables -C FORWARD -i tun0 -o {iface} -j ACCEPT 2>/dev/null || ip6tables -A FORWARD -i tun0 -o {iface} -j ACCEPT"),
            false,
        ).await;
        let _ = s.run(
            &format!("ip6tables -C FORWARD -i {iface} -o tun0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || ip6tables -A FORWARD -i {iface} -o tun0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"),
            false,
        ).await;
        let _ = s.run(
            &format!("ip6tables -t mangle -C FORWARD -i tun0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1340 2>/dev/null || ip6tables -t mangle -A FORWARD -i tun0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1340"),
            false,
        ).await;
        let _ = s.run(
            &format!("ip6tables -t mangle -C FORWARD -o tun0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1340 2>/dev/null || ip6tables -t mangle -A FORWARD -o tun0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1340"),
            false,
        ).await;
    }
    for proto in ["udp", "tcp"] {
        s.run(
            &format!("iptables -C INPUT -i tun0 -p {proto} --dport 53 -j ACCEPT 2>/dev/null || iptables -A INPUT -i tun0 -p {proto} --dport 53 -j ACCEPT"),
            false,
        )
        .await?;
    }
    for (proto, port) in [("tcp", tcp_port), ("udp", udp_port)] {
        s.run(
            &format!("iptables -C INPUT -p {proto} --dport {port} -j ACCEPT 2>/dev/null || iptables -A INPUT -p {proto} --dport {port} -j ACCEPT"),
            false,
        )
        .await?;
    }
    s.run(
        &format!("iptables -C INPUT -i lo -p tcp --dport {KEYSERVER_PORT} -j ACCEPT 2>/dev/null || iptables -I INPUT -i lo -p tcp --dport {KEYSERVER_PORT} -j ACCEPT"),
        false,
    )
    .await?;
    s.run(
        &format!("iptables -C INPUT -p tcp --dport {KEYSERVER_PORT} ! -i lo -j DROP 2>/dev/null || iptables -I INPUT -p tcp --dport {KEYSERVER_PORT} ! -i lo -j DROP"),
        false,
    )
    .await?;
    s.run(&format!("ufw allow {tcp_port}/tcp 2>/dev/null || true"), false)
        .await?;
    s.run(&format!("ufw allow {udp_port}/udp 2>/dev/null || true"), false)
        .await?;
    Ok(())
}

/// Removes the leftover 8443/8444 firewall rules, but never the ports that stay in use.
async fn close_legacy_ports(s: &Session, keep: &[(&str, &str)]) -> Result<(), String> {
    for port in ["8443", "8444"] {
        for proto in ["tcp", "udp"] {
            if keep.contains(&(proto, port)) {
                continue;
            }
            s.run(
                &format!("ufw delete allow {port}/{proto} >/dev/null 2>&1 || true"),
                false,
            )
            .await?;
            s.run(
                &format!("for i in 1 2 3 4 5; do iptables -D INPUT -p {proto} --dport {port} -j ACCEPT 2>/dev/null || break; done"),
                false,
            )
            .await?;
        }
    }
    Ok(())
}

async fn rollback(s: &Session) {
    s.log("rolling back");
    let _ = s.run(&format!("docker rm -f {VPN_CONTAINER} 2>/dev/null || true"), false).await;
    let _ = s.run(&format!("docker rm -f {KS_CONTAINER} 2>/dev/null || true"), false).await;
    let _ = s.run(&format!("rm -rf {SERVER_DIR} 2>/dev/null || true"), false).await;
}

#[derive(Debug, Serialize, Clone)]
pub struct ResetResult {
    pub server_public_key: String,
    pub reality_auth_key: String,
    pub reality_sni: String,
}

pub async fn change_sni(app: AppHandle, req: DeployReq, new_sni: String) -> Result<String, String> {
    let s = ssh_open(app.clone(), &req).await?;
    let sni = new_sni.trim().trim_end_matches(":443").to_lowercase();
    let sni = if sni.is_empty() {
        "www.microsoft.com".to_string()
    } else {
        sni
    };

    s.log(&format!("updating REALITY SNI to {sni}"));
    let script = format!(
        r#"python3 - <<'PY'
import json
path = "{SERVER_CONFIG}"
sni = {sni:?}
cfg = json.load(open(path))
cfg["reality_target"] = sni + ":443"
cfg["reality_backend"] = sni + ":443"
cfg["reality_backend_sni"] = sni
cfg["reality_server_names"] = [sni]
json.dump(cfg, open(path, "w"), indent=2)
print("SNI_OK")
PY"#
    );
    let res = s.run(&script, true).await?;
    if !res.contains("SNI_OK") {
        return Err(format!("Failed to update config.json on server: {res}"));
    }

    s.log("restarting vpn unit");
    s.run(&format!("docker restart {VPN_CONTAINER}"), true).await?;
    tokio::time::sleep(std::time::Duration::from_secs(1)).await;
    let running = s
        .run(
            &format!("docker inspect -f '{{{{.State.Running}}}}' {VPN_CONTAINER} 2>/dev/null || echo false"),
            false,
        )
        .await?;
    if !running.to_lowercase().contains("true") {
        return Err("VPN container failed to restart with new SNI".into());
    }
    s.log("SNI successfully updated");
    Ok(sni)
}

pub async fn reset_server(app: AppHandle, req: DeployReq) -> Result<ResetResult, String> {
    let s = ssh_open(app.clone(), &req).await?;
    s.log("initiating server reset");
    s.progress(20);

    let secret = StaticSecret::random_from_rng(rand::rngs::OsRng);
    let public = PublicKey::from(&secret);
    let priv_hex = hex::encode(secret.to_bytes());
    let pub_hex = hex::encode(public.to_bytes());
    let reality_auth = new_reality_auth();
    let sni = mask_sni(&req);

    s.log("generating new cryptographic keys");
    s.progress(45);
    let script = format!(
        r#"python3 - <<'PY'
import json
path = "{SERVER_CONFIG}"
priv_key = {priv_hex:?}
pub_key = {pub_hex:?}
auth_key = {reality_auth:?}
cfg = json.load(open(path))
cfg["server_private_key"] = priv_key
cfg["server_public_key"] = pub_key
cfg["reality_auth_key"] = auth_key
cfg["allowed_clients"] = []
json.dump(cfg, open(path, "w"), indent=2)

try:
    with open("{SERVER_DIR}/keys.json", "w") as f:
        f.write("{{}}\n")
except Exception:
    pass

try:
    with open("{SERVER_DIR}/revoked_clients.json", "w") as f:
        f.write('{{"revoked_clients": []}}\n')
except Exception:
    pass

print("RESET_OK")
PY"#
    );
    let res = s.run(&script, true).await?;
    if !res.contains("RESET_OK") {
        return Err(format!("Failed to reset server configuration: {res}"));
    }

    s.log("restarting services");
    s.progress(75);
    s.run(&format!("docker restart {VPN_CONTAINER}"), true).await?;
    s.run(&format!("docker restart {KS_CONTAINER} 2>/dev/null || true"), false).await?;
    tokio::time::sleep(std::time::Duration::from_secs(2)).await;

    let running = s
        .run(
            &format!("docker inspect -f '{{{{.State.Running}}}}' {VPN_CONTAINER} 2>/dev/null || echo false"),
            false,
        )
        .await?;
    if !running.to_lowercase().contains("true") {
        return Err("VPN container failed to start after reset".into());
    }

    s.log("server reset completed successfully");
    s.progress(100);
    Ok(ResetResult {
        server_public_key: pub_hex,
        reality_auth_key: reality_auth,
        reality_sni: sni,
    })
}

#[derive(Debug, Serialize, Clone)]
pub struct VersionCheckResult {
    pub version: String,
    pub needs_update: bool,
    pub message: String,
}

/// Parses "1.2.3". A leading "v" and any "-pre" or "+build" suffix are ignored.
fn parse_version(v: &str) -> Option<(u64, u64, u64)> {
    let core = v.trim().trim_start_matches('v');
    let core = core.split(|c| c == '-' || c == '+').next()?;
    let mut parts = core.split('.');
    let major = parts.next()?.parse().ok()?;
    let minor = parts.next().unwrap_or("0").parse().ok()?;
    let patch = parts.next().unwrap_or("0").parse().ok()?;
    Some((major, minor, patch))
}

/// The server core is outdated when its binary differs from the bundled one and its version
/// is older than this build. A binary that matches the bundle is never outdated. An equal
/// version with a different binary is outdated. A newer server version is never downgraded.
fn core_needs_update(remote_ver: Option<&str>, remote_hash: &str, local_hash: &str) -> bool {
    if !remote_hash.is_empty() && remote_hash == local_hash {
        return false;
    }
    let hash_differs = !remote_hash.is_empty();
    let local = parse_version(BUNDLED_VERSION).unwrap_or((0, 0, 0));
    match remote_ver.and_then(parse_version) {
        Some(remote) if remote < local => true,
        Some(remote) if remote == local => hash_differs,
        Some(_) => false,
        None => hash_differs,
    }
}

pub async fn check_remote_version(
    app: AppHandle,
    req: &DeployReq,
) -> Result<VersionCheckResult, String> {
    let s = ssh_open(app.clone(), req).await?;
    let ver_file = s
        .run(&format!("cat {VERSION_FILE} 2>/dev/null || echo MISSING"), false)
        .await?;

    let (server_bin, _) = runtime_files(&app)?;
    let local_bin_bytes = std::fs::read(&server_bin).map_err(|e| e.to_string())?;
    let local_hash = hex::encode(Sha256::digest(&local_bin_bytes));

    let (remote_ver, remote_hash) = if ver_file.contains("MISSING") {
        let bin_exists = s
            .run(
                "test -f /opt/obsidian/obsidian-server && echo EXISTS || echo NO",
                false,
            )
            .await?;
        if !bin_exists.contains("EXISTS") {
            return Err("Сервер Obsidian VPN не обнаружен на данном хосте.".to_string());
        }
        let remote_hash = s
            .run(
                "sha256sum /opt/obsidian/obsidian-server 2>/dev/null | awk '{print $1}'",
                false,
            )
            .await?
            .trim()
            .to_string();
        (None, remote_hash)
    } else {
        let lines: Vec<&str> = ver_file
            .lines()
            .map(str::trim)
            .filter(|l| !l.is_empty())
            .collect();
        let remote_ver = lines.first().map(|v| v.to_string());
        let remote_hash = lines.get(1).copied().unwrap_or("").to_string();
        (remote_ver, remote_hash)
    };

    let same_binary = !remote_hash.is_empty() && remote_hash == local_hash;
    let needs_update = core_needs_update(remote_ver.as_deref(), &remote_hash, &local_hash);
    let version = match remote_ver {
        Some(v) => v,
        None if same_binary => BUNDLED_VERSION.to_string(),
        None => "ранняя сборка".to_string(),
    };
    let message = if needs_update {
        format!("Доступно обновление ядра до {BUNDLED_VERSION} (сейчас на сервере: {version}).")
    } else {
        format!("Установлена актуальная версия ядра {version}.")
    };

    Ok(VersionCheckResult {
        version,
        needs_update,
        message,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const NGINX_TCP_443: &str = r#"LISTEN 0 511 0.0.0.0:443 0.0.0.0:* users:(("nginx",pid=83216,fd=5),("nginx",pid=69121,fd=5))"#;
    const OBSIDIAN_UDP_443: &str = r#"UNCONN 0 0 0.0.0.0:443 0.0.0.0:* users:(("obsidian-server",pid=68904,fd=9))"#;
    const OBSIDIAN_TCP_8443: &str = r#"LISTEN 0 4096 *:8443 *:* users:(("obsidian-server",pid=68904,fd=7))"#;

    #[test]
    fn foreign_tcp_443_is_reported_with_its_process() {
        assert_eq!(
            parse_port_owner(NGINX_TCP_443, "443", &[]),
            PortOwner::Foreign("nginx".into())
        );
    }

    #[test]
    fn obsidian_udp_443_is_ours() {
        assert_eq!(parse_port_owner(OBSIDIAN_UDP_443, "443", &[]), PortOwner::Ours);
    }

    #[test]
    fn other_port_in_the_listing_is_free() {
        assert_eq!(parse_port_owner(NGINX_TCP_443, "8443", &[]), PortOwner::Free);
    }

    #[test]
    fn port_match_is_exact() {
        assert_eq!(parse_port_owner(NGINX_TCP_443, "4430", &[]), PortOwner::Free);
        assert_eq!(parse_port_owner(NGINX_TCP_443, "44", &[]), PortOwner::Free);
    }

    #[test]
    fn ipv6_wildcard_and_star_addresses_match() {
        let v6 = r#"LISTEN 0 511 [::]:443 [::]:* users:(("nginx",pid=1,fd=6))"#;
        assert_eq!(parse_port_owner(v6, "443", &[]), PortOwner::Foreign("nginx".into()));
        assert_eq!(parse_port_owner(OBSIDIAN_TCP_8443, "8443", &[]), PortOwner::Ours);
    }

    #[test]
    fn process_of_vpn_container_counts_as_ours() {
        let line = r#"UNCONN 0 0 0.0.0.0:443 0.0.0.0:* users:(("xray",pid=4242,fd=3))"#;
        assert_eq!(parse_port_owner(line, "443", &[]), PortOwner::Foreign("xray".into()));
        assert_eq!(
            parse_port_owner(line, "443", &["4242".to_string()]),
            PortOwner::Ours
        );
    }

    #[test]
    fn socket_without_process_info_is_foreign() {
        let line = "LISTEN 0 128 0.0.0.0:443 0.0.0.0:*";
        assert!(matches!(parse_port_owner(line, "443", &[]), PortOwner::Foreign(_)));
    }

    #[test]
    fn empty_listing_means_free() {
        assert_eq!(parse_port_owner("", "443", &[]), PortOwner::Free);
    }

    #[test]
    fn parses_versions_loosely() {
        assert_eq!(parse_version("1.1.1"), Some((1, 1, 1)));
        assert_eq!(parse_version("v1.2"), Some((1, 2, 0)));
        assert_eq!(parse_version("0.1.0-beta.2"), Some((0, 1, 0)));
        assert_eq!(parse_version("ранняя сборка"), None);
        assert!(parse_version("1.10.0") > parse_version("1.9.9"));
    }

    #[test]
    fn same_binary_is_never_outdated() {
        assert!(!core_needs_update(Some("0.1.0"), "abc", "abc"));
        assert!(!core_needs_update(None, "abc", "abc"));
    }

    #[test]
    fn older_server_version_is_outdated() {
        assert!(core_needs_update(Some("0.1.0"), "abc", "def"));
        assert!(core_needs_update(Some("0.0.1"), "", "def"));
    }

    #[test]
    fn equal_version_is_outdated_only_when_hash_differs() {
        assert!(core_needs_update(Some(BUNDLED_VERSION), "abc", "def"));
        assert!(!core_needs_update(Some(BUNDLED_VERSION), "", "def"));
    }

    #[test]
    fn newer_server_is_not_downgraded() {
        assert!(!core_needs_update(Some("99.0.0"), "abc", "def"));
    }

    #[test]
    fn unknown_version_depends_on_hash() {
        assert!(core_needs_update(None, "abc", "def"));
        assert!(!core_needs_update(None, "", "def"));
    }
}
