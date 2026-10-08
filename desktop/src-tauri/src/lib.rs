mod installer;
mod keys;
mod storage;
mod vpn;

use installer::DeployReq;
use keys::EncodeArgs;
use qrcode::render::svg;
use qrcode::QrCode;
use serde::Serialize;
use serde_json::{json, Map, Value};
use std::net::{TcpStream, ToSocketAddrs};
use std::time::{Duration, Instant};
use storage::{IssuedKey, ServerProfile, Settings};
use tauri::{
    image::Image,
    menu::{MenuBuilder, MenuItemBuilder},
    tray::TrayIconBuilder,
    window::{ProgressBarState, ProgressBarStatus},
    AppHandle, Emitter, Manager,
};
use tauri_plugin_dialog::{DialogExt, FilePath};
use uuid::Uuid;
use vpn::Vpn;

#[derive(Serialize)]
struct AppStateDto {
    profiles: Vec<ServerProfile>,
    issued: Vec<IssuedKey>,
    settings: Settings,
    device_id: String,
    version: String,
    vpn: vpn::VpnSnapshot,
}

fn state_dto(app: &AppHandle) -> AppStateDto {
    AppStateDto {
        profiles: storage::load_profiles(),
        issued: storage::load_issued(),
        settings: storage::load_settings(),
        device_id: storage::short_device_id(),
        version: "0.1.0".into(),
        vpn: app.state::<Vpn>().snapshot(),
    }
}

#[tauri::command]
fn load_state(app: AppHandle) -> AppStateDto {
    let _ = vpn::extract_runtime(&app);
    state_dto(&app)
}

#[tauri::command]
fn save_settings(app: AppHandle, settings: Settings) -> Result<AppStateDto, String> {
    let prev = storage::load_settings();
    storage::save_settings(&settings)?;
    if prev.autostart != settings.autostart {
        set_windows_autostart(settings.autostart);
    }
    Ok(state_dto(&app))
}

#[tauri::command]
fn select_profile(app: AppHandle, id: String) -> Result<AppStateDto, String> {
    let mut settings = storage::load_settings();
    settings.last_profile_id = id;
    storage::save_settings(&settings)?;
    Ok(state_dto(&app))
}

#[tauri::command]
fn decode_preview(key: String) -> Result<String, String> {
    keys::key_ok(&key)
}

#[tauri::command]
fn add_key(app: AppHandle, key: String) -> Result<AppStateDto, String> {
    let cfg = keys::decode_key(&key)?;
    let host = cfg
        .get("server_host")
        .and_then(|v| v.as_str())
        .unwrap_or("Server")
        .to_string();
    let label = cfg
        .get("_label")
        .and_then(|v| v.as_str())
        .filter(|s| !s.trim().is_empty())
        .map(|s| s.trim().to_string());
    let server_name = label.unwrap_or_else(|| host.clone());
    let (flag, code) = storage::server_meta(&host);
    let mut profile = ServerProfile {
        id: Uuid::new_v4().to_string(),
        name: server_name,
        config: cfg.clone(),
        keyserver_url: str_field(&cfg, "_keyserver"),
        token: str_field(&cfg, "_token"),
        expires: str_field(&cfg, "_expires"),
        max_devices: cfg
            .get("_max_devices")
            .and_then(|v| v.as_u64())
            .unwrap_or(0) as u32,
        raw_key: key.trim().to_string(),
        source: "key".into(),
        ssh_host: String::new(),
        ssh_port: 22,
        ssh_user: "root".into(),
        ssh_password_secret: String::new(),
        ssh_auth: "password".into(),
        ssh_key_path: String::new(),
        keyserver_admin_token: String::new(),
        code,
        flag,
        server_version: "0.1.0".into(),
        needs_update: false,
    };
    let _ = storage::write_client_config(&mut profile);
    let mut profiles = storage::load_profiles();
    profiles.push(profile.clone());
    storage::save_profiles(&profiles)?;
    let mut settings = storage::load_settings();
    settings.last_profile_id = profile.id;
    storage::save_settings(&settings)?;
    Ok(state_dto(&app))
}

#[tauri::command]
fn remove_profile(app: AppHandle, id: String) -> Result<AppStateDto, String> {
    let profiles: Vec<_> = storage::load_profiles()
        .into_iter()
        .filter(|p| p.id != id)
        .collect();
    storage::save_profiles(&profiles)?;
    let issued: Vec<_> = storage::load_issued()
        .into_iter()
        .filter(|k| k.server_id != id)
        .collect();
    storage::save_issued(&issued)?;
    Ok(state_dto(&app))
}

