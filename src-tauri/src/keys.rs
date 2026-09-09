use data_encoding::BASE32;
use flate2::read::ZlibDecoder;
use flate2::write::ZlibEncoder;
use flate2::Compression;
use serde_json::{json, Map, Value};
use sha2::{Digest, Sha256};
use std::io::{Read, Write};

pub const AUTO_MTU: u32 = 1420;
pub const SAFE_MTU: u32 = 1420;
pub const MAX_TUN_MTU: u32 = 1420;

const DEFAULT_SIGNATURES: [&str; 2] = [
    "<b 0xc00000000108><rc 8><b 0x08><rc 8><b 0x0044b000000001><r 1170>",
    "<r 2><b 0x010000010000000000010377777706676f6f676c6503636f6d00000100010000291000000000000000>",
];

pub fn derive_tun_address(seed: &str) -> String {
    let digest = Sha256::digest(seed.as_bytes());
    let n = u32::from_be_bytes([digest[0], digest[1], digest[2], digest[3]]);
    let host = 2 + (n % 253);
    format!("10.8.0.{host}/24")
}

pub fn assign_client_tun_address(cfg: &mut Map<String, Value>, seed: &str) {
    let current = cfg.get("tun_address").and_then(|v| v.as_str()).unwrap_or("");
    if current.is_empty() || current == "10.8.0.2/24" {
        cfg.insert("tun_address".into(), Value::String(derive_tun_address(seed)));
    }
}

pub fn normalize_mtu(cfg: &mut Map<String, Value>) {
    let mut mtu = cfg
        .get("mtu")
        .and_then(|v| v.as_u64().or_else(|| v.as_str().and_then(|s| s.parse().ok())))
        .unwrap_or(0) as u32;
    let udp = cfg.get("enable_udp_data").and_then(|v| v.as_bool()).unwrap_or(false)
        && cfg
            .get("udp_port")
            .and_then(|v| v.as_str())
            .map(|s| !s.is_empty())
            .unwrap_or(false);
    if mtu == 0 || (udp && mtu == AUTO_MTU) {
        mtu = if udp { SAFE_MTU } else { AUTO_MTU };
    } else if mtu > MAX_TUN_MTU {
        mtu = MAX_TUN_MTU;
    }
    cfg.insert("mtu".into(), json!(mtu));
}

pub struct EncodeArgs {
    pub server_host: String,
    pub server_port: String,
    pub server_public_key: String,
    pub udp_port: String,
    pub keyserver_url: String,
    pub token: String,
    pub expires: String,
    pub max_devices: u32,
    pub enable_udp_data: bool,
    pub mtu: u32,
    pub reality_enabled: bool,
    pub reality_auth_key: String,
    pub reality_sni: String,
    pub enable_ipv6: bool,
}

pub fn encode_key(a: EncodeArgs) -> Result<String, String> {
    let mut mtu = if a.mtu == 0 { AUTO_MTU } else { a.mtu };
    if mtu > MAX_TUN_MTU {
        mtu = MAX_TUN_MTU;
    }
    let udp = if a.udp_port.is_empty() {
        a.server_port.clone()
    } else {
        a.udp_port.clone()
    };
    let mut compact = Map::new();
    compact.insert("h".into(), json!(a.server_host));
    compact.insert("p".into(), json!(a.server_port));
    compact.insert("u".into(), json!(udp));
    compact.insert("k".into(), json!(a.server_public_key));
    compact.insert("j".into(), json!(7));
    compact.insert("ns".into(), json!(10));
    compact.insert("nx".into(), json!(40));
    compact.insert("ka".into(), json!(20));
    compact.insert("d".into(), json!("10.8.0.1"));
    compact.insert("mtu".into(), json!(mtu));
    compact.insert("pv".into(), json!(2));
    compact.insert("eu".into(), json!(a.enable_udp_data));
    compact.insert("v6".into(), json!(a.enable_ipv6));
    if a.reality_enabled {
        compact.insert("re".into(), json!(true));
        if !a.reality_auth_key.is_empty() {
            compact.insert("rk".into(), json!(a.reality_auth_key));
        }
        if !a.reality_sni.is_empty() {
            compact.insert("rs".into(), json!(a.reality_sni));
        }
    }
    if !a.keyserver_url.is_empty() {
        compact.insert("ks".into(), json!(a.keyserver_url));
    }
    if !a.token.is_empty() {
        compact.insert("t".into(), json!(a.token));
    }
    if !a.expires.is_empty() {
        compact.insert("e".into(), json!(a.expires));
    }
    if a.max_devices > 0 {
        compact.insert("m".into(), json!(a.max_devices));
    }

    let raw = serde_json::to_vec(&compact).map_err(|e| e.to_string())?;
    let mut enc = ZlibEncoder::new(Vec::new(), Compression::best());
    enc.write_all(&raw).map_err(|e| e.to_string())?;
    let compressed = enc.finish().map_err(|e| e.to_string())?;
    let b32 = BASE32.encode(&compressed).trim_end_matches('=').to_string();
    let mut chunks = Vec::new();
    let mut i = 0;
    while i < b32.len() {
        let end = (i + 4).min(b32.len());
        chunks.push(&b32[i..end]);
        i = end;
    }
    Ok(format!("OBSDN-{}", chunks.join("-")))
}

