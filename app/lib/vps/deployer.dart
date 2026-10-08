import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:obsidian_vpn/core/codec/client_config.dart';
import 'package:obsidian_vpn/core/codec/obsidian_key.dart';
import 'package:obsidian_vpn/vps/deploy_scripts.dart';
import 'package:obsidian_vpn/vps/key_issuer.dart';
import 'package:obsidian_vpn/vps/ssh_session.dart';
import 'package:obsidian_vpn/vps/vps_models.dart';

/// Core version of the bundle (desktop/src-tauri/Cargo.toml). Bump with the core build.
const String kBundledServerVersion = '1.1.1';

/// Reads bundled files. The default reads Flutter assets; tests inject a fake.
abstract interface class AssetSource {
  Future<Uint8List> load(String path);
}

/// [AssetSource] backed by rootBundle.
class BundleAssetSource implements AssetSource {
  const BundleAssetSource();

  @override
  Future<Uint8List> load(String path) async {
    final data = await rootBundle.load(path);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}

/// Called with the SHA256 fingerprint when a server is contacted for the first
/// time (its credentials have no pinned fingerprint). The caller stores it.
typedef HostKeyObserver = void Function(String fingerprint);

/// Opens an SSH session. Tests replace it; the default is [SshSession.connect].
typedef SessionOpener = Future<SshSession> Function(
  VpsCredentials creds, {
  SshLog? log,
});

/// Manages the VPS core: deploy, update, version check, SNI change, IPv6 switch and reset.
///
/// API: every operation returns a `Stream<DeployEvent>`. It emits [DeployProgress]
/// and [DeployLog] events, then exactly one [DeployFinished] with the result. On
/// failure the stream emits a [VpsException] error and closes. Use
/// `stream.resultOf<T>()` to await only the result.
///
/// Operations run only after the stream is listened to. The SSH session is
/// closed when the stream ends.
class VpsDeployer {
  VpsDeployer({
    AssetSource? assets,
    this.onNewHostKey,
    Random? random,
    this.bundledVersion = kBundledServerVersion,
    SessionOpener? openSession,
  })  : _assets = assets ?? const BundleAssetSource(),
        _random = random ?? Random.secure(),
        _open = openSession ?? SshSession.connect;

  final AssetSource _assets;
  final Random _random;
  final SessionOpener _open;

  /// Called for a server that has no pinned host key yet.
  final HostKeyObserver? onNewHostKey;

  /// Version of the bundled core, written to version.txt on deploy and update.
  final String bundledVersion;

  /// Installs the core, keyserver, NAT and owner key on a fresh VPS.
  Stream<DeployEvent> deploy(DeployRequest request) =>
      _operation((op) => _deploy(op, request));

  /// Replaces the binary and keyserver, rewrites the config and restarts. Keys stay.
  /// REALITY is migrated to port 443 only when TCP moves there. Rolls back on failure.
  Stream<DeployEvent> update(VpsCredentials creds) =>
      _operation((op) => _update(op, creds));

  /// Compares the server's version.txt (or binary hash) with the bundled core.
  Stream<DeployEvent> checkVersion(VpsCredentials creds) =>
      _operation((op) => _checkVersion(op, creds));

  /// Points REALITY at [sni]. Yields the normalized SNI. Rebuild the owner key after this.
  Stream<DeployEvent> changeSni(VpsCredentials creds, String sni) =>
      _operation((op) => _changeSni(op, creds, sni));

  /// Sets enable_ipv6 in the server config and restarts the core. Yields the new flag.
  /// Clients get the flag from a key, so reissue keys after changing it.
  Stream<DeployEvent> setIpv6(VpsCredentials creds, bool enabled) =>
      _operation((op) => _setIpv6(op, creds, enabled));

  /// New server keys, empty allowed-clients and revocation lists. Yields a fresh owner key.
  Stream<DeployEvent> reset(VpsCredentials creds) =>
      _operation((op) => _reset(op, creds));