#[tauri::command]
fn set_split_tunnel(
    app: AppHandle,
    id: String,
    mode: String,
    sites: Vec<String>,
) -> Result<AppStateDto, String> {
    let mut profiles = storage::load_profiles();
    if let Some(p) = profiles.iter_mut().find(|p| p.id == id) {
        p.config
            .insert("split_tunnel_mode".into(), json!(mode));
        p.config.insert(
            "split_sites".into(),
            json!(sites.into_iter().filter(|s| !s.trim().is_empty()).collect::<Vec<_>>()),
        );
        p.config.insert("route_ips".into(), json!([]));
    }
    storage::save_profiles(&profiles)?;
    Ok(state_dto(&app))
}

#[tauri::command]
fn connect(app: AppHandle) -> Result<AppStateDto, String> {
    let settings = storage::load_settings();
    let profiles = storage::load_profiles();
    let profile = profiles
        .iter()
        .find(|p| p.id == settings.last_profile_id)
        .cloned()
        .or_else(|| profiles.first().cloned())
        .ok_or_else(|| "Add a server first".to_string())?;
    app.state::<Vpn>().connect(&app, profile)?;
    Ok(state_dto(&app))
}

#[tauri::command]
fn disconnect(app: AppHandle) -> AppStateDto {
    app.state::<Vpn>().disconnect(&app);
    state_dto(&app)
}

fn server_profile_to_deploy_req(p: &ServerProfile) -> Result<DeployReq, String> {
    let host = if !p.ssh_host.is_empty() {
        p.ssh_host.clone()
    } else {
        str_field(&p.config, "server_host")
    };
    if host.is_empty() {
        return Err("У сервера отсутствует SSH-хост".into());
    }
    let auth = if p.ssh_auth.is_empty() {
        if !p.ssh_key_path.is_empty() {
            "key".to_string()
        } else {
            "password".to_string()
        }
    } else {
        p.ssh_auth.clone()
    };
    if auth == "password" && p.ssh_password_secret.is_empty() {
        return Err("SSH-пароль не сохранен в профиле сервера".into());
    }
    if auth == "key" && p.ssh_key_path.is_empty() {
        return Err("Путь к SSH-ключу не сохранен в профиле сервера".into());
    }
    Ok(DeployReq {
        host,
        user: if p.ssh_user.is_empty() {
            "root".into()
        } else {
            p.ssh_user.clone()
        },
        port: if p.ssh_port == 0 { 22 } else { p.ssh_port },
        auth,
        password: if !p.ssh_password_secret.is_empty() {
            Some(p.ssh_password_secret.clone())
        } else {
            None
        },
        key_path: if !p.ssh_key_path.is_empty() {
            Some(p.ssh_key_path.clone())
        } else {
            None
        },
        mask: {
            let s = str_field(&p.config, "reality_sni");
            if s.is_empty() {
                Some("www.microsoft.com".into())
            } else {
                Some(s)
            }
        },
    })
}

