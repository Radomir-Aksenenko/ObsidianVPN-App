import 'dart:convert';

import 'package:obsidian_vpn/vps/vps_models.dart';

// Paths, names and ports of the server layout. Mirrors desktop/src-tauri/src/installer.rs.
const String kServerDir = '/opt/obsidian';
const String kServerBin = '$kServerDir/obsidian-server';
const String kServerConfig = '$kServerDir/obsidian-server.json';
const String kKeyserverScript = '$kServerDir/keyserver.py';
const String kVersionFile = '$kServerDir/version.txt';
const String kVpnContainer = 'obsidian-vpn';
const String kKeyserverContainer = 'obsidian-keyserver';
const String kVpnImage = 'ubuntu:22.04';
const String kKeyserverImage = 'python:3.11-slim';
const int kKeyserverPort = 8444;

/// Fallback port used when 443 is held by a foreign service.
const String kAltPort = '8443';

/// Preferred TCP and UDP ports, in order.
const List<String> kPreferredPorts = ['443', kAltPort];

/// Public IPv6 address used to probe IPv6 connectivity on the server.
const String kIpv6ProbeTarget = '2606:4700:4700::1111';

/// Asset paths. Binaries are chosen by the server architecture.
const String kKeyserverAsset = 'assets/bin/keyserver.py';

String serverBinaryAsset(String arch) => 'assets/bin/obsidian-server-linux-$arch';

// Commands run on the server.
const String kUnameCmd = 'uname -m';
const String kDockerVersionCmd = 'docker --version 2>/dev/null || echo MISSING';
const List<String> kDockerInstallCmds = [
  'apt-get update -qq && apt-get install -y -qq curl',
  'curl -fsSL https://get.docker.com | sh',
  'systemctl enable docker && systemctl start docker',
];
const String kPython3Cmd =
    'command -v python3 >/dev/null || (apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3)';
const String kIpForwardCmd = 'sysctl -w net.ipv4.ip_forward=1';
const String kIpForwardPersistCmd =
    "grep -q 'net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf";
const String kIpv6ForwardCmd = 'sysctl -w net.ipv6.conf.all.forwarding=1';
const String kIpv6ForwardPersistCmd =
    "grep -q 'net.ipv6.conf.all.forwarding=1' /etc/sysctl.conf || echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf";
const String kIfaceCmd =
    r"ip route show default | awk '/default/{print $5}' | head -1";
const String kSha256BinCmd =
    r"sha256sum /opt/obsidian/obsidian-server 2>/dev/null | awk '{print $1}'";
const String kBinExistsCmd =
    'test -f $kServerBin && echo EXISTS || echo NO';
const String kInstallExistsCmd =
    'test -f $kServerBin && test -f $kServerConfig && echo OK || echo MISSING';

/// Prints EXISTS when the install directory is already on the server. A deploy that
/// did not create it must never delete it on rollback.
const String kServerDirExistsCmd = 'test -e $kServerDir && echo EXISTS || echo NO';

/// Prints the numeric user id. Everything below needs root (apt, docker, iptables).
const String kUidCmd = 'id -u';

/// Succeeds when the docker daemon answers, starting it once when it does not.
const String kDockerReadyCmd =
    'docker info >/dev/null 2>&1 || (systemctl start docker >/dev/null 2>&1; sleep 3; '
    'docker info >/dev/null 2>&1)';

/// Pulling a base image can take long on a slow VPS.
const Duration kDockerRunTimeout = Duration(minutes: 10);

/// Files a deploy writes inside [kServerDir].
const List<String> kDeployFiles = [
  kServerBin,
  kServerConfig,
  kVersionFile,
  kKeyserverScript,
];

/// Undo of a failed deploy. When this deploy created [kServerDir] the whole directory
/// goes. When the directory was already there (leftovers of an earlier attempt, or other
/// data), only the files this deploy wrote are removed.
String rollbackFilesCmd({required bool dirExisted}) => dirExisted
    ? 'rm -f ${kDeployFiles.join(' ')} 2>/dev/null || true'
    : 'rm -rf $kServerDir 2>/dev/null || true';