  // -------------------------------------------------------------------------
  // Operation runner

  Stream<DeployEvent> _operation(Future<void> Function(_Op op) body) {
    final controller = StreamController<DeployEvent>();
    controller.onListen = () {
      final op = _Op(controller);
      unawaited(_drive(op, body));
    };
    return controller.stream;
  }

  Future<void> _drive(_Op op, Future<void> Function(_Op op) body) async {
    try {
      await body(op);
    } on VpsException catch (e) {
      op.fail(e);
    } catch (e) {
      op.fail(VpsException('Ошибка операции: $e'));
    } finally {
      op.close();
      await op.end();
    }
  }

  // -------------------------------------------------------------------------
  // Operations

  Future<void> _deploy(_Op op, DeployRequest req) async {
    final sni = normalizeSni(req.sni);
    final creds = req.creds;
    final session = await _connect(op, creds);
    final arch = await _detectArch(op);
    final serverBin = await _loadServerBinary(arch);
    final keyserver = await _loadKeyserver();
    if (keyserver == null) {
      throw VpsException('В приложении нет $kKeyserverAsset.');
    }
    op.progress(12, 'Проверка сервера');

    op.progress(20, 'Установка Docker');
    final docker = await op.run(kDockerVersionCmd, check: false);
    if (docker.contains('MISSING')) {
      for (final cmd in kDockerInstallCmds) {
        await op.run(cmd, timeout: const Duration(minutes: 15));
      }
    }

    op.progress(28, 'Настройка сети');
    await op.run(kIpForwardCmd);
    await op.run(kIpForwardPersistCmd);
    final ipv6 = await _probeIpv6(op);

    op.progress(36, 'Выбор портов');
    final pids = await _vpnPids(op);
    final tcp = await _pickPort(op, 'tcp', kPreferredPorts, pids);
    final udp = await _pickPort(op, 'udp', kPreferredPorts, pids);

    op.progress(48, 'Генерация ключей и загрузка ядра');
    final (privHex, pubHex) = await generateClientKeypair();
    final realityAuth = _randomHex(32);
    final adminToken = _randomHex(24);
    await op.upload(serverBin, kServerBin, mode: 0x1ed);
    final binHash = await _sha256Hex(serverBin);
    try {
      await op.upload(
        utf8.encode(versionFileContent(bundledVersion, binHash)),
        kVersionFile,
      );
    } catch (e) {
      op.log('version.txt не записан: $e');
    }
    op.log('REALITY: маска $sni:443, TCP $tcp, UDP $udp');

    final iface = await _iface(op);
    final config = buildServerConfigJson(
      sni: sni,
      tcpPort: tcp,
      udpPort: udp,
      iface: iface,
      enableIpv6: ipv6,
      serverPrivateKeyHex: privHex,
      serverPublicKeyHex: pubHex,
      realityAuthKey: realityAuth,
    );
    op.progress(62, 'Запуск VPN-ядра');
    await op.upload(utf8.encode(config), kServerConfig);
    await op.run(removeContainerCmd(kVpnContainer), check: false);
    await op.run(vpnDockerRunCmd());
    await _pause(2);
    if (!await _isRunning(op, kVpnContainer)) {
      final logs = await op.run(dockerLogsCmd(kVpnContainer, 120), check: false);
      await _rollback(op);
      throw VpsException('Контейнер VPN не запустился.\n$logs');
    }

    op.progress(78, 'Запуск сервера ключей');
    await op.upload(keyserver, kKeyserverScript);
    await op.run(removeContainerCmd(kKeyserverContainer), check: false);
    await op.run(keyserverDockerRunCmd(adminToken), secret: true);
    await _pause(2);
    if (!await _isRunning(op, kKeyserverContainer)) {
      op.log('Сервер ключей не запущен: проверьте логи контейнера $kKeyserverContainer.');
    }

    op.progress(90, 'Настройка firewall и NAT');
    await _setupNat(op, iface, tcp, udp, ipv6);

    final owner = _ownerKeyFor(
      _serverConfig(
        host: creds.host.trim(),
        tcp: tcp,
        udp: udp,
        serverPublicKey: pubHex,
        realityAuthKey: realityAuth,
        sni: sni,
        ipv6: ipv6,
      ),
    );
    op.progress(100, 'Готово');
    op.finish(
      DeployResult(
        ownerKey: owner.key,
        ownerConfig: owner.config,
        adminToken: adminToken,
        tcpPort: int.parse(tcp),
        udpPort: int.parse(udp),
        sni: sni,
        ipv6: ipv6,
        serverVersion: bundledVersion,
        hostKeyFingerprint: session.hostKeyFingerprint,
      ),
    );
  }