#[tauri::command]
async fn start_update(app: AppHandle, req: DeployReq) -> Result<AppStateDto, String> {
    let host = req.host.trim().to_string();
    let saved_password = req.password.clone();
    let saved_key_path = req.key_path.clone();
    let saved_auth = req.auth.clone();

    let result = installer::update_firmware(app.clone(), req).await?;
    let mut profiles = storage::load_profiles();
    let mut updated_server_ids = Vec::new();

    for p in profiles.iter_mut() {
        let same = p.ssh_host == host
            || p.config
                .get("server_host")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                == host;
        if p.source == "ssh" && same {
            p.config
                .insert("server_port".into(), json!(result.server_port.clone()));
            p.config
                .insert("udp_port".into(), json!(result.udp_port.clone()));
            // REALITY keys change only when the server actually runs REALITY after the update.
            p.config
                .insert("reality_enabled".into(), json!(result.reality_enabled));
            if result.reality_enabled {
                p.config.insert(
                    "reality_auth_key".into(),
                    json!(result.reality_auth_key.clone()),
                );
                p.config
                    .insert("reality_sni".into(), json!(result.reality_sni.clone()));
                p.config
                    .insert("sni".into(), json!(result.reality_sni.clone()));
                p.config.insert("no_tls".into(), json!(false));
                p.config.insert("fingerprint".into(), json!("chrome"));
            }
            p.config.insert("enable_ipv6".into(), json!(result.enable_ipv6));

            if let Some(ref pwd) = saved_password {
                if !pwd.is_empty() {
                    p.ssh_password_secret = pwd.clone();
                }
            }
            if let Some(ref kp) = saved_key_path {
                if !kp.is_empty() {
                    p.ssh_key_path = kp.clone();
                }
            }
            if !saved_auth.is_empty() {
                p.ssh_auth = saved_auth.clone();
            }
            p.server_version = "0.1.0".into();
            p.needs_update = false;

            // Re-encode key with updated SNI and auth key
            if let Ok(key) = keys::encode_key(EncodeArgs {
                server_host: str_field(&p.config, "server_host"),
                server_port: result.server_port.clone(),
                server_public_key: str_field(&p.config, "server_public_key"),
                udp_port: result.udp_port.clone(),
                keyserver_url: p.keyserver_url.clone(),
                token: p.token.clone(),
                expires: p.expires.clone(),
                max_devices: p.max_devices,
                enable_udp_data: true,
                mtu: keys::SAFE_MTU,
                reality_enabled: result.reality_enabled,
                reality_auth_key: result.reality_auth_key.clone(),
                reality_sni: result.reality_sni.clone(),
                enable_ipv6: result.enable_ipv6,
            }) {
                p.raw_key = key.clone();
                updated_server_ids.push((p.id.clone(), key));
            }
            let _ = storage::write_client_config(p);
        }
    }
    storage::save_profiles(&profiles)?;

    let mut issued = storage::load_issued();
    for (sid, key) in updated_server_ids {
        if let Some(owner) = issued.iter_mut().find(|k| {
            k.server_id == sid
                && (k.name.eq_ignore_ascii_case("owner") || k.name.eq_ignore_ascii_case("владелец"))
        }) {
            owner.key = key;
        }
    }
    storage::save_issued(&issued)?;
    Ok(state_dto(&app))
}

#[tauri::command]
async fn start_deploy(app: AppHandle, req: DeployReq) -> Result<AppStateDto, String> {
    let host = req.host.clone();
    let ssh_user = {
        let u = req.user.trim();
        if u.is_empty() {
            "root".into()
        } else {
            u.to_string()
        }
    };
    let ssh_port = if req.port == 0 { 22 } else { req.port };
    let ssh_auth = req.auth.clone();
    let ssh_password = req.password.clone().unwrap_or_default();
    let ssh_key_path = req.key_path.clone().unwrap_or_default();

    let result = installer::deploy(app.clone(), req).await?;
    let (flag, code) = storage::server_meta(&host);
    let key = keys::encode_key(EncodeArgs {
        server_host: result.server_host.clone(),
        server_port: result.server_port.clone(),
        server_public_key: result.server_public_key.clone(),
        udp_port: result.udp_port.clone(),
        keyserver_url: result.keyserver_url.clone(),
        token: String::new(),
        expires: String::new(),
        max_devices: 0,
        enable_udp_data: true,
        mtu: keys::SAFE_MTU,
        reality_enabled: true,
        reality_auth_key: result.reality_auth_key.clone(),
        reality_sni: result.reality_sni.clone(),
        enable_ipv6: result.enable_ipv6,
    })?;
    let mut cfg = keys::decode_key(&key)?;
    cfg.insert("enable_ipv6".into(), json!(result.enable_ipv6));

    let mut profiles = storage::load_profiles();
    let existing_idx = profiles.iter().position(|p| {
        p.source == "ssh" && (p.ssh_host == result.server_host || p.name == host)
    });

    let profile_id = if let Some(idx) = existing_idx {
        profiles[idx].id.clone()
    } else {
        Uuid::new_v4().to_string()
    };

    let mut profile = ServerProfile {
        id: profile_id.clone(),
        name: host.clone(),
        config: cfg,
        keyserver_url: result.keyserver_url.clone(),
        token: String::new(),
        expires: String::new(),
        max_devices: 0,
        raw_key: key.clone(),
        source: "ssh".into(),
        ssh_host: result.server_host.clone(),
        ssh_port,
        ssh_user,
        ssh_password_secret: ssh_password,
        ssh_auth,
        ssh_key_path,
        keyserver_admin_token: result.admin_token.clone(),
        code: code.clone(),
        flag,
        server_version: "0.1.0".into(),
        needs_update: false,
    };
    let _ = storage::write_client_config(&mut profile);

    if let Some(idx) = existing_idx {
        profiles[idx] = profile.clone();
    } else {
        profiles.push(profile.clone());
    }
    storage::save_profiles(&profiles)?;

    let mut settings = storage::load_settings();
    settings.last_profile_id = profile.id.clone();
    storage::save_settings(&settings)?;

    let mut issued = storage::load_issued();
    // Update existing Owner key if found for this server, otherwise insert exactly one
    if let Some(owner) = issued.iter_mut().find(|k| {
        (k.server_id == profile.id || k.server_code == code)
            && (k.name.eq_ignore_ascii_case("owner") || k.name.eq_ignore_ascii_case("владелец"))
    }) {
        owner.server_id = profile.id.clone();
        owner.server_code = code.clone();
        owner.key = key;
    } else {
        issued.insert(
            0,
            IssuedKey {
                id: Uuid::new_v4().to_string(),
                name: "Owner".into(),
                server_id: profile.id,
                server_code: code,
                devices: 3,
                days: 0,
                key,
                created: iso_date(0),
            },
        );
    }
    storage::save_issued(&issued)?;
    let _ = app.emit("deploy-result", &result);
    Ok(state_dto(&app))
}