fn percent_decode(input: &str) -> String {
    let mut bytes = Vec::new();
    let mut chars = input.bytes();
    while let Some(b) = chars.next() {
        if b == b'%' {
            let h1 = chars.next();
            let h2 = chars.next();
            if let (Some(c1), Some(c2)) = (h1, h2) {
                if let Ok(val) = u8::from_str_radix(
                    &format!("{}{}", c1 as char, c2 as char),
                    16,
                ) {
                    bytes.push(val);
                    continue;
                }
            }
        } else if b == b'+' {
            bytes.push(b' ');
            continue;
        }
        bytes.push(b);
    }
    String::from_utf8_lossy(&bytes).to_string()
}

fn percent_encode(input: &str) -> String {
    let mut out = String::new();
    for b in input.bytes() {
        match b {
            b'a'..=b'z' | b'A'..=b'Z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(b as char);
            }
            _ => {
                out.push_str(&format!("%{:02X}", b));
            }
        }
    }
    out
}

pub fn parse_uri(uri_str: &str) -> Result<Map<String, Value>, String> {
    let trimmed = uri_str.trim();
    if trimmed.is_empty() {
        return Err("Empty URI".into());
    }

    let (without_frag, fragment) = match trimmed.split_once('#') {
        Some((base, frag)) => (base, Some(percent_decode(frag))),
        None => (trimmed, None),
    };

    let (scheme, rest) = without_frag
        .split_once("://")
        .ok_or_else(|| "Missing scheme separator :// in URI".to_string())?;

    let scheme_lower = scheme.to_ascii_lowercase();
    let mut body = rest;
    if scheme_lower == "vpn" {
        if let Some(stripped) = body.strip_prefix("obsidian/") {
            body = stripped;
        }
    } else if scheme_lower != "obsidian" {
        return Err(format!("Unsupported URI scheme: {scheme}"));
    }

    let (authority, query_str) = match body.split_once('?') {
        Some((auth, q)) => (auth, Some(q)),
        None => (body, None),
    };

    let (userinfo, host_port) = match authority.split_once('@') {
        Some((user, hp)) => (Some(percent_decode(user)), hp),
        None => (None, authority),
    };

    let (host, port) = if host_port.starts_with('[') {
        if let Some(close) = host_port.find(']') {
            let host_part = &host_port[1..close];
            let rest = &host_port[close + 1..];
            let port_part = if let Some(p) = rest.strip_prefix(':') {
                p
            } else {
                "8443"
            };
            (host_part.to_string(), port_part.to_string())
        } else {
            return Err("Invalid IPv6 host format".into());
        }
    } else if let Some((h, p)) = host_port.rsplit_once(':') {
        (h.to_string(), p.to_string())
    } else {
        (host_port.to_string(), "8443".to_string())
    };

    if host.is_empty() {
        return Err("Missing host in URI".into());
    }

    let mut query_map: std::collections::HashMap<String, Vec<String>> = std::collections::HashMap::new();
    if let Some(q) = query_str {
        for pair in q.split('&') {
            if pair.is_empty() {
                continue;
            }
            let (k, v) = match pair.split_once('=') {
                Some((key, val)) => (percent_decode(key), percent_decode(val)),
                None => (percent_decode(pair), String::new()),
            };
            query_map.entry(k).or_default().push(v);
        }
    }

    let get_first = |k: &str| -> Option<String> {
        query_map.get(k).and_then(|v| v.first().cloned())
    };

    let mut pub_key = userinfo.unwrap_or_default();
    if pub_key.is_empty() {
        if let Some(pk) = get_first("pk")
            .or_else(|| get_first("pbk"))
            .or_else(|| get_first("server_public_key"))
        {
            pub_key = pk;
        }
    }
    let pub_key = pub_key.trim().to_ascii_lowercase();
    if pub_key.is_empty() {
        return Err("Missing server_public_key in URI".into());
    }

    let mut cfg = Map::new();
    cfg.insert("protocol_version".into(), json!(2));
    cfg.insert("server_host".into(), json!(host));
    cfg.insert("server_port".into(), json!(port));
    cfg.insert("server_public_key".into(), json!(pub_key));

    let udp_port = get_first("udp_port")
        .or_else(|| get_first("udp"))
        .unwrap_or_else(|| port.clone());
    cfg.insert("udp_port".into(), json!(udp_port));

    let enable_udp = get_first("udp_data")
        .or_else(|| get_first("eu"))
        .map(|v| v != "0" && v != "false")
        .unwrap_or(true);
    cfg.insert("enable_udp_data".into(), json!(enable_udp));

    let enable_ipv6 = get_first("ipv6")
        .or_else(|| get_first("v6"))
        .map(|v| v == "1" || v == "true")
        .unwrap_or(false);
    cfg.insert("enable_ipv6".into(), json!(enable_ipv6));

    let no_tls = get_first("no_tls")
        .or_else(|| get_first("nt"))
        .map(|v| v == "1" || v == "true")
        .unwrap_or(false);
    cfg.insert("no_tls".into(), json!(no_tls));

    cfg.insert("tun_address".into(), json!("10.8.0.2/24"));

    let dns = get_first("dns")
        .or_else(|| get_first("d"))
        .unwrap_or_else(|| "1.1.1.1".to_string());
    cfg.insert("dns".into(), json!(dns));

    let mtu = get_first("mtu")
        .and_then(|v| v.parse::<u32>().ok())
        .unwrap_or(AUTO_MTU);
    cfg.insert("mtu".into(), json!(mtu));

    cfg.insert("route_ips".into(), json!([]));

    let junk = get_first("junk")
        .or_else(|| get_first("j"))
        .and_then(|v| v.parse::<u32>().ok())
        .unwrap_or(7);
    cfg.insert("junk_count".into(), json!(junk));
    cfg.insert("junk_min".into(), json!(50));
    cfg.insert("junk_max".into(), json!(1000));

    let ns = get_first("noise_min")
        .or_else(|| get_first("ns"))
        .and_then(|v| v.parse::<f64>().ok())
        .unwrap_or(10.0);
    cfg.insert("noise_min_sec".into(), json!(ns));

    let nx = get_first("noise_max")
        .or_else(|| get_first("nx"))
        .and_then(|v| v.parse::<f64>().ok())
        .unwrap_or(40.0);
    cfg.insert("noise_max_sec".into(), json!(nx));

    let ka = get_first("keepalive")
        .or_else(|| get_first("ka"))
        .and_then(|v| v.parse::<f64>().ok())
        .unwrap_or(20.0);
    cfg.insert("keepalive_sec".into(), json!(ka));

    let profile = get_first("profile").unwrap_or_else(|| "fast-secure".to_string());
    cfg.insert("profile".into(), json!(profile));

    let jitter = get_first("jitter").unwrap_or_else(|| "off".to_string());
    cfg.insert("jitter".into(), json!(jitter));

    if let Some(sigs) = query_map.get("sig") {
        if !sigs.is_empty() {
            cfg.insert("signatures".into(), json!(sigs));
        } else {
            cfg.insert("signatures".into(), json!(DEFAULT_SIGNATURES));
        }
    } else {
        cfg.insert("signatures".into(), json!(DEFAULT_SIGNATURES));
    }

    let sec = get_first("security").unwrap_or_default().to_ascii_lowercase();
    let is_reality = sec == "reality"
        || get_first("reality").map(|v| v == "1" || v == "true").unwrap_or(false)
        || get_first("re").map(|v| v == "1" || v == "true").unwrap_or(false)
        || get_first("sni").is_some()
        || get_first("rs").is_some()
        || get_first("auth_key").is_some()
        || get_first("rk").is_some();

    if is_reality {
        cfg.insert("reality_enabled".into(), json!(true));
        let sni = get_first("sni")
            .or_else(|| get_first("rs"))
            .or_else(|| get_first("reality_sni"))
            .unwrap_or_else(|| "www.microsoft.com".to_string());
        cfg.insert("reality_sni".into(), json!(sni));
        cfg.insert("sni".into(), json!(sni));

        let auth_key = get_first("auth_key")
            .or_else(|| get_first("rk"))
            .or_else(|| get_first("sid"))
            .or_else(|| get_first("reality_auth_key"))
            .unwrap_or_default();
        if !auth_key.is_empty() {
            cfg.insert("reality_auth_key".into(), json!(auth_key));
        }

        let fp = get_first("fp")
            .or_else(|| get_first("fingerprint"))
            .unwrap_or_else(|| "chrome".to_string());
        cfg.insert("fingerprint".into(), json!(fp));
    }

    if let Some(c) = get_first("client_key").or_else(|| get_first("c")) {
        let c = c.trim().to_ascii_lowercase();
        if hex::decode(&c).map(|b| b.len() == 32).unwrap_or(false) {
            cfg.insert("client_private_key".into(), json!(c));
        }
    }

    normalize_mtu(&mut cfg);

    if let Some(ks) = get_first("keyserver").or_else(|| get_first("ks")) {
        cfg.insert("_keyserver".into(), json!(ks));
    }
    if let Some(t) = get_first("token").or_else(|| get_first("t")) {
        cfg.insert("_token".into(), json!(t));
    }
    if let Some(e) = get_first("expires").or_else(|| get_first("e")) {
        cfg.insert("_expires".into(), json!(e));
    }
    if let Some(m) = get_first("max_devices").or_else(|| get_first("m")) {
        if let Ok(n) = m.parse::<u32>() {
            cfg.insert("_max_devices".into(), json!(n));
        }
    }

    if let Some(frag) = fragment {
        if !frag.is_empty() {
            cfg.insert("_label".into(), json!(frag));
        }
    }

    Ok(cfg)
}