  Future<void> _update(_Op op, VpsCredentials creds) async {
    await _connect(op, creds);
    final arch = await _detectArch(op);
    final serverBin = await _loadServerBinary(arch);
    final keyserver = await _loadKeyserver();

    op.progress(16, 'Проверка установки');
    final exists = await op.run(kInstallExistsCmd, check: false);
    if (!exists.contains('OK')) {
      throw const VpsException(
        'На этом хосте нет установки Obsidian. Сначала разверните сервер.',
      );
    }
    final cfg = _decodeConfig(await op.run(kReadConfigCmd, quiet: true));
    final curTcp = jsonPortOf(cfg, 'port') ?? '443';
    final curUdp = jsonPortOf(cfg, 'udp_port') ?? curTcp;
    final currentSni = cfg['reality_backend_sni'];

    await op.run(kPython3Cmd, timeout: const Duration(minutes: 15));
    final ipv6 = await _probeIpv6(op);
    final pids = await _vpnPids(op);
    final tcp = await _pickPort(op, 'tcp', ['443', curTcp, kAltPort], pids);
    final udp = await _pickPort(op, 'udp', ['443', curUdp, kAltPort], pids);
    final plan = UpdatePlan(
      tcp: tcp,
      udp: udp,
      migrateReality: tcp == '443',
      sni: currentSni is String && currentSni.isNotEmpty ? currentSni : kDefaultSni,
      enableIpv6: ipv6,
    );
    op.log(
      plan.migrateReality
          ? 'порты: TCP $tcp, UDP $udp, REALITY на порту 443, маска ${plan.sni}'
          : 'порты: TCP $tcp, UDP $udp, настройки REALITY не меняются',
    );

    op.progress(30, 'Резервные копии');
    await op.run(kBackupCmd);

    UpdateResult result;
    try {
      result = await _applyUpdate(op, serverBin, keyserver, plan);
    } catch (_) {
      op.log('Обновление не удалось, восстанавливаю предыдущее ядро и конфиг.');
      await op.run(kRestoreCmd, check: false);
      rethrow;
    }
    op.progress(100, 'Готово');
    op.finish(result);
  }