const String kReadVersionFileCmd = 'cat $kVersionFile 2>/dev/null || echo MISSING';
const String kReadConfigCmd = 'cat $kServerConfig';
const String kVpnPidsCmd = 'docker top $kVpnContainer -o pid 2>/dev/null';
const String kBackupCmd =
    'cp -f $kServerBin $kServerBin.bak && cp -f $kServerConfig $kServerConfig.bak';
const String kRestoreCmd =
    'test -f $kServerBin.bak && cp -f $kServerBin.bak $kServerBin; '
    'test -f $kServerConfig.bak && cp -f $kServerConfig.bak $kServerConfig; '
    'docker restart $kVpnContainer >/dev/null 2>&1; true';

/// Shell command that prints IPV6_OK when the server has an IPv6 default route and
/// can ping the probe target, IPV6_NONE otherwise.
String probeIpv6Command() =>
    'ip -6 route show default 2>/dev/null | grep -q default && '
    '(ping6 -c 1 -W 2 $kIpv6ProbeTarget >/dev/null 2>&1 || '
    'ping -6 -c 1 -W 2 $kIpv6ProbeTarget >/dev/null 2>&1) && echo IPV6_OK || echo IPV6_NONE';

bool parseIpv6Probe(String out) => out.contains('IPV6_OK');

String containerRunningCmd(String name) =>
    "docker inspect -f '{{.State.Running}}' $name 2>/dev/null || echo false";

bool isRunningOutput(String out) => out.toLowerCase().contains('true');

String removeContainerCmd(String name) => 'docker rm -f $name 2>/dev/null || true';

String restartContainerCmd(String name) => 'docker restart $name';

String dockerLogsCmd(String name, int tail) => 'docker logs --tail $tail $name 2>&1';

/// Uses ss output of the given protocol, with a port filter applied later in Dart.
String ssCommand(String proto) => proto == 'udp' ? 'ss -lnup 2>/dev/null' : 'ss -lntp 2>/dev/null';

/// Keyserver URL as stored in the keys (IPv6 hosts bracketed).
String keyserverUrl(String host) {
  final h = host.trim();
  final shown = h.contains(':') && !h.startsWith('[') ? '[$h]' : h;
  return 'http://$shown:$kKeyserverPort';
}

/// Trims the input and drops ":443" suffixes. Lower case. Empty input gives
/// [kDefaultSni]. Throws [VpsException] on an invalid host name, because the value
/// is written into a server script.
String normalizeSni(String? raw) {
  var s = (raw ?? '').trim();
  while (s.endsWith(':443')) {
    s = s.substring(0, s.length - 4).trim();
  }
  s = s.toLowerCase();
  if (s.isEmpty) return kDefaultSni;
  if (!isValidSni(s)) {
    throw VpsException('Некорректный SNI "$s": укажите имя хоста, например www.microsoft.com.');
  }
  return s;
}

final RegExp _sniPattern = RegExp(
  r'^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$',
);

bool isValidSni(String sni) => sni.length <= 253 && _sniPattern.hasMatch(sni);

/// Maps `uname -m` output to the server binary suffix. Null when unsupported.
String? serverArchFromUname(String uname) {
  final lines = uname.trim().split('\n');
  final arch = lines.isEmpty ? '' : lines.last.trim();
  switch (arch) {
    case 'x86_64' || 'amd64':
      return 'amd64';
    case 'aarch64' || 'arm64':
      return 'arm64';
    default:
      return null;
  }
}