pub fn encode_uri(a: &EncodeArgs, label: &str) -> Result<String, String> {
    let mut mtu = if a.mtu == 0 { AUTO_MTU } else { a.mtu };
    if mtu > MAX_TUN_MTU {
        mtu = MAX_TUN_MTU;
    }
    let udp = if a.udp_port.is_empty() {
        a.server_port.clone()
    } else {
        a.udp_port.clone()
    };

    let mut query_params: Vec<(String, String)> = Vec::new();
    if udp != a.server_port {
        query_params.push(("udp_port".into(), udp));
    }
    if !a.enable_udp_data {
        query_params.push(("udp_data".into(), "0".into()));
    }
    if a.enable_ipv6 {
        query_params.push(("ipv6".into(), "1".into()));
    }
    if a.reality_enabled {
        query_params.push(("security".into(), "reality".into()));
        if !a.reality_sni.is_empty() {
            query_params.push(("sni".into(), a.reality_sni.clone()));
        }
        if !a.reality_auth_key.is_empty() {
            query_params.push(("auth_key".into(), a.reality_auth_key.clone()));
        }
    }
    if mtu != AUTO_MTU {
        query_params.push(("mtu".into(), mtu.to_string()));
    }
    if !a.keyserver_url.is_empty() {
        query_params.push(("keyserver".into(), a.keyserver_url.clone()));
    }
    if !a.token.is_empty() {
        query_params.push(("token".into(), a.token.clone()));
    }
    if !a.expires.is_empty() {
        query_params.push(("expires".into(), a.expires.clone()));
    }
    if a.max_devices > 0 {
        query_params.push(("max_devices".into(), a.max_devices.to_string()));
    }

    let host = if a.server_host.contains(':') && !a.server_host.starts_with('[') {
        format!("[{}]", a.server_host)
    } else {
        a.server_host.clone()
    };

    let mut url = format!(
        "obsidian://{}@{}:{}",
        a.server_public_key.to_ascii_lowercase(),
        host,
        a.server_port
    );

    if !query_params.is_empty() {
        let q_str = query_params
            .into_iter()
            .map(|(k, v)| format!("{}={}", percent_encode(&k), percent_encode(&v)))
            .collect::<Vec<_>>()
            .join("&");
        url.push('?');
        url.push_str(&q_str);
    }

    let clean_label = label.trim();
    if !clean_label.is_empty() {
        url.push('#');
        url.push_str(&percent_encode(clean_label));
    }

    Ok(url)
}