#[tauri::command]
async fn change_server_sni(
    app: AppHandle,
    server_id: String,
    new_sni: String,
) -> Result<AppStateDto, String> {
    let profiles = storage::load_profiles();
    let profile = profiles
        .iter()
        .find(|p| p.id == server_id)
        .ok_or_else(|| "Профиль сервера не найден".to_string())?;

    if profile.source != "ssh" {
        return Err("Изменение SNI доступно только для собственных VPS серверов".into());
    }

    let req = server_profile_to_deploy_req(profile)?;
    let applied_sni = installer::change_sni(app.clone(), req, new_sni).await?;

    let mut profiles = storage::load_profiles();
    let mut updated_key = String::new();
    for p in profiles.iter_mut() {
        if p.id == server_id {
            p.config.insert("reality_sni".into(), json!(applied_sni.clone()));
            p.config.insert("sni".into(), json!(applied_sni.clone()));
            if let Ok(key) = keys::encode_key(EncodeArgs {
                server_host: str_field(&p.config, "server_host"),
                server_port: str_field(&p.config, "server_port"),
                server_public_key: str_field(&p.config, "server_public_key"),
                udp_port: str_field(&p.config, "udp_port"),
                keyserver_url: p.keyserver_url.clone(),
                token: p.token.clone(),
                expires: p.expires.clone(),
                max_devices: p.max_devices,
                enable_udp_data: true,
                mtu: keys::SAFE_MTU,
                reality_enabled: true,
                reality_auth_key: str_field(&p.config, "reality_auth_key"),
                reality_sni: applied_sni.clone(),
                enable_ipv6: p.config.get("enable_ipv6").and_then(|v| v.as_bool()).unwrap_or(false),
            }) {
                p.raw_key = key.clone();
                updated_key = key;
            }
            let _ = storage::write_client_config(p);
        }
    }
    storage::save_profiles(&profiles)?;

    if !updated_key.is_empty() {
        let mut issued = storage::load_issued();
        if let Some(owner) = issued.iter_mut().find(|k| {
            k.server_id == server_id
                && (k.name.eq_ignore_ascii_case("owner") || k.name.eq_ignore_ascii_case("владелец"))
        }) {
            owner.key = updated_key;
        }
        storage::save_issued(&issued)?;
    }

    Ok(state_dto(&app))
}

#[tauri::command]
fn toggle_server_ipv6(app: AppHandle, server_id: String) -> Result<AppStateDto, String> {
    let mut profiles = storage::load_profiles();
    let mut updated_key = String::new();
    for p in profiles.iter_mut() {
        if p.id == server_id {
            let current = p.config.get("enable_ipv6").and_then(|v| v.as_bool()).unwrap_or(false);
            let next = !current;
            p.config.insert("enable_ipv6".into(), json!(next));
            if let Ok(key) = keys::encode_key(EncodeArgs {
                server_host: str_field(&p.config, "server_host"),
                server_port: str_field(&p.config, "server_port"),
                server_public_key: str_field(&p.config, "server_public_key"),
                udp_port: str_field(&p.config, "udp_port"),
                keyserver_url: p.keyserver_url.clone(),
                token: p.token.clone(),
                expires: p.expires.clone(),
                max_devices: p.max_devices,
                enable_udp_data: true,
                mtu: keys::SAFE_MTU,
                reality_enabled: true,
                reality_auth_key: str_field(&p.config, "reality_auth_key"),
                reality_sni: str_field(&p.config, "reality_sni"),
                enable_ipv6: next,
            }) {
                p.raw_key = key.clone();
                updated_key = key;
            }
            let _ = storage::write_client_config(p);
        }
    }
    storage::save_profiles(&profiles)?;
    if !updated_key.is_empty() {
        let mut issued = storage::load_issued();
        if let Some(owner) = issued.iter_mut().find(|k| {
            k.server_id == server_id
                && (k.name.eq_ignore_ascii_case("owner") || k.name.eq_ignore_ascii_case("владелец"))
        }) {
            owner.key = updated_key;
        }
        storage::save_issued(&issued)?;
    }
    Ok(state_dto(&app))
}

