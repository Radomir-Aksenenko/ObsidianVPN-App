import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/vps/deploy_scripts.dart';
import 'package:obsidian_vpn/vps/deployer.dart';
import 'package:obsidian_vpn/vps/ssh_session.dart';
import 'package:obsidian_vpn/vps/vps_models.dart';

class _Upload {
  _Upload(this.path, this.data, this.mode);

  final String path;
  final Uint8List data;
  final int? mode;
}

/// In-memory server: answers the commands of a deploy and records everything.
class _FakeSession implements SshSession {
  _FakeSession({
    this.installed = false,
    this.dirExists = false,
    this.uid = '0',
    this.vpnRuns = true,
  });

  bool installed;
  bool dirExists;
  String uid;
  bool vpnRuns;

  final List<String> commands = <String>[];
  final List<_Upload> uploads = <_Upload>[];
  final Completer<void> closed = Completer<void>();

  /// Completes once a command containing this text has been seen.
  final Map<String, Completer<void>> _waiters = <String, Completer<void>>{};

  Future<void> sawCommand(String needle) =>
      (_waiters[needle] ??= Completer<void>()).future;

  @override
  String get hostKeyFingerprint => 'SHA256:fake-host-key';

  @override
  Future<CmdResult> run(String cmd, {Duration timeout = const Duration(seconds: 60)}) async {
    commands.add(cmd);
    for (final entry in _waiters.entries) {
      if (cmd.contains(entry.key) && !entry.value.isCompleted) entry.value.complete();
    }
    return CmdResult(stdout: _answer(cmd), stderr: '', exitCode: 0);
  }

  String _answer(String cmd) {
    if (cmd == kUidCmd) return uid;
    if (cmd == kUnameCmd) return 'x86_64';
    if (cmd == kInstallExistsCmd) return installed ? 'OK' : 'MISSING';
    if (cmd == kServerDirExistsCmd) return dirExists ? 'EXISTS' : 'NO';
    if (cmd == kDockerVersionCmd) return 'Docker version 26.1.0';
    if (cmd.contains('echo DOCKER_OK')) return 'DOCKER_OK';
    if (cmd.contains('IPV6_OK')) return 'IPV6_NONE';
    if (cmd == kIfaceCmd) return 'eth0';
    if (cmd.startsWith('docker inspect')) {
      final isKeyserver = cmd.contains(kKeyserverContainer);
      return (isKeyserver || vpnRuns) ? 'true' : 'false';
    }
    return '';
  }

  @override
  Future<void> upload(Uint8List data, String remotePath, {int? mode}) async {
    uploads.add(_Upload(remotePath, data, mode));
  }

  @override
  void close() {
    if (!closed.isCompleted) closed.complete();
  }
}

class _Assets implements AssetSource {
  @override
  Future<Uint8List> load(String path) async =>
      Uint8List.fromList(utf8.encode('asset:$path'));
}

VpsDeployer _deployer(
  _FakeSession session, {
  Future<void> Function(Duration)? delay,
}) {
  return VpsDeployer(
    assets: _Assets(),
    random: Random(7),
    openSession: (creds, {log}) async => session,
    delay: delay ?? (_) async {},
  );
}

const VpsCredentials _creds = VpsCredentials(host: '203.0.113.10', password: 'pw');

Future<(List<DeployEvent>, Object?)> _run(Stream<DeployEvent> stream) async {
  final events = <DeployEvent>[];
  Object? error;
  final done = Completer<void>();
  stream.listen(
    events.add,
    onError: (Object e) => error = e,
    onDone: done.complete,
  );
  await done.future;
  return (events, error);
}

bool _removesInstallDir(_FakeSession s) =>
    s.commands.any((c) => c.contains('rm -rf $kServerDir'));