  Future<UpdateResult> _applyUpdate(
    _Op op,
    Uint8List serverBin,
    Uint8List? keyserver,
    UpdatePlan plan,
  ) async {
    op.progress(35, 'Загрузка нового ядра');
    await op.upload(serverBin, kServerBin, mode: 0x1ed);
    op.progress(55, 'Загрузка сервера ключей');
    if (keyserver != null) {
      await op.upload(keyserver, kKeyserverScript);
    } else {
      op.log('keyserver.py не входит в сборку: файл на сервере не обновлен.');
    }

    op.progress(70, 'Запись конфига');
    final kv = parseKeyValues(
      await op.run(updateConfigScript(plan), quiet: true),
    );

    op.progress(78, 'Перезапуск VPN-ядра');
    final iface = await _iface(op);
    await _closeLegacyPorts(op, plan.tcp, plan.udp);
    await _setupNat(op, iface, plan.tcp, plan.udp, plan.enableIpv6);
    await op.run(restartContainerCmd(kVpnContainer));
    if (await _isRunning(op, kKeyserverContainer)) {
      await op.run(restartContainerCmd(kKeyserverContainer), check: false);
    }
    await _pause(2);
    if (!await _isRunning(op, kVpnContainer)) {
      final logs = await op.run(dockerLogsCmd(kVpnContainer, 80), check: false);
      throw VpsException('Контейнер VPN не запустился после обновления.\n$logs');
    }

    // The version is recorded only after the unit is running.
    final binHash = await _sha256Hex(serverBin);
    try {
      await op.upload(
        utf8.encode(versionFileContent(bundledVersion, binHash)),
        kVersionFile,
      );
    } catch (e) {
      op.log('version.txt не записан: $e');
    }

    final logs = await op.run(dockerLogsCmd(kVpnContainer, 20), check: false, quiet: true);
    if (logs.trim().isNotEmpty) {
      op.log('Логи VPN-ядра:');
      for (final line in logs.split('\n').take(12)) {
        op.log(line);
      }
    }

    return UpdateResult(
      tcpPort: int.parse(plan.tcp),
      udpPort: int.parse(plan.udp),
      realityEnabled: kv['REALITY'] == '1',
      realityAuthKey: kv['AUTH'] ?? '',
      sni: kv['SNI'] ?? '',
      ipv6: plan.enableIpv6,
    );
  }

  Future<void> _checkVersion(_Op op, VpsCredentials creds) async {
    await _connect(op, creds);
    final arch = await _detectArch(op);
    final localBin = await _loadServerBinary(arch);
    final localHash = await _sha256Hex(localBin);

    op.progress(40, 'Сравнение версий');
    final file = parseVersionFile(
      await op.run(kReadVersionFileCmd, check: false),
    );
    var remoteHash = file.hash;
    if (file.missing) {
      final exists = await op.run(kBinExistsCmd, check: false);
      if (!exists.contains('EXISTS')) {
        throw const VpsException('Сервер Obsidian VPN не обнаружен на данном хосте.');
      }
      remoteHash = (await op.run(kSha256BinCmd, check: false)).trim();
    }

    final sameBinary = remoteHash.isNotEmpty && remoteHash == localHash;
    final needsUpdate = coreNeedsUpdate(
      remoteVersion: file.version,
      remoteHash: remoteHash,
      localHash: localHash,
      bundledVersion: bundledVersion,
    );
    final version = file.version ??
        (sameBinary ? bundledVersion : 'ранняя сборка');
    op.log(
      needsUpdate
          ? 'Доступно обновление ядра до $bundledVersion (сейчас на сервере: $version).'
          : 'Установлена актуальная версия ядра $version.',
    );
    op.progress(100, 'Готово');
    op.finish(
      VpsStatus(installed: true, upToDate: !needsUpdate, version: version),
    );
  }

  Future<void> _changeSni(_Op op, VpsCredentials creds, String sni) async {
    final target = normalizeSni(sni);
    await _connect(op, creds);
    op.progress(40, 'Обновление REALITY SNI');
    op.log('Обновление REALITY SNI до $target.');
    await op.run('cp -f $kServerConfig $kServerConfig.bak');
    try {
      final res = await op.run(changeSniScript(target));
      if (!res.contains('SNI_OK')) {
        throw VpsException('Не удалось обновить config.json на сервере: $res');
      }
      op.progress(70, 'Перезапуск VPN-ядра');
      await op.run(restartContainerCmd(kVpnContainer));
      await _pause(1);
      if (!await _isRunning(op, kVpnContainer)) {
        throw const VpsException('Контейнер VPN не перезапустился с новым SNI.');
      }
    } catch (_) {
      await _restoreConfig(op);
      rethrow;
    }
    op.log('SNI обновлен.');
    op.progress(100, 'Готово');
    op.finish<String>(target);
  }

