use crate::storage::{self, ServerProfile};
use serde::Serialize;
use std::fs::{self, OpenOptions};
use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};
use tauri::{AppHandle, Emitter, Manager};

#[cfg(windows)]
const CREATE_NO_WINDOW: u32 = 0x08000000;

#[derive(Debug, Clone, Serialize)]
pub struct VpnSnapshot {
    pub status: String,
    pub error: Option<String>,
    pub detail: Option<String>,
    pub progress: u32,
    pub stage: Option<String>,
    pub connected_at: Option<u64>,
    pub profile_id: Option<String>,
}

pub struct Vpn {
    child: Mutex<Option<Child>>,
    status: Mutex<String>,
    error: Mutex<Option<String>>,
    detail: Mutex<Option<String>>,
    progress: Mutex<u32>,
    stage: Mutex<Option<String>>,
    connected_at: Mutex<Option<u64>>,
    profile_id: Mutex<Option<String>>,
}

impl Vpn {
    pub fn new() -> Self {
        Self {
            child: Mutex::new(None),
            status: Mutex::new("disconnected".into()),
            error: Mutex::new(None),
            detail: Mutex::new(None),
            progress: Mutex::new(0),
            stage: Mutex::new(None),
            connected_at: Mutex::new(None),
            profile_id: Mutex::new(None),
        }
    }

    pub fn snapshot(&self) -> VpnSnapshot {
        VpnSnapshot {
            status: self.status.lock().unwrap().clone(),
            error: self.error.lock().unwrap().clone(),
            detail: self.detail.lock().unwrap().clone(),
            progress: *self.progress.lock().unwrap(),
            stage: self.stage.lock().unwrap().clone(),
            connected_at: *self.connected_at.lock().unwrap(),
            profile_id: self.profile_id.lock().unwrap().clone(),
        }
    }

    pub fn connect(&self, app: &AppHandle, mut profile: ServerProfile) -> Result<(), String> {
        if !is_admin() {
            relaunch_as_admin(&["--connect"])?;
            return Err("Restarting as Administrator…".into());
        }

        self.disconnect_inner();
        *self.status.lock().unwrap() = "connecting".into();
        *self.error.lock().unwrap() = None;
        *self.detail.lock().unwrap() = Some("Инициализация соединения...".into());
        *self.progress.lock().unwrap() = 10;
        *self.stage.lock().unwrap() = Some("Инициализация (1/4)".into());
        *self.profile_id.lock().unwrap() = Some(profile.id.clone());
        let _ = app.emit("vpn-status", self.snapshot());

        let exe = extract_runtime(app)?;
        let cfg = storage::write_client_config(&mut profile)?;
        let mut profiles = storage::load_profiles();
        if let Some(p) = profiles.iter_mut().find(|p| p.id == profile.id) {
            *p = profile.clone();
        }
        let _ = storage::save_profiles(&profiles);

        let mut cmd = Command::new(&exe);
        cmd.arg("--config")
            .arg(&cfg)
            .arg("--debug")
            .current_dir(exe.parent().unwrap())
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        #[cfg(windows)]
        {
            use std::os::windows::process::CommandExt;
            cmd.creation_flags(CREATE_NO_WINDOW);
        }
        let mut child = cmd
            .spawn()
            .map_err(|e| format!("Failed to start client: {e}"))?;
        let logs = tee_child_output(&mut child);
        *self.child.lock().unwrap() = Some(child);

        let app2 = app.clone();
        std::thread::spawn(move || {
            let mut last_emit = String::new();
            loop {
                std::thread::sleep(std::time::Duration::from_millis(250));
                let vpn = app2.state::<Vpn>();
                let mode = vpn.status.lock().unwrap().clone();
                if mode == "disconnected" || mode == "disconnecting" {
                    break;
                }
                let exited = {
                    let mut child = vpn.child.lock().unwrap();
                    match child.as_mut() {
                        Some(c) => c.try_wait().ok().flatten().is_some(),
                        None => break,
                    }
                };
                let dump = logs.lock().unwrap().clone();
                if exited {
                    *vpn.status.lock().unwrap() = "error".into();
                    let msg = humanize_client_log(&dump);
                    *vpn.error.lock().unwrap() = Some(msg.clone());
                    *vpn.detail.lock().unwrap() = Some(msg);
                    *vpn.progress.lock().unwrap() = 0;
                    *vpn.stage.lock().unwrap() = None;
                    *vpn.connected_at.lock().unwrap() = None;
                    *vpn.child.lock().unwrap() = None;
                    let _ = app2.emit("vpn-status", vpn.snapshot());
                    break;
                }
                let current_status = vpn.status.lock().unwrap().clone();
                let (status, detail, progress, stage) = interpret_client_log(&dump, &current_status);
                let changed = {
                    let prev = vpn.status.lock().unwrap().clone();
                    let prev_detail = vpn.detail.lock().unwrap().clone().unwrap_or_default();
                    let prev_progress = *vpn.progress.lock().unwrap();
                    if prev != status {
                        if status == "connected" && prev != "connected" {
                            *vpn.connected_at.lock().unwrap() = Some(now_secs());
                            *vpn.error.lock().unwrap() = None;
                        }
                        if status != "connected" {
                            *vpn.connected_at.lock().unwrap() = None;
                        }
                        *vpn.status.lock().unwrap() = status.clone();
                    }
                    *vpn.detail.lock().unwrap() = Some(detail.clone());
                    *vpn.progress.lock().unwrap() = progress;
                    *vpn.stage.lock().unwrap() = Some(stage.clone());
                    prev != status || prev_detail != detail || prev_progress != progress
                };
                if changed {
                    let key = format!("{status}|{progress}|{detail}");
                    if key != last_emit {
                        last_emit = key;
                        let _ = app2.emit("vpn-status", vpn.snapshot());
                    }
                }
            }
        });
        Ok(())
    }

