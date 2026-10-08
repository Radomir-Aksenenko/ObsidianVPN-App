import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/vps/deploy_scripts.dart';
import 'package:obsidian_vpn/vps/ssh_session.dart' show shellQuote, streamUploadCommand;
import 'package:obsidian_vpn/vps/vps_models.dart';

const String _nginxTcp443 =
    'LISTEN 0 511 0.0.0.0:443 0.0.0.0:* users:(("nginx",pid=83216,fd=5),("nginx",pid=69121,fd=5))';
const String _obsidianUdp443 =
    'UNCONN 0 0 0.0.0.0:443 0.0.0.0:* users:(("obsidian-server",pid=68904,fd=9))';
const String _obsidianTcp8443 =
    'LISTEN 0 4096 *:8443 *:* users:(("obsidian-server",pid=68904,fd=7))';
const String _xrayUdp443 =
    'UNCONN 0 0 0.0.0.0:443 0.0.0.0:* users:(("xray",pid=4242,fd=3))';

String _hex64(String c) => List.filled(64, c).join();

Future<PortOwner> Function(String) _owners(Map<String, PortOwner> m) {
  return (port) async => m[port] ?? const PortOwner.free();
}

void main() {
  group('ss listing parsing', () {
    test('foreign TCP 443 is reported with its process name', () {
      expect(
        parseSsListing(_nginxTcp443, '443'),
        const PortOwner.foreign('nginx'),
      );
    });

    test('obsidian-server on UDP 443 is ours', () {
      expect(parseSsListing(_obsidianUdp443, '443'), const PortOwner.ours());
    });

    test('another port in the listing is free', () {
      expect(parseSsListing(_nginxTcp443, '8443'), const PortOwner.free());
    });

    test('port match is exact', () {
      expect(parseSsListing(_nginxTcp443, '4430'), const PortOwner.free());
      expect(parseSsListing(_nginxTcp443, '44'), const PortOwner.free());
    });

    test('IPv6 wildcard [::]:443 and the * address both match', () {
      const v6 = 'LISTEN 0 511 [::]:443 [::]:* users:(("nginx",pid=1,fd=6))';
      expect(parseSsListing(v6, '443'), const PortOwner.foreign('nginx'));
      expect(parseSsListing(_obsidianTcp8443, '8443'), const PortOwner.ours());
    });

    test('a process of the VPN container counts as ours', () {
      expect(
        parseSsListing(_xrayUdp443, '443'),
        const PortOwner.foreign('xray'),
      );
      expect(
        parseSsListing(_xrayUdp443, '443', vpnPids: {'4242'}),
        const PortOwner.ours(),
      );
    });

    test('socket without process info is foreign (unknown process)', () {
      const line = 'LISTEN 0 128 0.0.0.0:443 0.0.0.0:*';
      expect(
        parseSsListing(line, '443'),
        const PortOwner.foreign('неизвестный процесс'),
      );
    });

    test('ss output with a Netid column is read from the 5th column', () {
      const withNetid =
          'tcp LISTEN 0 511 0.0.0.0:443 0.0.0.0:* users:(("nginx",pid=1,fd=6))';
      expect(parseSsListing(withNetid, '443'), const PortOwner.foreign('nginx'));
      expect(parseSsListing(withNetid, '511'), const PortOwner.free());
      expect(parseSsListing(withNetid, '0'), const PortOwner.free());
    });

    test('empty listing means free', () {
      expect(parseSsListing('', '443'), const PortOwner.free());
    });

    test('foreign process wins over our own socket on the same port', () {
      final out = '$_obsidianUdp443\n$_xrayUdp443';
      expect(parseSsListing(out, '443'), const PortOwner.foreign('xray'));
    });
  });

  group('port selection', () {
    test('free 443 is picked without logs', () async {
      final logs = <String>[];
      final port = await pickPort(
        proto: 'tcp',
        candidates: kPreferredPorts,
        ownerOf: _owners({}),
        log: logs.add,
      );
      expect(port, '443');
      expect(logs, isEmpty);
    });

    test('busy 443 falls back to 8443 and logs the skip', () async {
      final logs = <String>[];
      final port = await pickPort(
        proto: 'tcp',
        candidates: kPreferredPorts,
        ownerOf: _owners({'443': const PortOwner.foreign('nginx')}),
        log: logs.add,
      );
      expect(port, '8443');
      expect(logs, ['TCP 443 занят (nginx), оставляю порт 8443']);
    });

    test('our own 443 is kept', () async {
      final port = await pickPort(
        proto: 'udp',
        candidates: kPreferredPorts,
        ownerOf: _owners({'443': const PortOwner.ours()}),
      );
      expect(port, '443');
    });

    test('current config port is tried after 443', () async {
      final port = await pickPort(
        proto: 'tcp',
        candidates: ['443', '9443', kAltPort],
        ownerOf: _owners({'443': const PortOwner.foreign('nginx')}),
      );
      expect(port, '9443');
    });

    test('all candidates busy throws a Russian error naming them', () async {
      await expectLater(
        pickPort(
          proto: 'tcp',
          candidates: kPreferredPorts,
          ownerOf: _owners({
            '443': const PortOwner.foreign('nginx'),
            '8443': const PortOwner.foreign('caddy'),
          }),
        ),
        throwsA(
          isA<VpsException>().having(
            (e) => e.messageRu,
            'message',
            allOf(contains('443, 8443'), contains('Освободите')),
          ),
        ),
      );
    });
  });

  group('architecture mapping', () {
    test('uname values map to server binary suffixes', () {
      expect(serverArchFromUname('x86_64\n'), 'amd64');
      expect(serverArchFromUname('aarch64'), 'arm64');
      expect(serverArchFromUname('arm64'), 'arm64');
      expect(serverArchFromUname('amd64'), 'amd64');
    });

    test('unsupported architectures map to null', () {
      expect(serverArchFromUname('armv7l'), isNull);
      expect(serverArchFromUname('i686'), isNull);
      expect(serverArchFromUname(''), isNull);
    });

    test('asset path uses the arch suffix', () {
      expect(
        serverBinaryAsset('arm64'),
        'assets/bin/obsidian-server-linux-arm64',
      );
    });
  });

  group('server config JSON', () {
    final json = buildServerConfigJson(
      sni: 'www.microsoft.com',
      tcpPort: '443',
      udpPort: '8443',
      iface: 'ens3',
      enableIpv6: true,
      serverPrivateKeyHex: _hex64('c'),
      serverPublicKeyHex: _hex64('d'),
      realityAuthKey: _hex64('e'),
    );
    final cfg = jsonDecode(json) as Map<String, dynamic>;

    test('contains every key the core reads', () {
      const required = [
        'port',
        'udp_port',
        'no_tls',
        'reality_target',
        'reality_backend',
        'reality_backend_sni',
        'reality_server_names',
        'reality_auth_key',
        'server_private_key',
        'server_public_key',
        'tun_interface',
        'tun_address',
        'out_interface',
        'dns_upstream',
        'dns_listen',
        'enable_ipv6',
        'enable_udp_data',
        'allowed_clients',
        'revocation_file',
        'junk_count',
        'noise_min_sec',
        'noise_max_sec',
        'keepalive_sec',
        'signatures',
      ];
      for (final key in required) {
        expect(cfg.containsKey(key), isTrue, reason: 'missing $key');
      }
    });

    test('ports are strings, flags are booleans', () {
      expect(cfg['port'], '443');
      expect(cfg['udp_port'], '8443');
      expect(cfg['enable_ipv6'], isTrue);
      expect(cfg['no_tls'], isFalse);
      expect(cfg['allowed_clients'], isEmpty);
    });

    test('REALITY target follows the SNI', () {
      expect(cfg['reality_target'], 'www.microsoft.com:443');
      expect(cfg['reality_backend'], 'www.microsoft.com:443');
      expect(cfg['reality_backend_sni'], 'www.microsoft.com');
      expect(cfg['reality_server_names'], ['www.microsoft.com']);
    });

    test('tunnel layout matches the desktop installer', () {
      expect(cfg['tun_address'], '10.8.0.1/24');
      expect(cfg['dns_listen'], '10.8.0.1:53');
      expect(cfg['out_interface'], 'ens3');
      expect(cfg['revocation_file'], '/opt/obsidian/revoked_clients.json');
    });
  });

  group('NAT steps', () {
    test('IPv4 only: no ip6tables commands', () {
      final steps = natSteps(
        iface: 'eth0',
        tcpPort: '443',
        udpPort: '443',
        ipv6: false,
      );
      expect(steps.any((s) => s.cmd.contains('ip6tables')), isFalse);
    });

    test('IPv6 on: fd00:8::/64 masquerade and MSS 1340', () {
      final steps = natSteps(
        iface: 'eth0',
        tcpPort: '443',
        udpPort: '443',
        ipv6: true,
      );
      final text = steps.map((s) => s.cmd).join('\n');
      expect(text, contains('ip6tables -t nat -C POSTROUTING -s fd00:8::/64'));
      expect(text, contains('--set-mss 1340'));
      expect(text, contains('--set-mss 1380'));
    });

    test('masquerade and forwarding are required, MSS clamp is not', () {
      final steps = natSteps(
        iface: 'eth0',
        tcpPort: '8443',
        udpPort: '443',
        ipv6: false,
      );
      final masq = steps.firstWhere((s) => s.cmd.contains('MASQUERADE'));
      final mss = steps.firstWhere((s) => s.cmd.contains('TCPMSS'));
      expect(masq.required, isTrue);
      expect(mss.required, isFalse);
      expect(
        steps.any((s) => s.cmd.contains('--dport 8443 -j ACCEPT') && s.required),
        isTrue,
      );
    });

    test('keyserver is reachable only on loopback', () {
      final steps = natSteps(
        iface: 'eth0',
        tcpPort: '443',
        udpPort: '443',
        ipv6: false,
      );
      expect(
        steps.any((s) => s.cmd.contains('--dport 8444 ! -i lo -j DROP')),
        isTrue,
      );
    });

    test('legacy ports keep the ones in use', () {
      final steps = closeLegacyPortsSteps([('tcp', '443'), ('udp', '443')]);
      expect(steps.any((s) => s.cmd.contains('ufw delete allow 443/')), isFalse);
      expect(
        steps.any((s) => s.cmd.contains('ufw delete allow 8443/tcp')),
        isTrue,
      );
    });
  });

  group('SNI normalization', () {
    test('trims, lowercases and drops :443', () {
      expect(normalizeSni('  WWW.Microsoft.com:443 '), 'www.microsoft.com');
    });

    test('empty input gives the default mask', () {
      expect(normalizeSni(null), kDefaultSni);
      expect(normalizeSni('   '), kDefaultSni);
    });

    test('values that could break out of the server script are rejected', () {
      expect(() => normalizeSni('a"b.com'), throwsA(isA<VpsException>()));
      expect(() => normalizeSni('x; rm -rf /'), throwsA(isA<VpsException>()));
    });
  });

  group('version comparison', () {
    test('parses loosely: v prefix, short forms and pre-release suffix', () {
      expect(parseVersion('1.1.1'), (major: 1, minor: 1, patch: 1));
      expect(parseVersion('v1.2'), (major: 1, minor: 2, patch: 0));
      expect(parseVersion('0.1.0-beta.2'), (major: 0, minor: 1, patch: 0));
      expect(parseVersion('ранняя сборка'), isNull);
    });

    test('numeric comparison, not string comparison', () {
      expect(
        compareVersions(parseVersion('1.10.0')!, parseVersion('1.9.9')!),
        greaterThan(0),
      );
    });

    test('same binary is never outdated', () {
      expect(
        coreNeedsUpdate(
          remoteVersion: '0.1.0',
          remoteHash: 'abc',
          localHash: 'abc',
          bundledVersion: '1.1.1',
        ),
        isFalse,
      );
    });

    test('older server version is outdated', () {
      expect(
        coreNeedsUpdate(
          remoteVersion: '0.1.0',
          remoteHash: 'abc',
          localHash: 'def',
          bundledVersion: '1.1.1',
        ),
        isTrue,
      );
    });

    test('equal version is outdated only when the hash differs', () {
      expect(
        coreNeedsUpdate(
          remoteVersion: '1.1.1',
          remoteHash: 'abc',
          localHash: 'def',
          bundledVersion: '1.1.1',
        ),
        isTrue,
      );
      expect(
        coreNeedsUpdate(
          remoteVersion: '1.1.1',
          remoteHash: '',
          localHash: 'def',
          bundledVersion: '1.1.1',
        ),
        isFalse,
      );
    });

    test('newer server is never downgraded', () {
      expect(
        coreNeedsUpdate(
          remoteVersion: '99.0.0',
          remoteHash: 'abc',
          localHash: 'def',
          bundledVersion: '1.1.1',
        ),
        isFalse,
      );
    });

    test('unknown version depends on the hash alone', () {
      expect(
        coreNeedsUpdate(
          remoteVersion: null,
          remoteHash: 'abc',
          localHash: 'def',
          bundledVersion: '1.1.1',
        ),
        isTrue,
      );
      expect(
        coreNeedsUpdate(
          remoteVersion: null,
          remoteHash: '',
          localHash: 'def',
          bundledVersion: '1.1.1',
        ),
        isFalse,
      );
    });

    test('version.txt parsing reads version and hash, MISSING is flagged', () {
      final file = parseVersionFile('1.1.1\nabc123\n');
      expect(file.missing, isFalse);
      expect(file.version, '1.1.1');
      expect(file.hash, 'abc123');
      expect(parseVersionFile('MISSING').missing, isTrue);
    });
  });

  group('remote script builders', () {
    test('update script writes both ports and migrates REALITY when asked', () {
      final script = updateConfigScript(
        const UpdatePlan(
          tcp: '443',
          udp: '8443',
          migrateReality: true,
          sni: 'www.apple.com',
          enableIpv6: false,
        ),
      );
      expect(script, contains('cfg["port"] = "443"'));
      expect(script, contains('cfg["udp_port"] = "8443"'));
      expect(script, contains('cfg["enable_ipv6"] = False'));
      expect(script, contains('if True:'));
      expect(script, contains('"www.apple.com"'));
      expect(script, contains("python3 - <<'PY'"));
    });

    test('update script keeps REALITY when migration is off', () {
      final script = updateConfigScript(
        const UpdatePlan(
          tcp: '8443',
          udp: '8443',
          migrateReality: false,
          sni: 'www.microsoft.com',
          enableIpv6: true,
        ),
      );
      expect(script, contains('if False:'));
      expect(script, contains('cfg["enable_ipv6"] = True'));
    });

    test('IPv6 script toggles only enable_ipv6 and prints the ports', () {
      final on = setIpv6Script(true);
      final off = setIpv6Script(false);
      expect(on, contains('cfg["enable_ipv6"] = True'));
      expect(off, contains('cfg["enable_ipv6"] = False'));
      expect(on, contains('print("TCP="'));
      expect(on, contains('print("UDP="'));
    });

    test('reset script prints RESET_OK and blanks the key files', () {
      final script = resetScript(
        serverPrivateKeyHex: _hex64('1'),
        serverPublicKeyHex: _hex64('2'),
        realityAuthKey: _hex64('3'),
      );
      expect(script, contains('print("RESET_OK")'));
      expect(script, contains('f.write("{}\\n")'));
    });

    test('Docker run for keyserver carries the admin token', () {
      final cmd = keyserverDockerRunCmd('tok123');
      expect(cmd, contains('-e ADMIN_TOKEN=tok123'));
      expect(cmd, contains('-e KEYSERVER_BIND=127.0.0.1'));
    });

    test('SNI change script prints SNI_OK after writing', () {
      expect(changeSniScript('www.google.com'), contains('print("SNI_OK")'));
    });
  });

  group('small parsers', () {
    test('docker top pids skip the header', () {
      expect(
        parseDockerTopPids('PID\n4242\n\n4243\n'),
        ['4242', '4243'],
      );
    });

    test('IPv6 probe output', () {
      expect(parseIpv6Probe('IPV6_OK'), isTrue);
      expect(parseIpv6Probe('IPV6_NONE'), isFalse);
    });

    test('KEY=value lines from server scripts', () {
      final kv = parseKeyValues('AUTH=abc\nSNI=www.x.com\nREALITY=1\nnoise');
      expect(kv, {'AUTH': 'abc', 'SNI': 'www.x.com', 'REALITY': '1'});
    });

    test('default route interface is validated', () {
      expect(interfaceFromRoute('eth0\n'), 'eth0');
      expect(interfaceFromRoute('eth0; rm -rf /'), isNull);
      expect(interfaceFromRoute(''), isNull);
    });

    test('keyserver URL brackets IPv6 hosts', () {
      expect(keyserverUrl('203.0.113.5'), 'http://203.0.113.5:8444');
      expect(keyserverUrl('2001:db8::1'), 'http://[2001:db8::1]:8444');
    });
  });

  group('VPS models', () {
    test('credentials round trip through JSON', () {
      const creds = VpsCredentials(
        host: '203.0.113.5',
        port: 2222,
        user: 'admin',
        password: 'p@ss',
        hostKeyFingerprint: 'SHA256:abc',
      );
      final back = VpsCredentials.fromJson(creds.toJson());
      expect(back.host, '203.0.113.5');
      expect(back.port, 2222);
      expect(back.user, 'admin');
      expect(back.password, 'p@ss');
      expect(back.hostKeyFingerprint, 'SHA256:abc');
      expect(back.usesKey, isFalse);
    });

    test('defaults are port 22 and root', () {
      const creds = VpsCredentials(host: 'h');
      expect(creds.port, 22);
      expect(creds.user, 'root');
    });

    test('toString never reveals secrets', () {
      const creds = VpsCredentials(host: 'h', password: 'secret-pass');
      expect(creds.toString(), isNot(contains('secret-pass')));
    });

    test('an empty PEM means password auth', () {
      const creds = VpsCredentials(host: 'h', privateKeyPem: '   ');
      expect(creds.usesKey, isFalse);
    });
  });

  group('shell quoting', () {
    test('single quotes are closed, escaped and reopened', () {
      expect(shellQuote('/opt/obsidian'), "'/opt/obsidian'");
      expect(shellQuote("a'b"), r"'a'\''b'");
      expect(shellQuote("'; rm -rf / #"), r"''\''; rm -rf / #'");
    });

    test('exec upload keeps the temp file private and quotes every path', () {
      final cmd = streamUploadCommand('/tmp/x', "/opt/o'b/f");
      expect(cmd, startsWith('umask 077;'));
      expect(cmd, contains(r"'/opt/o'\''b/f'"));
    });
  });
}