  Future<void> _setIpv6(_Op op, VpsCredentials creds, bool enabled) async {
    await _connect(op, creds);
    final exists = await op.run(kInstallExistsCmd, check: false);
    if (!exists.contains('OK')) {
      throw const VpsException('На этом хосте нет установки Obsidian. Сначала разверните сервер.');
    }
    await op.run(kPython3Cmd, timeout: const Duration(minutes: 15));
    if (enabled) {
      final reachable = await _probeIpv6(op);
      if (!reachable) {
        op.log(
          'На сервере нет внешнего IPv6: клиенты получат IPv6, но выход в IPv6 может не работать.',
        );
      }
    }

    op.progress(50, 'Запись конфига');
    await op.run('cp -f $kServerConfig $kServerConfig.bak');
    final iface = await _iface(op);
    try {
      final kv = parseKeyValues(await op.run(setIpv6Script(enabled), quiet: true));
      final tcp = kv['TCP'] ?? '';
      final udp = kv['UDP'] ?? '';
      if (tcp.isEmpty || udp.isEmpty) {
        throw const VpsException('Не удалось прочитать порты из конфига сервера.');
      }
      op.progress(70, 'Обновление NAT');
      await _setupNat(op, iface, tcp, udp, enabled);
      await op.run(restartContainerCmd(kVpnContainer));
      await _pause(2);
      if (!await _isRunning(op, kVpnContainer)) {
        throw const VpsException('Контейнер VPN не запустился после смены IPv6.');
      }
    } catch (_) {
      await _restoreConfig(op);
      rethrow;
    }
    op.log('IPv6 ${enabled ? 'включен' : 'выключен'}.');
    op.progress(100, 'Готово');
    op.finish<bool>(enabled);
  }