#[tauri::command]
async fn reset_server(app: AppHandle, server_id: String) -> Result<AppStateDto, String> {
    let profiles = storage::load_profiles();
    let profile = profiles
        .iter()
        .find(|p| p.id == server_id)
        .ok_or_else(|| "Профиль сервера не найден".to_string())?;

    if profile.source != "ssh" {
        return Err("Обнуление доступно только для собственных VPS серверов".into());
    }

    // If currently connected to this server, disconnect first
    let snap = app.state::<Vpn>().snapshot();
    if snap.status == "connected" || snap.status == "connecting" {
        let settings = storage::load_settings();
        if settings.last_profile_id == server_id {
            app.state::<Vpn>().disconnect(&app);
        }
    }

    let req = server_profile_to_deploy_req(profile)?;
    let result = installer::reset_server(app.clone(), req).await?;

    let mut profiles = storage::load_profiles();
    let mut new_owner_key = String::new();
    let mut server_code = profile.code.clone();

    for p in profiles.iter_mut() {
        if p.id == server_id {
            p.config
                .insert("server_public_key".into(), json!(result.server_public_key.clone()));
            p.config
                .insert("reality_auth_key".into(), json!(result.reality_auth_key.clone()));
            p.config
                .insert("reality_sni".into(), json!(result.reality_sni.clone()));
            p.config
                .insert("sni".into(), json!(result.reality_sni.clone()));
            p.server_version = "0.1.0".into();
            p.needs_update = false;

            // Generate fresh client identity
            p.config.remove("client_private_key");
            p.config.remove("client_public_key");
            storage::ensure_client_identity(&mut p.config);

            if let Ok(key) = keys::encode_key(EncodeArgs {
                server_host: str_field(&p.config, "server_host"),
                server_port: str_field(&p.config, "server_port"),
                server_public_key: result.server_public_key.clone(),
                udp_port: str_field(&p.config, "udp_port"),
                keyserver_url: p.keyserver_url.clone(),
                token: String::new(),
                expires: String::new(),
                max_devices: 0,
                enable_udp_data: true,
                mtu: keys::SAFE_MTU,
                reality_enabled: true,
                reality_auth_key: result.reality_auth_key.clone(),
                reality_sni: result.reality_sni.clone(),
                enable_ipv6: p.config.get("enable_ipv6").and_then(|v| v.as_bool()).unwrap_or(false),
            }) {
                p.raw_key = key.clone();
                new_owner_key = key;
            }
            server_code = p.code.clone();
            let _ = storage::write_client_config(p);
        }
    }
    storage::save_profiles(&profiles)?;

    // Remove old issued client keys for this server and set exactly one fresh Owner key
    let mut issued: Vec<_> = storage::load_issued()
        .into_iter()
        .filter(|k| k.server_id != server_id)
        .collect();

    if !new_owner_key.is_empty() {
        issued.insert(
            0,
            IssuedKey {
                id: Uuid::new_v4().to_string(),
                name: "Owner".into(),
                server_id: server_id.clone(),
                server_code,
                devices: 3,
                days: 0,
                key: new_owner_key,
                created: iso_date(0),
            },
        );
    }
    storage::save_issued(&issued)?;

    Ok(state_dto(&app))
}

#[tauri::command]
async fn update_server_firmware(app: AppHandle, server_id: String) -> Result<AppStateDto, String> {
    let profiles = storage::load_profiles();
    let profile = profiles
        .iter()
        .find(|p| p.id == server_id)
        .ok_or_else(|| "Профиль сервера не найден".to_string())?;

    if profile.source != "ssh" {
        return Err("Обновление доступно только для собственных VPS серверов".into());
    }

    let req = server_profile_to_deploy_req(profile)?;
    start_update(app, req).await
}