pub fn decode_key(key_str: &str) -> Result<Map<String, Value>, String> {
    let trimmed = key_str.trim();
    let lower = trimmed.to_ascii_lowercase();
    if lower.starts_with("obsidian://") || lower.starts_with("vpn://") {
        return parse_uri(trimmed);
    }

    let mut s = trimmed.to_uppercase().replace(' ', "");
    if let Some(rest) = s.strip_prefix("OBSDN-") {
        s = rest.to_string();
    }
    let mut b32 = s.replace('-', "");
    let pad = (8 - b32.len() % 8) % 8;
    b32.push_str(&"=".repeat(pad));
    let raw = BASE32
        .decode(b32.as_bytes())
        .map_err(|e| format!("Invalid key: {e}"))?;
    let mut dec = ZlibDecoder::new(raw.as_slice());
    let mut json_bytes = Vec::new();
    dec.read_to_end(&mut json_bytes)
        .map_err(|e| format!("Invalid key: {e}"))?;
    let compact: Map<String, Value> =
        serde_json::from_slice(&json_bytes).map_err(|e| format!("Invalid key: {e}"))?;
    for req in ["h", "p", "u", "k"] {
        if !compact.contains_key(req) {
            return Err(format!("Key is missing fields: {req}"));
        }
    }

    let mut cfg = Map::new();
    cfg.insert(
        "protocol_version".into(),
        json!(compact.get("pv").and_then(|v| v.as_u64()).unwrap_or(2)),
    );
    cfg.insert("server_host".into(), compact["h"].clone());
    cfg.insert("server_port".into(), compact["p"].clone());
    cfg.insert(
        "udp_port".into(),
        compact.get("u").cloned().unwrap_or(json!("")),
    );
    cfg.insert(
        "enable_udp_data".into(),
        json!(compact.get("eu").and_then(|v| v.as_bool()).unwrap_or(false)),
    );
    cfg.insert(
        "enable_ipv6".into(),
        json!(compact.get("v6").and_then(|v| v.as_bool()).unwrap_or(false)),
    );
    cfg.insert("server_public_key".into(), compact["k"].clone());
    cfg.insert(
        "no_tls".into(),
        json!(compact.get("nt").and_then(|v| v.as_bool()).unwrap_or(false)),
    );
    cfg.insert("tun_address".into(), json!("10.8.0.2/24"));
    cfg.insert(
        "dns".into(),
        compact.get("d").cloned().unwrap_or(json!("1.1.1.1")),
    );
    cfg.insert(
        "mtu".into(),
        compact.get("mtu").cloned().unwrap_or(json!(AUTO_MTU)),
    );
    cfg.insert("route_ips".into(), json!([]));
    cfg.insert(
        "junk_count".into(),
        compact.get("j").cloned().unwrap_or(json!(7)),
    );
    cfg.insert("junk_min".into(), json!(50));
    cfg.insert("junk_max".into(), json!(1000));
    cfg.insert(
        "noise_min_sec".into(),
        compact.get("ns").cloned().unwrap_or(json!(10)),
    );
    cfg.insert(
        "noise_max_sec".into(),
        compact.get("nx").cloned().unwrap_or(json!(40)),
    );
    cfg.insert(
        "keepalive_sec".into(),
        compact.get("ka").cloned().unwrap_or(json!(20)),
    );
    cfg.insert("profile".into(), json!("fast-secure"));
    cfg.insert("jitter".into(), json!("off"));
    cfg.insert("signatures".into(), json!(DEFAULT_SIGNATURES));
    let reality = compact.get("re").and_then(|v| v.as_bool()).unwrap_or(false)
        || compact.get("rk").is_some()
        || compact.get("rs").is_some();
    if reality {
        cfg.insert("reality_enabled".into(), json!(true));
        if let Some(v) = compact.get("rk") {
            cfg.insert("reality_auth_key".into(), v.clone());
        }
        let sni = compact
            .get("rs")
            .and_then(|v| v.as_str())
            .unwrap_or("www.microsoft.com");
        cfg.insert("reality_sni".into(), json!(sni));
        cfg.insert("sni".into(), json!(sni));
        cfg.insert("fingerprint".into(), json!("chrome"));
    }
    if let Some(c) = compact.get("c").and_then(|v| v.as_str()) {
        let c = c.trim().to_lowercase();
        if hex::decode(&c).map(|b| b.len() == 32).unwrap_or(false) {
            cfg.insert("client_private_key".into(), json!(c));
        } else {
            return Err("Invalid pre-provisioned client key".into());
        }
    }
    normalize_mtu(&mut cfg);
    if let Some(v) = compact.get("ks") {
        cfg.insert("_keyserver".into(), v.clone());
    }
    if let Some(v) = compact.get("t") {
        cfg.insert("_token".into(), v.clone());
    }
    if let Some(v) = compact.get("e") {
        cfg.insert("_expires".into(), v.clone());
    }
    if let Some(v) = compact.get("m") {
        cfg.insert("_max_devices".into(), v.clone());
    }
    Ok(cfg)
}