void main() {
  test('a fresh deploy finishes with a decodable owner key and never deletes anything', () async {
    final session = _FakeSession();
    final (events, error) = await _run(
      _deployer(session).deploy(const DeployRequest(creds: _creds)),
    );
    expect(error, isNull);
    final done = events.whereType<DeployFinished<DeployResult>>().single.value;
    expect(done.ownerKey, startsWith('OBSDN-'));
    expect(done.ownerConfig.serverHost, '203.0.113.10');
    expect(done.tcpPort, 443);
    expect(done.hostKeyFingerprint, 'SHA256:fake-host-key');
    expect(_removesInstallDir(session), isFalse);
    expect(session.commands.any((c) => c.contains('rm -f $kServerBin')), isFalse);
    expect(session.closed.isCompleted, isTrue);

    final config = session.uploads.firstWhere((u) => u.path == kServerConfig);
    expect(config.mode, 0x180, reason: 'config holds the private key: 0600');
    final json = jsonDecode(utf8.decode(config.data)) as Map<String, dynamic>;
    expect(json['reality_backend_sni'], kDefaultSni);
    expect(json['allowed_clients'], isEmpty);
  });

  test('secrets never reach the log', () async {
    final session = _FakeSession();
    final (events, _) = await _run(
      _deployer(session).deploy(const DeployRequest(creds: _creds)),
    );
    final done = events.whereType<DeployFinished<DeployResult>>().single.value;
    final config = session.uploads.firstWhere((u) => u.path == kServerConfig);
    final json = jsonDecode(utf8.decode(config.data)) as Map<String, dynamic>;
    final logs = events.whereType<DeployLog>().map((e) => e.line).join('\n');
    expect(logs, isNot(contains(done.adminToken)));
    expect(logs, isNot(contains(json['server_private_key'] as String)));
    expect(logs, isNot(contains(json['reality_auth_key'] as String)));
    expect(logs, isNot(contains(done.ownerKey)));
    expect(logs, isNot(contains('pw')));
  });

  test('an existing installation is never overwritten or removed', () async {
    final session = _FakeSession(installed: true, dirExists: true);
    final (events, error) = await _run(
      _deployer(session).deploy(const DeployRequest(creds: _creds)),
    );
    expect(error, isA<VpsException>());
    expect((error! as VpsException).messageRu, contains('уже установлен'));
    expect(events.whereType<DeployFinished<Object?>>(), isEmpty);
    expect(session.uploads, isEmpty);
    expect(session.commands.any((c) => c.startsWith('docker run')), isFalse);
    expect(session.commands.any((c) => c.contains('rm ')), isFalse);
    expect(session.closed.isCompleted, isTrue);
  });

  test('a failed start removes the directory this deploy created', () async {
    final session = _FakeSession(vpnRuns: false);
    final (_, error) = await _run(
      _deployer(session).deploy(const DeployRequest(creds: _creds)),
    );
    expect(error, isA<VpsException>());
    expect(_removesInstallDir(session), isTrue);
  });

  test('a failed start leaves a directory that was already there', () async {
    final session = _FakeSession(vpnRuns: false, dirExists: true);
    final (_, error) = await _run(
      _deployer(session).deploy(const DeployRequest(creds: _creds)),
    );
    expect(error, isA<VpsException>());
    expect(_removesInstallDir(session), isFalse);
    expect(
      session.commands.any((c) => c == rollbackFilesCmd(dirExisted: true)),
      isTrue,
    );
  });

  test('rollback for a pre-existing directory removes only the deploy files', () {
    final cmd = rollbackFilesCmd(dirExisted: true);
    expect(cmd, isNot(contains('rm -rf')));
    for (final f in kDeployFiles) {
      expect(cmd, contains(f));
    }
    expect(rollbackFilesCmd(dirExisted: false), 'rm -rf $kServerDir 2>/dev/null || true');
  });

  test('a non-root user is refused before anything is changed', () async {
    final session = _FakeSession(uid: '1000');
    final (_, error) = await _run(
      _deployer(session).deploy(const DeployRequest(creds: _creds)),
    );
    expect(error, isA<VpsException>());
    expect(session.uploads, isEmpty);
    expect(session.commands.any((c) => c.contains('apt-get')), isFalse);
  });

  test('an invalid SNI is rejected before connecting', () async {
    final session = _FakeSession();
    final (_, error) = await _run(
      _deployer(session).deploy(
        const DeployRequest(creds: _creds, sni: "x.com'; rm -rf /; '"),
      ),
    );
    expect(error, isA<VpsException>());
    expect(session.commands, isEmpty);
  });

  test('cancelling mid-deploy stops further steps and undoes the install', () async {
    final session = _FakeSession();
    final gate = Completer<void>();
    final events = <DeployEvent>[];
    final sub = _deployer(session, delay: (_) => gate.future)
        .deploy(const DeployRequest(creds: _creds))
        .listen(events.add, onError: (_) {});
    // The deploy waits at its pause after `docker run` of the VPN container.
    await session.sawCommand('docker run -d --name $kVpnContainer');
    await sub.cancel();
    gate.complete();
    await session.closed.future.timeout(const Duration(seconds: 5));

    expect(session.uploads.any((u) => u.path == kKeyserverScript), isFalse);
    expect(session.commands.any((c) => c.contains(kKeyserverContainer) && c.startsWith('docker run')), isFalse);
    expect(_removesInstallDir(session), isTrue);
    expect(events.whereType<DeployFinished<Object?>>(), isEmpty);
  });
}
