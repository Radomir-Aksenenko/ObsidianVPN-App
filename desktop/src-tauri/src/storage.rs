use crate::keys::{assign_client_tun_address, normalize_mtu};
use rand::rngs::OsRng;
use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};
use std::fs;
use std::path::{Path, PathBuf};
use uuid::Uuid;
use x25519_dalek::{PublicKey, StaticSecret};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerProfile {
    pub id: String,
    pub name: String,
    pub config: Map<String, Value>,
    #[serde(default)]
    pub keyserver_url: String,
    #[serde(default)]
    pub token: String,
    #[serde(default)]
    pub expires: String,
    #[serde(default)]
    pub max_devices: u32,
    #[serde(default)]
    pub raw_key: String,
    #[serde(default = "key_source")]
    pub source: String,
    #[serde(default)]
    pub ssh_host: String,
    #[serde(default = "default_ssh_port")]
    pub ssh_port: u16,
    #[serde(default = "default_ssh_user")]
    pub ssh_user: String,
    #[serde(default)]
    pub ssh_password_secret: String,
    #[serde(default = "default_ssh_auth")]
    pub ssh_auth: String,
    #[serde(default)]
    pub ssh_key_path: String,
    #[serde(default)]
    pub keyserver_admin_token: String,
    #[serde(default)]
    pub code: String,
    #[serde(default)]
    pub flag: String,
    #[serde(default = "default_server_version")]
    pub server_version: String,
    #[serde(default)]
    pub needs_update: bool,
}

fn key_source() -> String {
    "key".into()
}
fn default_ssh_port() -> u16 {
    22
}
fn default_ssh_user() -> String {
    "root".into()
}
fn default_ssh_auth() -> String {
    "password".into()
}
fn default_server_version() -> String {
    // Unknown until the server is checked over SSH.
    String::new()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IssuedKey {
    pub id: String,
    pub name: String,
    pub server_id: String,
    pub server_code: String,
    pub devices: u32,
    pub days: u32,
    pub key: String,
    pub created: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Settings {
    #[serde(default)]
    pub autostart: bool,
    #[serde(default = "default_true")]
    pub minimize_to_tray: bool,
    #[serde(default)]
    pub kill_switch: bool,
    #[serde(default)]
    pub last_profile_id: String,
}

fn default_true() -> bool {
    true
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            autostart: false,
            minimize_to_tray: true,
            kill_switch: false,
            last_profile_id: String::new(),
        }
    }
}

pub fn app_dir() -> PathBuf {
    let base = std::env::var("APPDATA")
        .ok()
        .map(PathBuf::from)
        .unwrap_or_else(|| std::env::temp_dir());
    let dir = base.join("ObsidianVPN");
    let _ = fs::create_dir_all(&dir);
    dir
}

pub fn runtime_dir() -> PathBuf {
    let dir = app_dir().join("runtime");
    let _ = fs::create_dir_all(&dir);
    dir
}

pub fn device_id() -> String {
    let path = app_dir().join("device_id.txt");
    if let Ok(v) = fs::read_to_string(&path) {
        let v = v.trim();
        if !v.is_empty() {
            return v.to_string();
        }
    }
    let id = Uuid::new_v4().to_string();
    let _ = fs::write(&path, &id);
    id
}

pub fn short_device_id() -> String {
    let id: String = device_id()
        .chars()
        .filter(|c| c.is_ascii_hexdigit())
        .take(12)
        .collect::<String>()
        .to_uppercase();
    let pad = format!("{:0<12}", id);
    format!("{}-{}-{}", &pad[0..4], &pad[4..8], &pad[8..12])
}

pub fn load_profiles() -> Vec<ServerProfile> {
    read_json(&app_dir().join("servers.json")).unwrap_or_default()
}

pub fn save_profiles(profiles: &[ServerProfile]) -> Result<(), String> {
    write_json(&app_dir().join("servers.json"), profiles)
}

pub fn deduplicate_issued(keys: &mut Vec<IssuedKey>) {
    let mut seen_owners = std::collections::HashSet::new();
    keys.retain(|k| {
        let is_owner = k.name.eq_ignore_ascii_case("owner") || k.name.eq_ignore_ascii_case("владелец");
        if is_owner {
            let key_id = if !k.server_id.is_empty() {
                k.server_id.clone()
            } else {
                k.server_code.clone()
            };
            if seen_owners.contains(&key_id) {
                return false;
            }
            seen_owners.insert(key_id);
        }
        true
    });
}