/// Lower-case hex of [bytes].
String hexEncode(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Python/JSON string literal for [s]. Callers validate [s] first.
String pyStr(String s) => jsonEncode(s);

// ---------------------------------------------------------------------------
// Port selection

enum PortUse { free, ours, foreign }

/// Who holds a local port: nobody, our own unit, or a foreign process ([who]).
class PortOwner {
  const PortOwner._(this.use, this.who);
  const PortOwner.free() : this._(PortUse.free, '');
  const PortOwner.ours() : this._(PortUse.ours, '');
  const PortOwner.foreign(String who) : this._(PortUse.foreign, who);

  final PortUse use;
  final String who;

  @override
  bool operator ==(Object other) =>
      other is PortOwner && other.use == use && other.who == who;

  @override
  int get hashCode => Object.hash(use, who);

  @override
  String toString() => 'PortOwner($use, $who)';
}

const Set<String> _ssNetids = {'tcp', 'udp', 'tcp6', 'udp6'};

/// Reads `ss -lntp` / `ss -lnup` output and decides who holds exactly [port].
/// Sockets of obsidian-server, or of a pid in [vpnPids] (processes of the VPN
/// container, which runs with --network host), count as ours.
PortOwner parseSsListing(String out, String port, {Set<String> vpnPids = const {}}) {
  var listed = false;
  var unknown = false;
  final foreign = <String>[];
  for (final line in out.split('\n')) {
    final cols = line.trim().split(RegExp(r'\s+'));
    // The local address is the 4th column, or the 5th when ss prints a Netid column
    // ("tcp LISTEN 0 128 0.0.0.0:443 ..."). The port is the part after the last ':'.
    final at = _ssNetids.contains(cols[0]) ? 4 : 3;
    if (cols.length <= at) continue;
    if (cols[at].split(':').last != port) continue;
    listed = true;
    final usersAt = line.indexOf('users:((');
    final users = usersAt < 0 ? '' : line.substring(usersAt);
    var hasEntry = false;
    for (final entry in users.split('("').skip(1)) {
      hasEntry = true;
      final name = entry.split('"').first;
      final pidPart = entry.split('pid=');
      final pidRaw = pidPart.length > 1 ? pidPart[1] : '';
      final pid = pidRaw.split(RegExp(r'[^0-9]')).first;
      final ours = name == 'obsidian-server' || vpnPids.contains(pid);
      if (!ours && !foreign.contains(name)) foreign.add(name);
    }
    if (!hasEntry) unknown = true;
  }
  if (!listed) return const PortOwner.free();
  if (foreign.isNotEmpty) return PortOwner.foreign(foreign.join(', '));
  if (unknown) return const PortOwner.foreign('неизвестный процесс');
  return const PortOwner.ours();
}

/// Returns the first candidate that is free or ours. [ownerOf] looks a port up
/// on the server. [log] receives one line when a candidate was skipped.
/// Throws [VpsException] when every candidate is held by a foreign process.
Future<String> pickPort({
  required String proto,
  required List<String> candidates,
  required Future<PortOwner> Function(String port) ownerOf,
  void Function(String line)? log,
}) async {
  final label = proto.toUpperCase();
  String? skippedPort;
  String? skippedWho;
  final busy = <String>[];
  for (final port in candidates) {
    final owner = await ownerOf(port);
    if (owner.use != PortUse.foreign) {
      if (skippedPort != null) {
        log?.call('$label $skippedPort занят ($skippedWho), оставляю порт $port');
      }
      return port;
    }
    skippedPort ??= port;
    skippedWho ??= owner.who;
    if (!busy.contains(port)) busy.add(port);
  }
  throw VpsException(
    'Не удалось выбрать порт $label: заняты ${busy.join(', ')}. '
    'Освободите один из них на сервере и повторите.',
  );
}

/// Pids of the VPN container processes from `docker top -o pid` (header skipped).
List<String> parseDockerTopPids(String out) {
  return out
      .split('\n')
      .skip(1)
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
}

/// Reads an integer port from the server config. Strings and numbers are both
/// accepted, as in installer.rs json_port.
String? jsonPortOf(Map<String, dynamic> cfg, String key) {
  final v = cfg[key];
  if (v is String && v.trim().isNotEmpty) return v.trim();
  if (v is num) return v.toString();
  return null;
}

/// Splits "KEY=value" lines printed by the server scripts.
Map<String, String> parseKeyValues(String out) {
  final map = <String, String>{};
  for (final line in out.split('\n')) {
    final eq = line.indexOf('=');
    if (eq <= 0) continue;
    map[line.substring(0, eq).trim()] = line.substring(eq + 1).trim();
  }
  return map;
}

String? interfaceFromRoute(String out) {
  final name = out.split('\n').map((l) => l.trim()).firstWhere(
        (l) => l.isNotEmpty,
        orElse: () => '',
      );
  return RegExp(r'^[A-Za-z0-9_.@:-]{1,15}$').hasMatch(name) ? name : null;
}

// ---------------------------------------------------------------------------
// Docker run lines

/// VPN core container. Runs with --network host so it owns tun0 and the ports.
String vpnDockerRunCmd() =>
    'docker run -d --name $kVpnContainer --network host --cap-add NET_ADMIN '
    '--device /dev/net/tun --restart always -v $kServerDir:$kServerDir $kVpnImage '
    'sh -c "apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq '
    'iproute2 iptables >/dev/null && exec $kServerBin --config $kServerConfig"';

/// Keyserver container. Contains the admin token, so the command must not be logged.
String keyserverDockerRunCmd(String adminToken) =>
    'docker run -d --name $kKeyserverContainer --network host --restart always '
    '-v $kServerDir:$kServerDir -e ADMIN_TOKEN=$adminToken -e KEYSERVER_PORT=$kKeyserverPort '
    '-e KEYSERVER_BIND=127.0.0.1 -e KEYS_FILE=$kServerDir/keys.json '
    '-e REVOCATIONS_FILE=$kServerDir/revoked_clients.json -e SERVER_CONFIG=$kServerConfig '
    '$kKeyserverImage python3 $kKeyserverScript';

// ---------------------------------------------------------------------------
// Firewall and NAT

/// One remote command. [required] steps stop the operation on failure.
class CmdStep {
  const CmdStep(this.cmd, {this.required = false});

  final String cmd;
  final bool required;
}

/// Adds the rule when it is missing: `-C` check, else `-A` (or `-I` for [insert]).
String ensureRule(
  String tool,
  String table,
  String chain,
  String spec, {
  bool insert = false,
}) {
  final t = table.isEmpty ? '' : '-t $table ';
  final add = insert ? '-I' : '-A';
  return '$tool $t-C $chain $spec 2>/dev/null || $tool $t$add $chain $spec';
}

/// NAT, forwarding, MSS clamp, INPUT and firewall steps for the VPN unit.
List<CmdStep> natSteps({
  required String iface,
  required String tcpPort,
  required String udpPort,
  required bool ipv6,
}) {
  final steps = <CmdStep>[
    CmdStep(
      ensureRule('iptables', 'nat', 'POSTROUTING', '-s 10.8.0.0/24 -o $iface -j MASQUERADE'),
      required: true,
    ),
    CmdStep(ensureRule('iptables', '', 'FORWARD', '-i tun0 -o $iface -j ACCEPT'), required: true),
    CmdStep(
      ensureRule(
        'iptables',
        '',
        'FORWARD',
        '-i $iface -o tun0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT',
      ),
      required: true,
    ),
    CmdStep(
      ensureRule(
        'iptables',
        'mangle',
        'FORWARD',
        '-i tun0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1380',
      ),
    ),
    CmdStep(
      ensureRule(
        'iptables',
        'mangle',
        'FORWARD',
        '-o tun0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1380',
      ),
    ),
  ];
  if (ipv6) {
    steps.addAll([
      CmdStep(
        ensureRule('ip6tables', 'nat', 'POSTROUTING', '-s fd00:8::/64 -o $iface -j MASQUERADE'),
      ),
      CmdStep(ensureRule('ip6tables', '', 'FORWARD', '-i tun0 -o $iface -j ACCEPT')),
      CmdStep(
        ensureRule(
          'ip6tables',
          '',
          'FORWARD',
          '-i $iface -o tun0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT',
        ),
      ),
      CmdStep(
        ensureRule(
          'ip6tables',
          'mangle',
          'FORWARD',
          '-i tun0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1340',
        ),
      ),
      CmdStep(
        ensureRule(
          'ip6tables',
          'mangle',
          'FORWARD',
          '-o tun0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1340',
        ),
      ),
    ]);
  }
  for (final proto in ['udp', 'tcp']) {
    steps.add(
      CmdStep(
        ensureRule('iptables', '', 'INPUT', '-i tun0 -p $proto --dport 53 -j ACCEPT'),
        required: true,
      ),
    );
  }
  for (final pair in [('tcp', tcpPort), ('udp', udpPort)]) {
    steps.add(
      CmdStep(
        ensureRule('iptables', '', 'INPUT', '-p ${pair.$1} --dport ${pair.$2} -j ACCEPT'),
        required: true,
      ),
    );
  }
  steps.addAll([
    CmdStep(
      ensureRule(
        'iptables',
        '',
        'INPUT',
        '-i lo -p tcp --dport $kKeyserverPort -j ACCEPT',
        insert: true,
      ),
    ),
    CmdStep(
      ensureRule(
        'iptables',
        '',
        'INPUT',
        '-p tcp --dport $kKeyserverPort ! -i lo -j DROP',
        insert: true,
      ),
    ),
    CmdStep('ufw allow $tcpPort/tcp 2>/dev/null || true'),
    CmdStep('ufw allow $udpPort/udp 2>/dev/null || true'),
  ]);
  return steps;
}

/// Removes the leftover 8443 and 8444 firewall rules, except the ports in [keep]
/// (pairs of proto and port).
List<CmdStep> closeLegacyPortsSteps(List<(String, String)> keep) {
  final steps = <CmdStep>[];
  for (final port in [kAltPort, '$kKeyserverPort']) {
    for (final proto in ['tcp', 'udp']) {
      if (keep.contains((proto, port))) continue;
      steps.add(CmdStep('ufw delete allow $port/$proto >/dev/null 2>&1 || true'));
      steps.add(
        CmdStep(
          'for i in 1 2 3 4 5; do iptables -D INPUT -p $proto --dport $port -j ACCEPT '
          '2>/dev/null || break; done',
        ),
      );
    }
  }
  return steps;
}

// ---------------------------------------------------------------------------
// Server config

/// Server config for a fresh install. Same keys and values as installer.rs.
Map<String, dynamic> buildServerConfig({
  required String sni,
  required String tcpPort,
  required String udpPort,
  required String iface,
  required bool enableIpv6,
  required String serverPrivateKeyHex,
  required String serverPublicKeyHex,
  required String realityAuthKey,
}) {
  return {
    'host': '0.0.0.0',
    'protocol_version': 2,
    'port': tcpPort,
    'no_tls': false,
    'reality_target': '$sni:443',
    'reality_backend': '$sni:443',
    'reality_backend_sni': sni,
    'reality_server_names': [sni],
    'reality_auth_key': realityAuthKey,
    'server_private_key': serverPrivateKeyHex,
    'server_public_key': serverPublicKeyHex,
    'tun_interface': 'tun0',
    'tun_address': '10.8.0.1/24',
    'mtu': 1420,
    'out_interface': iface,
    'dns_upstream': '1.1.1.1:53',
    'dns_listen': '10.8.0.1:53',
    'disable_dns_proxy': false,
    'enable_ipv6': enableIpv6,
    'udp_port': udpPort,
    'enable_udp_data': true,
    'udp_socket_buffer_mb': 16,
    'allowed_clients': <String>[],
    'revocation_file': '$kServerDir/revoked_clients.json',
    'junk_count': 7,
    'junk_min': 50,
    'junk_max': 1000,
    'noise_min_sec': 10,
    'noise_max_sec': 40,
    'keepalive_sec': 20,
    'profile': 'fast-secure',
    'jitter': 'off',
    'signatures': [
      '<b 0xc00000000108><rc 8><b 0x08><rc 8><b 0x0044b000000001><r 1170>',
      '<r 2><b 0x010000010000000000010377777706676f6f676c6503636f6d00000100010000291000000000000000>',
    ],
  };
}

String buildServerConfigJson({
  required String sni,
  required String tcpPort,
  required String udpPort,
  required String iface,
  required bool enableIpv6,
  required String serverPrivateKeyHex,
  required String serverPublicKeyHex,
  required String realityAuthKey,
}) {
  final map = buildServerConfig(
    sni: sni,
    tcpPort: tcpPort,
    udpPort: udpPort,
    iface: iface,
    enableIpv6: enableIpv6,
    serverPrivateKeyHex: serverPrivateKeyHex,
    serverPublicKeyHex: serverPublicKeyHex,
    realityAuthKey: realityAuthKey,
  );
  return const JsonEncoder.withIndent('  ').convert(map);
}

/// Wraps [body] as a `python3 -` heredoc run on the server.
String _pyHeredoc(String body) => "python3 - <<'PY'\n$body\nPY";

/// New ports for an update. REALITY is migrated only when TCP moves to 443.
class UpdatePlan {
  const UpdatePlan({
    required this.tcp,
    required this.udp,
    required this.migrateReality,
    required this.sni,
    required this.enableIpv6,
  });

  final String tcp;
  final String udp;
  final bool migrateReality;
  final String sni;
  final bool enableIpv6;
}

/// Rewrites the config for an update. Prints AUTH=, SNI=, REALITY=.
String updateConfigScript(UpdatePlan plan) {
  final ipv6 = plan.enableIpv6 ? 'True' : 'False';
  final migrate = plan.migrateReality ? 'True' : 'False';
  return _pyHeredoc('''
import json, os, secrets
path = ${pyStr(kServerConfig)}
tmp = path + ".tmp"
with open(path) as f:
    cfg = json.load(f)
cfg["port"] = ${pyStr(plan.tcp)}
cfg["udp_port"] = ${pyStr(plan.udp)}
cfg["enable_ipv6"] = $ipv6
if $migrate:
    sni = ${pyStr(plan.sni)}
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
''');
}

/// Points REALITY at [sni]. Prints SNI_OK on success.
String changeSniScript(String sni) => _pyHeredoc('''
import json, os
path = ${pyStr(kServerConfig)}
tmp = path + ".tmp"
sni = ${pyStr(sni)}
with open(path) as f:
    cfg = json.load(f)
cfg["reality_target"] = sni + ":443"
cfg["reality_backend"] = sni + ":443"
cfg["reality_backend_sni"] = sni
cfg["reality_server_names"] = [sni]
with open(tmp, "w") as f:
    json.dump(cfg, f, indent=2)
os.replace(tmp, path)
print("SNI_OK")
''');

/// Sets enable_ipv6 in the server config. Prints V6=, TCP= and UDP=.
String setIpv6Script(bool enabled) => _pyHeredoc('''
import json, os
path = ${pyStr(kServerConfig)}
tmp = path + ".tmp"
with open(path) as f:
    cfg = json.load(f)
cfg["enable_ipv6"] = ${enabled ? 'True' : 'False'}
with open(tmp, "w") as f:
    json.dump(cfg, f, indent=2)
os.replace(tmp, path)
print("V6=" + ("1" if cfg.get("enable_ipv6") else "0"))
print("TCP=" + str(cfg.get("port") or ""))
print("UDP=" + str(cfg.get("udp_port") or cfg.get("port") or ""))
''');

/// Installs new keys, clears clients and revocations. Prints RESET_OK, SNI=, TCP=, UDP=, V6=.
String resetScript({
  required String serverPrivateKeyHex,
  required String serverPublicKeyHex,
  required String realityAuthKey,
}) =>
    _pyHeredoc('''
import json, os
path = ${pyStr(kServerConfig)}
tmp = path + ".tmp"
cfg_priv = ${pyStr(serverPrivateKeyHex)}
cfg_pub = ${pyStr(serverPublicKeyHex)}
cfg_auth = ${pyStr(realityAuthKey)}
with open(path) as f:
    cfg = json.load(f)
cfg["server_private_key"] = cfg_priv
cfg["server_public_key"] = cfg_pub
cfg["reality_auth_key"] = cfg_auth
cfg["allowed_clients"] = []
with open(tmp, "w") as f:
    json.dump(cfg, f, indent=2)
os.replace(tmp, path)
try:
    with open(${pyStr('$kServerDir/keys.json')}, "w") as f:
        f.write("{}\\n")
except Exception:
    pass
try:
    with open(${pyStr('$kServerDir/revoked_clients.json')}, "w") as f:
        f.write('{"revoked_clients": []}\\n')
except Exception:
    pass
print("RESET_OK")
print("SNI=" + str(cfg.get("reality_backend_sni") or ""))
print("TCP=" + str(cfg.get("port") or ""))
print("UDP=" + str(cfg.get("udp_port") or cfg.get("port") or ""))
print("V6=" + ("1" if cfg.get("enable_ipv6") else "0"))
''');

/// Content of version.txt: the core version and the SHA256 of the binary.
String versionFileContent(String version, String sha256Hex) => '$version\n$sha256Hex\n';

/// Parsed version.txt. [missing] means the file is absent on the server.
class RemoteVersionFile {
  const RemoteVersionFile({required this.missing, this.version, this.hash = ''});

  final bool missing;
  final String? version;
  final String hash;
}

RemoteVersionFile parseVersionFile(String out) {
  if (out.contains('MISSING')) return const RemoteVersionFile(missing: true);
  final lines = out
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  return RemoteVersionFile(
    missing: false,
    version: lines.isNotEmpty ? lines[0] : null,
    hash: lines.length > 1 ? lines[1] : '',
  );
}

/// Parses "1.2.3". A leading "v" and any "-pre" or "+build" suffix are ignored.
({int major, int minor, int patch})? parseVersion(String v) {
  var core = v.trim();
  while (core.startsWith('v')) {
    core = core.substring(1);
  }
  core = core.split(RegExp(r'[-+]')).first;
  final parts = core.split('.');
  final major = int.tryParse(parts[0]);
  if (major == null) return null;
  var minor = 0;
  var patch = 0;
  if (parts.length > 1) {
    final m = int.tryParse(parts[1]);
    if (m == null) return null;
    minor = m;
  }
  if (parts.length > 2) {
    final p = int.tryParse(parts[2]);
    if (p == null) return null;
    patch = p;
  }
  return (major: major, minor: minor, patch: patch);
}

int compareVersions(
  ({int major, int minor, int patch}) a,
  ({int major, int minor, int patch}) b,
) {
  if (a.major != b.major) return a.major.compareTo(b.major);
  if (a.minor != b.minor) return a.minor.compareTo(b.minor);
  return a.patch.compareTo(b.patch);
}

/// The server core is outdated when its binary differs from the bundled one and its
/// version is older than this build. A matching binary is never outdated. An equal
/// version with a different binary is outdated. A newer server is never downgraded.
bool coreNeedsUpdate({
  required String? remoteVersion,
  required String remoteHash,
  required String localHash,
  required String bundledVersion,
}) {
  if (remoteHash.isNotEmpty && remoteHash == localHash) return false;
  final hashDiffers = remoteHash.isNotEmpty;
  final local = parseVersion(bundledVersion) ?? (major: 0, minor: 0, patch: 0);
  final remote = remoteVersion == null ? null : parseVersion(remoteVersion);
  if (remote == null) return hashDiffers;
  final cmp = compareVersions(remote, local);
  if (cmp < 0) return true;
  if (cmp == 0) return hashDiffers;
  return false;
}