pub fn key_ok(key_str: &str) -> Result<String, String> {
    let cfg = decode_key(key_str)?;
    let host = cfg.get("server_host").and_then(|v| v.as_str()).unwrap_or("");
    let port = cfg.get("server_port").and_then(|v| v.as_str()).unwrap_or("");
    Ok(format!("{host}:{port}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_and_encode_uri() {
        let pk = "170a2fec63c53e4a0c6c866d9d08a3304602b3a9090101765af292a469ac1f27";
        let uri = format!(
            "obsidian://{pk}@95.85.231.206:8443?security=reality&sni=www.microsoft.com&auth_key=d859d03517492c93bbdf73a10bc10cf1&udp_port=8443#Frankfurt"
        );

        let cfg = decode_key(&uri).expect("decode_key failed");
        assert_eq!(cfg["server_host"], "95.85.231.206");
        assert_eq!(cfg["server_port"], "8443");
        assert_eq!(cfg["server_public_key"], pk);
        assert_eq!(cfg["reality_enabled"], true);
        assert_eq!(cfg["reality_sni"], "www.microsoft.com");
        assert_eq!(cfg["_label"], "Frankfurt");

        let args = EncodeArgs {
            server_host: "95.85.231.206".into(),
            server_port: "8443".into(),
            server_public_key: pk.into(),
            udp_port: "8443".into(),
            keyserver_url: "".into(),
            token: "".into(),
            expires: "".into(),
            max_devices: 0,
            enable_udp_data: true,
            mtu: SAFE_MTU,
            reality_enabled: true,
            reality_auth_key: "d859d03517492c93bbdf73a10bc10cf1".into(),
            reality_sni: "www.microsoft.com".into(),
            enable_ipv6: false,
        };
        let re_encoded = encode_uri(&args, "Frankfurt").expect("encode_uri failed");
        assert!(re_encoded.starts_with("obsidian://"));
        assert!(re_encoded.contains("#Frankfurt"));

        let cfg2 = decode_key(&re_encoded).expect("decode re-encoded failed");
        assert_eq!(cfg2["server_host"], cfg["server_host"]);
        assert_eq!(cfg2["_label"], "Frankfurt");
    }

    #[test]
    fn test_vpn_scheme_alias() {
        let pk = "170a2fec63c53e4a0c6c866d9d08a3304602b3a9090101765af292a469ac1f27";
        let uri1 = format!("vpn://obsidian/{pk}@10.0.0.1:9000?udp_port=9000#MyServer");
        let cfg1 = decode_key(&uri1).expect("decode vpn://obsidian/ failed");
        assert_eq!(cfg1["server_host"], "10.0.0.1");
        assert_eq!(cfg1["server_port"], "9000");
        assert_eq!(cfg1["_label"], "MyServer");

        let uri2 = format!("vpn://{pk}@10.0.0.1:9000#DirectVPN");
        let cfg2 = decode_key(&uri2).expect("decode vpn:// failed");
        assert_eq!(cfg2["server_host"], "10.0.0.1");
        assert_eq!(cfg2["_label"], "DirectVPN");
    }

    #[test]
    fn test_legacy_obsdn_key_compatibility() {
        let args = EncodeArgs {
            server_host: "1.2.3.4".into(),
            server_port: "7777".into(),
            server_public_key: "170a2fec63c53e4a0c6c866d9d08a3304602b3a9090101765af292a469ac1f27".into(),
            udp_port: "7777".into(),
            keyserver_url: "".into(),
            token: "".into(),
            expires: "".into(),
            max_devices: 0,
            enable_udp_data: true,
            mtu: SAFE_MTU,
            reality_enabled: false,
            reality_auth_key: "".into(),
            reality_sni: "".into(),
            enable_ipv6: false,
        };
        let obsdn_key = encode_key(args).expect("encode_key failed");
        assert!(obsdn_key.starts_with("OBSDN-"));

        let cfg = decode_key(&obsdn_key).expect("decode legacy key failed");
        assert_eq!(cfg["server_host"], "1.2.3.4");
        assert_eq!(cfg["server_port"], "7777");
    }
}