    pub fn disconnect(&self, app: &AppHandle) {
        *self.status.lock().unwrap() = "disconnecting".into();
        *self.progress.lock().unwrap() = 0;
        *self.stage.lock().unwrap() = Some("Отключение...".into());
        let _ = app.emit("vpn-status", self.snapshot());
        self.disconnect_inner();
        *self.status.lock().unwrap() = "disconnected".into();
        *self.connected_at.lock().unwrap() = None;
        *self.error.lock().unwrap() = None;
        *self.detail.lock().unwrap() = None;
        *self.progress.lock().unwrap() = 0;
        *self.stage.lock().unwrap() = None;
        let _ = app.emit("vpn-status", self.snapshot());
    }

    fn disconnect_inner(&self) {
        if let Some(mut child) = self.child.lock().unwrap().take() {
            // Close stdin so Go client's stdin monitor initiates graceful tun.Close()
            drop(child.stdin.take());
            let start = std::time::Instant::now();
            let mut exited = false;
            while start.elapsed() < std::time::Duration::from_millis(1500) {
                if let Ok(Some(_)) = child.try_wait() {
                    exited = true;
                    break;
                }
                std::thread::sleep(std::time::Duration::from_millis(50));
            }
            if !exited {
                let _ = child.kill();
                let _ = child.wait();
            }
        }
        cleanup_system_network();
    }
}

pub fn cleanup_system_network() {
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        let clean = |cmd: &str, args: &[&str]| {
            let mut c = Command::new(cmd);
            c.args(args);
            c.creation_flags(CREATE_NO_WINDOW);
            let _ = c.status();
        };

        // Remove any stale split-default and DNS routes (<10ms)
        clean("route", &["delete", "0.0.0.0", "mask", "128.0.0.0"]);
        clean("route", &["delete", "128.0.0.0", "mask", "128.0.0.0"]);
        clean("route", &["delete", "1.1.1.1"]);
        clean("route", &["delete", "1.0.0.1"]);
        clean("route", &["delete", "8.8.8.8"]);
        clean("route", &["delete", "8.8.4.4"]);

        // Remove global policy registry keys to heal Windows DNS and local network (<10ms)
        clean(
            "reg",
            &[
                "delete",
                r"HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient",
                "/v",
                "DisableSmartNameResolution",
                "/f",
            ],
        );
        clean(
            "reg",
            &[
                "delete",
                r"HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient",
                "/v",
                "EnableMulticast",
                "/f",
            ],
        );

        // Fast direct netsh removal of firewall rules (<20ms vs 1500ms PowerShell)
        clean("netsh", &["advfirewall", "firewall", "delete", "rule", "name=ObsidianVPN-Block-Physical-DNS-UDP"]);
        clean("netsh", &["advfirewall", "firewall", "delete", "rule", "name=ObsidianVPN-Block-Physical-DNS-TCP"]);
        clean("netsh", &["advfirewall", "firewall", "delete", "rule", "name=ObsidianVPN-Block-IPv6-DNS-UDP"]);
        clean("netsh", &["advfirewall", "firewall", "delete", "rule", "name=ObsidianVPN-Block-IPv6-DNS-TCP"]);
        clean("netsh", &["advfirewall", "firewall", "delete", "rule", "name=ObsidianVPN-Block-Router-DNS"]);
        clean("netsh", &["advfirewall", "firewall", "delete", "rule", "name=ObsidianVPN-Block-Router-DNS-TCP"]);

        clean("ipconfig", &["/flushdns"]);

        // Non-blocking asynchronous cleanup of NRPT rule and DNS cache so UI never freezes
        std::thread::spawn(|| {
            let mut c = Command::new("powershell");
            c.args(&[
                "-NoProfile",
                "-NonInteractive",
                "-WindowStyle",
                "Hidden",
                "-Command",
                "Get-DnsClientNrptRule -ErrorAction SilentlyContinue | Where-Object DisplayName -eq 'ObsidianVPN-NRPT' | Remove-DnsClientNrptRule -Force -ErrorAction SilentlyContinue; Clear-DnsClientCache -ErrorAction SilentlyContinue",
            ]);
            c.creation_flags(CREATE_NO_WINDOW);
            let _ = c.status();
        });
    }
}