pub fn load_issued() -> Vec<IssuedKey> {
    let mut keys: Vec<IssuedKey> = read_json(&app_dir().join("issued.json")).unwrap_or_default();
    deduplicate_issued(&mut keys);
    keys
}

pub fn save_issued(keys: &[IssuedKey]) -> Result<(), String> {
    let mut deduped = keys.to_vec();
    deduplicate_issued(&mut deduped);
    write_json(&app_dir().join("issued.json"), &deduped)
}

pub fn load_settings() -> Settings {
    read_json(&app_dir().join("settings.json")).unwrap_or_default()
}

pub fn save_settings(settings: &Settings) -> Result<(), String> {
    write_json(&app_dir().join("settings.json"), settings)
}

pub fn write_client_config(profile: &mut ServerProfile) -> Result<PathBuf, String> {
    let mut cfg = profile.config.clone();
    ensure_client_identity(&mut cfg);
    let seed = format!(
        "{}|{}|{}|{}|{}",
        profile.token,
        device_id(),
        profile.id,
        cfg.get("server_host").and_then(|v| v.as_str()).unwrap_or(""),
        cfg.get("server_public_key")
            .and_then(|v| v.as_str())
            .unwrap_or("")
    );
    assign_client_tun_address(&mut cfg, &seed);
    normalize_mtu(&mut cfg);
    if cfg.get("dns").and_then(|v| v.as_str()) == Some("10.8.0.1") {
        cfg.insert("dns".into(), json!("1.1.1.1"));
    }
    profile.config = cfg.clone();
    let path = app_dir().join(format!("{}.json", profile.id));
    let body = serde_json::to_string_pretty(&cfg).map_err(|e| e.to_string())?;
    fs::write(&path, body).map_err(|e| e.to_string())?;
    Ok(path)
}

pub fn ensure_client_identity(cfg: &mut Map<String, Value>) {
    let existing = cfg
        .get("client_private_key")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    if let Ok(bytes) = hex::decode(&existing) {
        if bytes.len() == 32 {
            let mut arr = [0u8; 32];
            arr.copy_from_slice(&bytes);
            let secret = StaticSecret::from(arr);
            let public = PublicKey::from(&secret);
            cfg.insert(
                "client_public_key".into(),
                json!(hex::encode(public.to_bytes())),
            );
            return;
        }
    }
    let secret = StaticSecret::random_from_rng(OsRng);
    let public = PublicKey::from(&secret);
    cfg.insert(
        "client_private_key".into(),
        json!(hex::encode(secret.to_bytes())),
    );
    cfg.insert(
        "client_public_key".into(),
        json!(hex::encode(public.to_bytes())),
    );
}

pub fn server_meta(name: &str) -> (String, String) {
    let lower = name.to_lowercase();
    if lower.contains("frankfurt") || lower.contains("germany") {
        return ("DE".into(), "DE-FRA-01".into());
    }
    if lower.contains("amsterdam") || lower.contains("nether") {
        return ("NL".into(), "NL-AMS-01".into());
    }
    if lower.contains("london") {
        return ("GB".into(), "GB-LON-01".into());
    }
    if lower.contains("paris") {
        return ("FR".into(), "FR-PAR-01".into());
    }
    if lower.contains("warsaw") {
        return ("PL".into(), "PL-WAW-01".into());
    }
    if lower.contains("helsinki") {
        return ("FI".into(), "FI-HEL-01".into());
    }
    if lower.contains("moscow") {
        return ("RU".into(), "RU-MOW-01".into());
    }
    let slug = name
        .chars()
        .filter(|c| c.is_ascii_alphanumeric())
        .take(3)
        .collect::<String>()
        .to_uppercase();
    let slug = if slug.is_empty() {
        "SRV".to_string()
    } else {
        slug
    };
    ("UN".into(), format!("XX-{slug}-01"))
}

fn read_json<T: serde::de::DeserializeOwned>(path: &Path) -> Option<T> {
    let data = fs::read_to_string(path).ok()?;
    serde_json::from_str(&data).ok()
}

fn write_json<T: Serialize + ?Sized>(path: &Path, value: &T) -> Result<(), String> {
    let body = serde_json::to_string_pretty(value).map_err(|e| e.to_string())?;
    fs::write(path, body).map_err(|e| e.to_string())
}