#[tauri::command]
async fn check_server_version(app: AppHandle, server_id: String) -> Result<AppStateDto, String> {
    let profiles = storage::load_profiles();
    let profile = profiles
        .iter()
        .find(|p| p.id == server_id)
        .ok_or_else(|| "Профиль сервера не найден".to_string())?;

    if profile.source != "ssh" {
        return Err("Проверка версий доступна только для собственных VPS серверов".into());
    }

    let req = server_profile_to_deploy_req(profile)?;
    let check = installer::check_remote_version(app.clone(), &req).await?;

    let mut profiles = storage::load_profiles();
    for p in profiles.iter_mut() {
        if p.id == server_id {
            p.server_version = check.version.clone();
            p.needs_update = check.needs_update;
        }
    }
    storage::save_profiles(&profiles)?;
    Ok(state_dto(&app))
}

#[tauri::command]
fn set_taskbar_progress(
    app: AppHandle,
    progress: Option<u64>,
    state_name: Option<String>,
) -> Result<(), String> {
    if let Some(window) = app.get_webview_window("main") {
        let status = match state_name.as_deref() {
            Some("indeterminate") => Some(ProgressBarStatus::Indeterminate),
            Some("error") => Some(ProgressBarStatus::Error),
            Some("paused") => Some(ProgressBarStatus::Paused),
            Some("none") => Some(ProgressBarStatus::None),
            _ => Some(ProgressBarStatus::Normal),
        };
        let _ = window.set_progress_bar(ProgressBarState {
            progress,
            status,
        });
    }
    Ok(())
}

#[tauri::command]
fn save_server_credentials(
    app: AppHandle,
    server_id: String,
    host: String,
    port: u16,
    user: String,
    auth: String,
    password: Option<String>,
    key_path: Option<String>,
    raw_key: Option<String>,
) -> Result<AppStateDto, String> {
    let mut profiles = storage::load_profiles();
    let p = profiles
        .iter_mut()
        .find(|p| p.id == server_id)
        .ok_or_else(|| "Профиль сервера не найден".to_string())?;

    let host_clean = host.trim().to_string();
    if !host_clean.is_empty() {
        p.ssh_host = host_clean.clone();
        p.name = host_clean.clone();
        p.config.insert("server_host".into(), json!(host_clean));
    }
    p.ssh_port = if port == 0 { 22 } else { port };
    p.ssh_user = if user.trim().is_empty() {
        "root".into()
    } else {
        user.trim().to_string()
    };
    p.ssh_auth = if auth.trim() == "key" {
        "key".into()
    } else {
        "password".into()
    };

    if let Some(pwd) = password {
        let pwd_trimmed = pwd.trim();
        if !pwd_trimmed.is_empty() {
            p.ssh_password_secret = pwd;
        }
    }

    if let Some(raw) = raw_key {
        let raw_clean = raw.trim();
        if !raw_clean.is_empty() {
            let app_data = app.path().app_data_dir().map_err(|e| e.to_string())?;
            let keys_dir = app_data.join("ssh_keys");
            let _ = std::fs::create_dir_all(&keys_dir);
            let key_file = keys_dir.join(format!("{server_id}.id_rsa"));
            std::fs::write(&key_file, raw_clean)
                .map_err(|e| format!("Не удалось сохранить приватный ключ: {e}"))?;
            p.ssh_key_path = key_file.to_string_lossy().to_string();
        }
    }

    if let Some(kp) = key_path {
        let kp_clean = kp.trim().to_string();
        if !kp_clean.is_empty() {
            p.ssh_key_path = kp_clean;
        }
    }

    let _ = storage::write_client_config(p);
    storage::save_profiles(&profiles)?;
    Ok(state_dto(&app))
}