fn is_admin() -> bool {
    #[cfg(windows)]
    {
        let mut cmd = Command::new("net");
        cmd.arg("session")
            .stdout(Stdio::null())
            .stderr(Stdio::null());
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(CREATE_NO_WINDOW);
        return cmd.status().map(|s| s.success()).unwrap_or(false);
    }
    #[cfg(not(windows))]
    {
        true
    }
}

fn relaunch_as_admin(extra: &[&str]) -> Result<(), String> {
    #[cfg(windows)]
    {
        let exe = std::env::current_exe().map_err(|e| e.to_string())?;
        let exe_str = exe.to_string_lossy().replace('\'', "''");
        let arg_list = extra.join(" ");
        let ps = if extra.is_empty() {
            format!("Start-Process -FilePath '{exe_str}' -Verb RunAs")
        } else {
            format!(
                "Start-Process -FilePath '{exe_str}' -Verb RunAs -ArgumentList '{arg_list}'"
            )
        };
        let mut cmd = Command::new("powershell");
        cmd.args(["-NoProfile", "-WindowStyle", "Hidden", "-Command", &ps]);
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(CREATE_NO_WINDOW);
        let status = cmd
            .status()
            .map_err(|e| format!("Could not request Administrator: {e}"))?;
        if !status.success() {
            return Err(
                "The tunnel needs Administrator. Allow the UAC prompt, then press Connect."
                    .into(),
            );
        }
        std::process::exit(0);
    }
    #[cfg(not(windows))]
    {
        let _ = extra;
        Ok(())
    }
}

fn tee_child_output(child: &mut Child) -> Arc<Mutex<String>> {
    let buf = Arc::new(Mutex::new(String::new()));
    let log_path = storage::app_dir().join("client.log");
    if let Some(out) = child.stdout.take() {
        spawn_reader(out, buf.clone(), log_path.clone());
    }
    if let Some(err) = child.stderr.take() {
        spawn_reader(err, buf.clone(), log_path);
    }
    buf
}

fn spawn_reader<R: std::io::Read + Send + 'static>(
    reader: R,
    buf: Arc<Mutex<String>>,
    log_path: PathBuf,
) {
    std::thread::spawn(move || {
        let reader = BufReader::new(reader);
        for line in reader.lines() {
            let Ok(line) = line else { break };
            if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(&log_path)
            {
                let _ = writeln!(file, "{line}");
            }
            if let Ok(mut dump) = buf.lock() {
                if !dump.is_empty() {
                    dump.push('\n');
                }
                dump.push_str(&line);
                const KEEP: usize = 65536;
                if dump.len() > KEEP {
                    let drain = dump.len() - KEEP;
                    dump.drain(..drain);
                }
            }
        }
    });
}

fn interpret_client_log(dump: &str, current_status: &str) -> (String, String, u32, String) {
    let ready = dump.rfind(": ready");
    let ended = dump.rfind("session ended:");

    // Если туннель уже перешел в состояние connected:
    // он остается connected до тех пор, пока процесс работает и не появилось нового "session ended:" после последнего ": ready"
    if current_status == "connected" {
        let broken = match (ended, ready) {
            (Some(e), Some(r)) => e > r,
            (Some(_), None) => true,
            _ => false,
        };
        if !broken {
            return (
                "connected".into(),
                "Туннель активен. Сетевой трафик защищен.".into(),
                100,
                "Подключено".into(),
            );
        }
    }

    let live = match (ready, ended) {
        (Some(r), Some(e)) => r > e,
        (Some(_), None) => true,
        _ => false,
    };
    if live {
        return (
            "connected".into(),
            "Туннель активен. Сетевой трафик защищен.".into(),
            100,
            "Подключено".into(),
        );
    }
    let lower = dump.to_ascii_lowercase();
    if lower.contains("clean all stale")
        || lower.contains("bypass route")
        || lower.contains("dual-stack ipv6")
        || lower.contains("routes restored")
    {
        (
            "connecting".into(),
            "Маршрутизация сетевого трафика через туннель".into(),
            90,
            "Маршрутизация (4/4)".into(),
        )
    } else if lower.contains("tun address set")
        || lower.contains("set dns")
        || lower.contains("tun mtu")
    {
        (
            "connecting".into(),
            "Настройка IP-адресации и защищенного DNS".into(),
            70,
            "Конфигурация сети (3/4)".into(),
        )
    } else if lower.contains("wintun session started")
        || lower.contains("creating adapter")
        || lower.contains("session started")
    {
        (
            "connecting".into(),
            "Запуск виртуального сетевого адаптера Wintun".into(),
            45,
            "Wintun адаптер (2/4)".into(),
        )
    } else if lower.contains("connecting to") || lower.contains("handshake") {
        (
            "connecting".into(),
            "Согласование криптографических ключей REALITY".into(),
            20,
            "REALITY handshake (1/4)".into(),
        )
    } else {
        (
            "connecting".into(),
            "Инициализация сетевого соединения...".into(),
            10,
            "Инициализация".into(),
        )
    }
}