  Future<void> _reset(_Op op, VpsCredentials creds) async {
    await _connect(op, creds);
    final exists = await op.run(kInstallExistsCmd, check: false);
    if (!exists.contains('OK')) {
      throw const VpsException('На этом хосте нет установки Obsidian. Сначала разверните сервер.');
    }
    op.log('Сброс сервера.');
    op.progress(20, 'Генерация новых ключей');
    final (privHex, pubHex) = await generateClientKeypair();
    final realityAuth = _randomHex(32);

    op.progress(45, 'Запись конфига');
    final out = await op.run(
      resetScript(
        serverPrivateKeyHex: privHex,
        serverPublicKeyHex: pubHex,
        realityAuthKey: realityAuth,
      ),
      secret: true,
    );
    if (!out.contains('RESET_OK')) {
      throw VpsException('Не удалось сбросить конфигурацию сервера: $out');
    }
    final kv = parseKeyValues(out);

    op.progress(75, 'Перезапуск сервисов');
    await op.run(restartContainerCmd(kVpnContainer));
    await op.run(restartContainerCmd(kKeyserverContainer), check: false);
    await _pause(2);
    if (!await _isRunning(op, kVpnContainer)) {
      throw const VpsException('Контейнер VPN не запустился после сброса.');
    }

    final owner = _ownerKeyFor(
      _serverConfig(
        host: creds.host.trim(),
        tcp: kv['TCP'] ?? '',
        udp: kv['UDP'] ?? '',
        serverPublicKey: pubHex,
        realityAuthKey: realityAuth,
        sni: kv['SNI'] ?? kDefaultSni,
        ipv6: kv['V6'] == '1',
      ),
    );
    op.log('Сброс сервера завершен.');
    op.progress(100, 'Готово');
    op.finish(
      ResetResult(
        serverPublicKey: pubHex,
        realityAuthKey: realityAuth,
        realitySni: kv['SNI'] ?? '',
        ownerKey: owner.key,
        ownerConfig: owner.config,
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Shared steps

  Future<SshSession> _connect(_Op op, VpsCredentials creds) async {
    op.progress(4, 'Подключение к серверу');
    op.log('SSH: подключение к ${creds.host.trim()}:${creds.port}');
    final session = await _open(creds, log: op.log);
    op.attach(session);
    if ((creds.hostKeyFingerprint ?? '').isEmpty) {
      onNewHostKey?.call(session.hostKeyFingerprint);
    }
    op.log('SSH: вход выполнен, ключ сервера ${session.hostKeyFingerprint}');
    return session;
  }

  Future<String> _detectArch(_Op op) async {
    final out = await op.run(kUnameCmd);
    final arch = serverArchFromUname(out);
    if (arch == null) {
      throw VpsException(
        'Архитектура сервера "${out.trim()}" не поддерживается. Нужна x86_64 или aarch64.',
      );
    }
    op.log('Архитектура сервера: $arch');
    return arch;
  }

  Future<Uint8List> _loadServerBinary(String arch) async {
    final path = serverBinaryAsset(arch);
    try {
      return await _assets.load(path);
    } catch (_) {
      throw VpsException('В приложении нет ядра сервера для архитектуры $arch ($path).');
    }
  }

  Future<Uint8List?> _loadKeyserver() async {
    try {
      return await _assets.load(kKeyserverAsset);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _probeIpv6(_Op op) async {
    op.log('Проверка IPv6 на сервере.');
    final ok = parseIpv6Probe(await op.run(probeIpv6Command(), check: false));
    if (ok) {
      op.log('IPv6 доступен: режим Dual-Stack.');
      await op.run(kIpv6ForwardCmd, check: false);
      await op.run(kIpv6ForwardPersistCmd, check: false);
    } else {
      op.log('Внешнего маршрута IPv6 на сервере нет: режим чистого IPv4.');
    }
    return ok;
  }

  Future<Set<String>> _vpnPids(_Op op) async {
    final out = await op.run(kVpnPidsCmd, check: false, quiet: true);
    return parseDockerTopPids(out).toSet();
  }

  Future<String> _pickPort(
    _Op op,
    String proto,
    List<String> candidates,
    Set<String> vpnPids,
  ) {
    return pickPort(
      proto: proto,
      candidates: candidates,
      log: op.log,
      ownerOf: (port) async {
        final out = await op.run(ssCommand(proto), check: false, quiet: true);
        return parseSsListing(out, port, vpnPids: vpnPids);
      },
    );
  }

  Future<String> _iface(_Op op) async {
    final out = await op.run(kIfaceCmd, check: false, quiet: true);
    return interfaceFromRoute(out) ?? 'eth0';
  }

  Future<bool> _isRunning(_Op op, String container) async {
    return isRunningOutput(await op.run(containerRunningCmd(container), check: false));
  }

  Future<void> _setupNat(
    _Op op,
    String iface,
    String tcp,
    String udp,
    bool ipv6,
  ) async {
    for (final step in natSteps(iface: iface, tcpPort: tcp, udpPort: udp, ipv6: ipv6)) {
      await op.run(step.cmd, check: step.required);
    }
  }

  Future<void> _closeLegacyPorts(_Op op, String tcp, String udp) async {
    for (final step in closeLegacyPortsSteps([('tcp', tcp), ('udp', udp)])) {
      await op.run(step.cmd, check: false);
    }
  }

  Future<void> _rollback(_Op op) async {
    op.log('Откат: удаление контейнеров и каталога $kServerDir.');
    await op.run(removeContainerCmd(kVpnContainer), check: false);
    await op.run(removeContainerCmd(kKeyserverContainer), check: false);
    await op.run('rm -rf $kServerDir 2>/dev/null || true', check: false);
  }

  Future<void> _restoreConfig(_Op op) async {
    op.log('Восстановление предыдущего конфига.');
    await op.run(
      'test -f $kServerConfig.bak && cp -f $kServerConfig.bak $kServerConfig; '
      'docker restart $kVpnContainer >/dev/null 2>&1; true',
      check: false,
    );
  }

  String _randomHex(int bytes) =>
      hexEncode(List<int>.generate(bytes, (_) => _random.nextInt(256)));

  Future<String> _sha256Hex(Uint8List bytes) async {
    final hash = await Sha256().hash(bytes);
    return hexEncode(hash.bytes);
  }

  ClientConfig _serverConfig({
    required String host,
    required String tcp,
    required String udp,
    required String serverPublicKey,
    required String realityAuthKey,
    required String sni,
    required bool ipv6,
  }) {
    return ClientConfig(
      protocolVersion: 2,
      serverHost: host,
      serverPort: tcp,
      udpPort: udp,
      serverPublicKey: serverPublicKey,
      noTls: false,
      realityEnabled: true,
      realityAuthKey: realityAuthKey,
      realitySni: sni,
      enableUdpData: true,
      mtu: kSafeMtu,
      enableIpv6: ipv6,
      dns: '10.8.0.1',
      junkCount: 7,
      noiseMinSec: 10,
      noiseMaxSec: 40,
      keepaliveSec: 20,
      profile: 'fast-secure',
      jitter: 'off',
      keyserver: keyserverUrl(host),
    );
  }

  /// Owner key: 3 devices, no expiry. The config is decoded back from the key,
  /// so it matches what clients will read.
  ({String key, ClientConfig config}) _ownerKeyFor(ClientConfig server) {
    final issued = issueKey(
      serverConfig: server,
      name: 'Owner',
      days: 0,
      devices: 3,
      random: _random,
    );
    return (key: issued.key, config: parseKey(issued.key));
  }
}

/// Per-operation state: the event sink and the open SSH session.
class _Op {
  _Op(this._controller);

  final StreamController<DeployEvent> _controller;
  SshSession? _session;

  void attach(SshSession session) => _session = session;

  SshSession get _ssh {
    final s = _session;
    if (s == null) throw StateError('SSH-сессия не открыта.');
    return s;
  }

  void progress(int percent, String stepRu) => _emit(
        DeployProgress(percent < 0 ? 0 : (percent > 100 ? 100 : percent), stepRu),
      );

  void log(String line) => _emit(DeployLog(line));

  void finish<T>(T value) => _emit(DeployFinished<T>(value));

  void fail(VpsException error) {
    if (!_controller.isClosed) _controller.addError(error);
  }

  Future<void> end() async {
    if (!_controller.isClosed) await _controller.close();
  }

  void close() => _session?.close();

  void _emit(DeployEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  /// Runs a remote command. [quiet] hides the command and its output from the
  /// log. [secret] also hides the command text in errors. Use it for commands
  /// that contain keys or tokens.
  Future<String> run(
    String cmd, {
    bool check = true,
    bool quiet = false,
    bool secret = false,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final firstLine = cmd.split('\n').first;
    final shown = secret
        ? '[скрыто]'
        : (cmd.contains('\n') ? '$firstLine ...' : cmd);
    if (!quiet) log('\$ $shown');
    final r = await _ssh.run(cmd, timeout: timeout);
    if (!quiet && !secret) {
      for (final line in r.stdout.split('\n')) {
        if (line.trim().isNotEmpty) log(line);
      }
      if (r.stderr.isNotEmpty) log('[stderr] ${r.stderr}');
    }
    if (check && !r.ok) {
      final detail = r.stderr.isEmpty ? '' : '\n${r.stderr}';
      throw VpsException(
        'Команда на сервере завершилась с ошибкой (код ${r.exitCode}): $shown$detail',
      );
    }
    return r.stdout;
  }

  Future<void> upload(List<int> data, String path, {int? mode}) async {
    final name = path.split('/').last;
    final mb = (data.length / 1024 / 1024).toStringAsFixed(1);
    log('upload $name ($mb МБ)');
    final bytes = data is Uint8List ? data : Uint8List.fromList(data);
    await _ssh.upload(bytes, path, mode: mode);
  }
}

Map<String, dynamic> _decodeConfig(String text) {
  try {
    final value = jsonDecode(text);
    if (value is Map<String, dynamic>) return value;
  } catch (_) {
    // Reported below without the raw text, which may hold keys.
  }
  throw const VpsException('Не удалось прочитать конфиг сервера.');
}

Future<void> _pause(int seconds) =>
    Future<void>.delayed(Duration(seconds: seconds));