#[tauri::command]
fn issue_key(app: AppHandle, name: String, days: u32, devices: u32) -> Result<IssuedKey, String> {
    let profiles = storage::load_profiles();
    let server = profiles
        .iter()
        .find(|p| p.source == "ssh")
        .ok_or_else(|| "Deploy your own server before issuing keys".to_string())?;
    let cfg = &server.config;
    let expires = if days == 0 { String::new() } else { iso_date(days) };
    let key = keys::encode_key(EncodeArgs {
        server_host: str_field(cfg, "server_host"),
        server_port: str_field(cfg, "server_port"),
        server_public_key: str_field(cfg, "server_public_key"),
        udp_port: str_field(cfg, "udp_port"),
        keyserver_url: server.keyserver_url.clone(),
        token: String::new(),
        expires: expires.clone(),
        max_devices: devices,
        enable_udp_data: cfg
            .get("enable_udp_data")
            .and_then(|v| v.as_bool())
            .unwrap_or(true),
        mtu: keys::SAFE_MTU,
        reality_enabled: cfg.get("reality_enabled").and_then(|v| v.as_bool()).unwrap_or(false)
            || cfg
                .get("reality_auth_key")
                .and_then(|v| v.as_str())
                .map(|s| !s.is_empty())
                .unwrap_or(false),
        reality_auth_key: str_field(cfg, "reality_auth_key"),
        reality_sni: {
            let s = str_field(cfg, "reality_sni");
            if s.is_empty() {
                str_field(cfg, "sni")
            } else {
                s
            }
        },
        enable_ipv6: cfg.get("enable_ipv6").and_then(|v| v.as_bool()).unwrap_or(false),
    })?;
    let issued = IssuedKey {
        id: Uuid::new_v4().to_string(),
        name: if name.trim().is_empty() {
            "Guest".into()
        } else {
            name.trim().into()
        },
        server_id: server.id.clone(),
        server_code: server.code.clone(),
        devices,
        days,
        key,
        created: iso_date(0),
    };
    let mut all = storage::load_issued();
    all.insert(0, issued.clone());
    storage::save_issued(&all)?;
    let _ = app;
    Ok(issued)
}

#[tauri::command]
fn qr_svg(text: String) -> Result<String, String> {
    let code = QrCode::new(text.as_bytes()).map_err(|e| e.to_string())?;
    Ok(code
        .render::<svg::Color>()
        .min_dimensions(220, 220)
        .dark_color(svg::Color("#111111"))
        .light_color(svg::Color("#ffffff"))
        .build())
}

#[tauri::command]
fn export_server_uri(server_id: String) -> Result<String, String> {
    let profiles = storage::load_profiles();
    let server = profiles
        .iter()
        .find(|p| p.id == server_id)
        .ok_or_else(|| "Профиль сервера не найден".to_string())?;
    let cfg = &server.config;
    let expires = str_field(cfg, "_expires");
    let token = str_field(cfg, "_token");
    let max_devices = cfg
        .get("_max_devices")
        .and_then(|v| v.as_u64())
        .unwrap_or(0) as u32;

    keys::encode_uri(
        &keys::EncodeArgs {
            server_host: str_field(cfg, "server_host"),
            server_port: str_field(cfg, "server_port"),
            server_public_key: str_field(cfg, "server_public_key"),
            udp_port: str_field(cfg, "udp_port"),
            keyserver_url: server.keyserver_url.clone(),
            token,
            expires,
            max_devices,
            enable_udp_data: cfg
                .get("enable_udp_data")
                .and_then(|v| v.as_bool())
                .unwrap_or(true),
            mtu: cfg
                .get("mtu")
                .and_then(|v| v.as_u64())
                .unwrap_or(keys::SAFE_MTU as u64) as u32,
            reality_enabled: cfg
                .get("reality_enabled")
                .and_then(|v| v.as_bool())
                .unwrap_or(false)
                || cfg
                    .get("reality_auth_key")
                    .and_then(|v| v.as_str())
                    .map(|s| !s.is_empty())
                    .unwrap_or(false),
            reality_auth_key: str_field(cfg, "reality_auth_key"),
            reality_sni: {
                let s = str_field(cfg, "reality_sni");
                if s.is_empty() {
                    str_field(cfg, "sni")
                } else {
                    s
                }
            },
            enable_ipv6: cfg.get("enable_ipv6").and_then(|v| v.as_bool()).unwrap_or(false),
        },
        &server.name,
    )
}

#[tauri::command]
fn ping_host(host: String, port: String) -> Option<u32> {
    let addr = format!("{host}:{port}");
    let sock = addr.to_socket_addrs().ok()?.next()?;
    let start = Instant::now();
    TcpStream::connect_timeout(&sock, Duration::from_millis(1200)).ok()?;
    Some(start.elapsed().as_millis() as u32)
}

#[tauri::command]
fn read_clipboard() -> Result<String, String> {
    arboard::Clipboard::new()
        .and_then(|mut c| c.get_text())
        .map_err(|e| e.to_string())
}

#[tauri::command]
fn write_clipboard(text: String) -> Result<(), String> {
    arboard::Clipboard::new()
        .and_then(|mut c| c.set_text(text))
        .map_err(|e| e.to_string())
}