fn humanize_client_log(dump: &str) -> String {
    let last = dump
        .lines()
        .rev()
        .find(|l| !l.trim().is_empty())
        .unwrap_or("")
        .trim();
    let lower = dump.to_ascii_lowercase();
    if lower.contains("access is denied") || lower.contains("administrator") {
        return "Для работы Wintun требуются права Администратора.".into();
    }
    if last.contains("failed to open TUN") {
        return "Не удалось создать виртуальный адаптер TUN. Запустите приложение от имени Администратора.".into();
    }
    if lower.contains("connectex") || lower.contains("did not properly respond") {
        return "Сервер не отвечает на TCP-порт 443. Проверьте статус VPS.".into();
    }
    if lower.contains("i/o timeout") || lower.contains("did not return a recognizable response") {
        return "Таймаут подключения: сервер не завершил рукопожатие REALITY.".into();
    }
    if last.is_empty() {
        "Процесс клиента неожиданно завершился".into()
    } else {
        last.to_string()
    }
}

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

pub fn extract_runtime(app: &AppHandle) -> Result<PathBuf, String> {
    let dest = storage::runtime_dir();
    let names = [
        "obsidian-client.exe",
        "wintun.dll",
        "obsidian-server-linux",
        "keyserver.py",
    ];
    for name in names {
        let target = dest.join(name);
        let mut src = app
            .path()
            .resolve(
                format!("resources/{name}"),
                tauri::path::BaseDirectory::Resource,
            )
            .ok();
        if src.as_ref().map(|p| !p.exists()).unwrap_or(true) {
            let alt = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                .join("resources")
                .join(name);
            if alt.exists() {
                src = Some(alt);
            }
        }
        if let Some(path) = src {
            if path.exists() {
                copy_if_changed(&path, &target)?;
            }
        }
    }
    let exe = dest.join("obsidian-client.exe");
    if !exe.exists() {
        return Err("obsidian-client.exe is missing from the app bundle".into());
    }
    Ok(exe)
}

fn copy_if_changed(src: &PathBuf, dest: &PathBuf) -> Result<(), String> {
    let data = fs::read(src).map_err(|e| format!("read {}: {e}", src.display()))?;
    if dest.exists() {
        if let Ok(existing) = fs::read(dest) {
            if existing == data {
                return Ok(());
            }
        }
    }
    fs::write(dest, data).map_err(|e| {
        if dest.exists() {
            String::new()
        } else {
            format!("write {}: {e}", dest.display())
        }
    })?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_interpret_initial_ready() {
        let dump = "2026/09/04 19:00:00 session 1234abcd: ready\n";
        let (status, _, progress, stage) = interpret_client_log(dump, "connecting");
        assert_eq!(status, "connected");
        assert_eq!(progress, 100);
        assert_eq!(stage, "Подключено");
    }

    #[test]
    fn test_interpret_buffer_drained_keeps_connected() {
        // Simulates the log buffer 1 minute later, when : ready has been drained away
        // by subsequent traffic lines
        let dump = "2026/09/04 19:01:00 DEBUG: packet traffic flowing...\n";
        let (status, _, progress, stage) = interpret_client_log(dump, "connected");
        assert_eq!(status, "connected", "Must not revert to connecting when buffer is drained");
        assert_eq!(progress, 100);
        assert_eq!(stage, "Подключено");
    }

    #[test]
    fn test_interpret_buffer_drained_when_connecting() {
        let dump = "random unknown log line";
        let (status, _, progress, _) = interpret_client_log(dump, "connecting");
        assert_eq!(status, "connecting");
        assert_eq!(progress, 10);
    }

    #[test]
    fn test_interpret_session_ended_reverts_connected() {
        let dump = "2026/09/04 19:00:00 session 1234abcd: ready\n2026/09/04 19:02:00 session ended: connection reset — reconnecting in 3s\n";
        let (status, _, _progress, _) = interpret_client_log(dump, "connected");
        assert_ne!(status, "connected", "Must recognize session ended");
    }
}