#[tauri::command]
fn pick_ssh_key(app: AppHandle) -> Option<String> {
    app.dialog()
        .file()
        .add_filter("Все файлы (*.*)", &["*"])
        .add_filter("SSH-ключи", &["pem", "pub", "key", "id_rsa", "id_ed25519", "id_ecdsa"])
        .blocking_pick_file()
        .and_then(|p| match p {
            FilePath::Path(path) => Some(path.to_string_lossy().to_string()),
            _ => None,
        })
}

fn str_field(cfg: &Map<String, Value>, key: &str) -> String {
    cfg.get(key)
        .and_then(|v| v.as_str().map(|s| s.to_string()).or_else(|| {
            v.as_u64().map(|n| n.to_string())
        }))
        .unwrap_or_default()
}

fn iso_date(days: u32) -> String {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let t = now + u64::from(days) * 86400;
    let days_since = t / 86400;
    let z = days_since as i64 + 719468;
    let era = if z >= 0 { z } else { z - 146096 } / 146097;
    let doe = (z - era * 146097) as u64;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    format!("{y:04}-{m:02}-{d:02}")
}

fn set_windows_autostart(on: bool) {
    if !cfg!(windows) {
        return;
    }
    let exe = std::env::current_exe()
        .map(|p| format!("\"{}\"", p.display()))
        .unwrap_or_default();
    let _ = std::process::Command::new("schtasks")
        .args(["/Delete", "/TN", "ObsidianVPN", "/F"])
        .output();
    let _ = std::process::Command::new("schtasks")
        .args(["/Delete", "/TN", "ObsidianVPN-Client", "/F"])
        .output();
    if on {
        let _ = std::process::Command::new("schtasks")
            .args([
                "/Create",
                "/TN",
                "ObsidianVPN",
                "/SC",
                "ONLOGON",
                "/RL",
                "HIGHEST",
                "/F",
                "/TR",
                &exe,
            ])
            .output();
    }
}

fn setup_tray(app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    let show = MenuItemBuilder::with_id("show", "Open").build(app)?;
    let quit = MenuItemBuilder::with_id("exit", "Quit").build(app)?;
    let menu = MenuBuilder::new(app).items(&[&show, &quit]).build()?;
    let icon = Image::from_bytes(include_bytes!("../icons/32x32.png"))?;
    TrayIconBuilder::with_id("main")
        .icon(icon)
        .tooltip("ObsidianVPN")
        .menu(&menu)
        .on_menu_event(|app, event| match event.id().as_ref() {
            "show" => {
                if let Some(w) = app.get_webview_window("main") {
                    let _ = w.show();
                    let _ = w.set_focus();
                }
            }
            "exit" => {
                app.state::<Vpn>().disconnect(app);
                app.exit(0);
            }
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            if let tauri::tray::TrayIconEvent::Click { button, .. } = event {
                if button == tauri::tray::MouseButton::Left {
                    if let Some(w) = tray.app_handle().get_webview_window("main") {
                        let _ = w.show();
                        let _ = w.set_focus();
                    }
                }
            }
        })
        .build(app)?;
    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .manage(Vpn::new())
        .invoke_handler(tauri::generate_handler![
            load_state,
            save_settings,
            select_profile,
            decode_preview,
            add_key,
            export_server_uri,
            remove_profile,
            set_split_tunnel,
            connect,
            disconnect,
            start_deploy,
            start_update,
            change_server_sni,
            toggle_server_ipv6,
            reset_server,
            update_server_firmware,
            check_server_version,
            save_server_credentials,
            issue_key,
            qr_svg,
            ping_host,
            pick_ssh_key,
            set_taskbar_progress,
            read_clipboard,
            write_clipboard
        ])
        .setup(|app| {
            crate::vpn::cleanup_system_network();
            setup_tray(app.handle())?;
            if let Some(w) = app.get_webview_window("main") {
                let _ = w.set_focus();
            }
            if std::env::args().any(|a| a == "--connect") {
                let handle = app.handle().clone();
                std::thread::spawn(move || {
                    std::thread::sleep(std::time::Duration::from_millis(700));
                    let _ = handle.emit("auto-connect", ());
                });
            }
            Ok(())
        })
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                if storage::load_settings().minimize_to_tray {
                    api.prevent_close();
                    let _ = window.hide();
                } else {
                    crate::vpn::cleanup_system_network();
                }
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
