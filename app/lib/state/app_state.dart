import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueListenable, kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:obsidian_vpn/core/codec/client_config.dart';
import 'package:obsidian_vpn/core/codec/obsidian_key.dart';
import 'package:obsidian_vpn/core/models/profile.dart';
import 'package:obsidian_vpn/core/models/split_tunnel.dart';
import 'package:obsidian_vpn/core/net/ping.dart';
import 'package:obsidian_vpn/core/storage/store.dart';
import 'package:obsidian_vpn/platform_info.dart' as platform;
import 'package:obsidian_vpn/vps/key_issuer.dart';
import 'package:obsidian_vpn/vps/owner_key.dart';
import 'package:obsidian_vpn/vps/vps_models.dart';
import 'package:obsidian_vpn/vpn/channel_backend.dart';
import 'package:obsidian_vpn/vpn/desktop_backend.dart';
import 'package:obsidian_vpn/vpn/elevation.dart' as elevation;
import 'package:obsidian_vpn/vpn/vpn_backend.dart';
import 'package:path_provider/path_provider.dart';

/// Number of log lines kept in memory. Older lines are dropped.
const int kAppLogCapacity = 500;

/// Thrown by [AppState] for user-facing failures. [messageRu] is Russian text
/// that can be shown as is.
class AppStateException implements Exception {
  /// Creates an exception with a Russian [messageRu].
  const AppStateException(this.messageRu);

  /// Russian message for the user.
  final String messageRu;

  @override
  String toString() => messageRu;
}

/// Optional backend capability: enforce the kill switch natively.
///
/// [AppState.connect] calls [setKillSwitch] before connecting, but only when
/// the backend implements this interface. [ChannelVpnBackend] implements it and
/// sends the flag as `killSwitch` with `connect`; the desktop backend does not.
abstract interface class KillSwitchCapable {
  /// Turns the kill switch on or off for the next connection.
  Future<void> setKillSwitch(bool enabled);
}

/// Operating-system calls used by [AppState]. [AppPlatformHooks.system] wires
/// the real implementations. Tests pass fakes.
final class AppPlatformHooks {
  /// Creates hooks from explicit values.
  const AppPlatformHooks({
    required this.isDesktop,
    required this.isWindows,
    required this.isElevated,
    required this.relaunchElevated,
    required this.setAutostart,
  });

  /// Real hooks for the running OS.
  factory AppPlatformHooks.system() {
    return AppPlatformHooks(
      isDesktop: platform.isDesktop,
      isWindows: Platform.isWindows,
      isElevated: elevation.isElevated,
      relaunchElevated: (args) => elevation.relaunchElevatedWindows(args: args),
      setAutostart: elevation.setAutostart,
    );
  }

  /// True on Windows, macOS and Linux. Autostart is only applied there.
  final bool isDesktop;

  /// True on Windows. Only Windows relaunches elevated.
  final bool isWindows;

  /// Returns true when the process has administrator rights.
  final Future<bool> Function() isElevated;

  /// Restarts the app elevated with [args]. Throws [ElevationDenied] when refused.
  final Future<void> Function(List<String> args) relaunchElevated;

  /// Enables or disables autostart at logon.
  final Future<void> Function(bool enabled) setAutostart;
}

/// The single state object the UI reads and calls.
///
/// Create it with [AppState.create] (real storage) or the constructor (tests),
/// then call [init] once. Access it from widgets with [AppState.of].
///
/// Failures of VPN operations do not throw: they set [vpnStatus] to an error
/// phase with a Russian message in [VpnStatus.error]. Input and lookup errors
/// (unknown profile, empty name) throw [AppStateException] or
/// [KeyFormatException].
class AppState extends ChangeNotifier {
  /// Creates the state around an opened [store].
  ///
  /// [backend] defaults to ChannelVpnBackend on Android and iOS, and to
  /// DesktopVpnBackend elsewhere. [observeLifecycle] attaches the app lifecycle
  /// listener in [init]; set it to false in tests without a widgets binding.
  AppState({
    required AppStore store,
    VpnBackend? backend,
    AppPlatformHooks? platform,
    List<String> launchArgs = const <String>[],
    Duration pingInterval = const Duration(seconds: 30),
    Duration pingTimeout = kPingTimeout,
    bool observeLifecycle = true,
    // The named parameters keep their public names, so the fields are set here.
    // ignore: prefer_initializing_formals
  }) : _store = store,
       _backend = backend ?? _defaultBackend(),
       _platform = platform ?? AppPlatformHooks.system(),
       _launchArgs = List<String>.unmodifiable(launchArgs),
       // ignore: prefer_initializing_formals
       _pingInterval = pingInterval,
       // ignore: prefer_initializing_formals
       _pingTimeout = pingTimeout,
       // ignore: prefer_initializing_formals
       _observeLifecycle = observeLifecycle;

  /// Opens the real store in the app support directory and returns an
  /// unstarted state. On Windows the old app data in `%APPDATA%\ObsidianVPN`
  /// is imported on the first run. Call [init] next.
  ///
  /// [launchArgs] are the process arguments; `--connect` and `--autostart` are
  /// recognised by [init].
  static Future<AppState> create({
    List<String> launchArgs = const <String>[],
  }) async {
    final support = await getApplicationSupportDirectory();
    final store = await AppStore.open(
      dir: support.path,
      secrets: SecureSecretStore(),
      legacyDir: _legacyWindowsDir(),
    );
    return AppState(store: store, launchArgs: launchArgs);
  }

  /// Returns the state provided by the nearest [AppScope]. Asserts when none exists.
  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope?.notifier != null, 'AppState: no AppScope above this context');
    return scope!.notifier!;
  }

  final AppStore _store;
  final VpnBackend _backend;
  final AppPlatformHooks _platform;
  final List<String> _launchArgs;
  final Duration _pingInterval;
  final Duration _pingTimeout;
  final bool _observeLifecycle;

  final List<String> _logLines = <String>[];

  /// Log lines are published to [_logsNotifier] at most once per
  /// [_logPublishInterval]: the first line of a quiet period goes out at once, and a
  /// burst is coalesced into one trailing publish. Logs never call notifyListeners.
  static const Duration _logPublishInterval = Duration(milliseconds: 250);
  final ValueNotifier<List<String>> _logsNotifier =
      ValueNotifier<List<String>>(const <String>[]);
  Timer? _logPublishTimer;
  DateTime? _lastLogPublish;

  /// Mutations (addKey, removeProfile, ...) run one at a time through this chain,
  /// so two calls cannot both pass a duplicate check before either one saves.
  Future<void> _mutationChain = Future<void>.value();

  final Map<String, int?> _pings = <String, int?>{};
  VpnStatus _status = const VpnStatus();
  TrafficStats? _stats;
  String? _activeProfileId;

  /// Profile of the last connect request. Survives the short disconnected phase
  /// of a live split reapply, so the connected profile is not mixed up with the
  /// selected one. Cleared by an explicit disconnect.
  String? _tunnelProfileId;
  Future<void>? _pendingConnect;
  bool _initialized = false;
  bool _disposed = false;
  StreamSubscription<VpnStatus>? _statusSub;
  StreamSubscription<TrafficStats>? _statsSub;
  StreamSubscription<String>? _logSub;
  AppLifecycleListener? _lifecycle;
  Timer? _pingTimer;

  /// All profiles in insertion order. Read-only.
  List<ServerProfile> get profiles => _store.profiles;

  /// The profile chosen in settings, or the first profile when none is chosen
  /// or the chosen one was removed. Null when there are no profiles.
  ServerProfile? get selectedProfile {
    final id = _store.settings.lastProfileId;
    final list = _store.profiles;
    if (id != null) {
      for (final profile in list) {
        if (profile.id == id) return profile;
      }
    }
    return list.isEmpty ? null : list.first;
  }

  /// The profile the tunnel is currently running for, or null.
  ServerProfile? get connectedProfile {
    final id = _activeProfileId;
    return id == null ? null : profileById(id);
  }

  /// Issued keys in insertion order. Read-only.
  List<IssuedKey> get issuedKeys => _store.issuedKeys;

  /// Current settings.
  AppSettings get settings => _store.settings;

  /// Latest VPN status from the backend.
  VpnStatus get vpnStatus => _status;

  /// True when the phase is [VpnPhase.connected].
  bool get isConnected => _status.phase == VpnPhase.connected;

  /// True while connecting, reconnecting or disconnecting. The UI should show progress.
  bool get isBusy {
    final phase = _status.phase;
    return phase == VpnPhase.connecting ||
        phase == VpnPhase.reconnecting ||
        phase == VpnPhase.disconnecting;
  }

  /// Latest traffic sample. Null when disconnected or when stats are not active.
  TrafficStats? get stats => _stats;

  /// Last [kAppLogCapacity] log lines, oldest first. Read-only view. It is not
  /// reactive: listen to [logsListenable] to rebuild on new lines.
  UnmodifiableListView<String> get logs => UnmodifiableListView(_logLines);

  /// Snapshot of the log lines, updated at most once per 250 ms during bursts. Each
  /// value is an unmodifiable copy, oldest first. Log UIs listen to this instead of
  /// the whole state.
  ValueListenable<List<String>> get logsListenable => _logsNotifier;

  /// Removes all log lines. The log keeps filling from new events.
  void clearLogs() {
    if (_logLines.isEmpty) return;
    _logLines.clear();
    _publishLogs();
  }

  /// Last TCP ping per profile id, in milliseconds. A null value means the
  /// server did not answer. A missing key means no measurement yet. Read-only view.
  UnmodifiableMapView<String, int?> get pings => UnmodifiableMapView(_pings);

  /// Stable id of this installation.
  String get deviceId => _store.deviceId;

  /// True after [init] has run.
  bool get initialized => _initialized;

  /// Returns the profile with [id], or null.
  ServerProfile? profileById(String id) {
    for (final profile in _store.profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  /// Starts the state. Idempotent.
  ///
  /// Subscribes to the backend streams, attaches the lifecycle listener (when
  /// enabled), and connects when [AppSettings.autoConnect] is on or the
  /// process was started with `--connect`. Failures never throw.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    for (final notice in _store.notices) {
      _log(notice);
    }
    _statusSub = _backend.status.listen(_onStatus, onError: _onStreamError);
    _statsSub = _backend.stats.listen(_onStats, onError: _onStreamError);
    _logSub = _backend.logs.listen(_log, onError: _onStreamError);
    if (_observeLifecycle) _attachLifecycle();
    if (_launchArgs.contains('--autostart')) _log('Запуск из автозапуска');
    final shouldConnect =
        settings.autoConnect || _launchArgs.contains('--connect');
    if (shouldConnect && _store.profiles.isNotEmpty) {
      unawaited(connect().catchError((Object _) {}));
    }
    _notify();
  }

  /// Parses [input] (obsidian://, vpn://, or OBSDN- key) and saves a profile.
  ///
  /// The profile is deduplicated by host, port and server public key: if one
  /// exists, it is returned unchanged. When this is the first profile, it is
  /// selected. Throws [KeyFormatException] for invalid input.
  Future<ServerProfile> addKey(String input, {String? name}) =>
      _serialMutation(() => _addKeyNow(input, name: name));

  Future<ServerProfile> _addKeyNow(String input, {String? name}) async {
    final config = parseKey(input);
    final host = config.serverHost;
    final port = int.tryParse(config.serverPort) ?? int.parse(kDefaultPort);
    final publicKey = config.serverPublicKey.toLowerCase();
    final existing = _findDuplicate(host, port, publicKey);
    if (existing != null) return existing;

    final id = generateUuidV4();
    final trimmedName = name?.trim() ?? '';
    final label = config.label.trim();
    final displayName = trimmedName.isNotEmpty
        ? trimmedName
        : (label.isNotEmpty ? label : host);
    final wasEmpty = _store.profiles.isEmpty;
    await _store.secrets.write(
      SecretKeys.profile(id, SecretKeys.rawKey),
      input.trim(),
    );
    final profile = ServerProfile(
      id: id,
      name: displayName,
      countryCode: guessCountryCode(displayName),
      host: host,
      port: port,
      serverPublicKey: publicKey,
      source: ProfileSource.key,
      createdAt: DateTime.now().toUtc(),
      split: SplitTunnelConfig(),
    );
    await _store.putProfile(profile);
    if (wasEmpty) await _selectFirst(id);
    _log('Добавлен сервер: $displayName');
    if (_pingTimer != null) unawaited(_pingOne(profile));
    _notify();
    return profile;
  }

  /// Removes a profile and its secrets. Disconnects first when it is the active tunnel.
  Future<void> removeProfile(String id) =>
      _serialMutation(() => _removeProfileNow(id));

  Future<void> _removeProfileNow(String id) async {
    if (profileById(id) == null) return;
    if (_activeProfileId == id || _tunnelProfileId == id) await disconnect();
    await _store.removeProfile(id);
    _pings.remove(id);
    if (settings.lastProfileId == id) {
      final list = _store.profiles;
      final next = list.isEmpty ? null : list.first.id;
      await _store.setSettings(
        settings.copyWith(
          lastProfileId: next,
          clearLastProfileId: next == null,
        ),
      );
    }
    _log('Сервер удалён');
    _notify();
  }

  /// Renames a profile. Throws [AppStateException] when [name] is empty.
  Future<void> renameProfile(String id, String name) =>
      _serialMutation(() => _renameProfileNow(id, name));

  Future<void> _renameProfileNow(String id, String name) async {
    final profile = _requireProfile(id);
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const AppStateException('Введите название сервера.');
    }
    await _store.putProfile(profile.copyWith(name: trimmed));
    _notify();
  }

  /// Flips [ServerProfile.isFavorite] of a profile.
  Future<void> toggleFavorite(String id) async {
    final profile = _requireProfile(id);
    await _store.putProfile(profile.copyWith(isFavorite: !profile.isFavorite));
    _notify();
  }

  /// Makes a profile the selected one. Does not change the tunnel.
  Future<void> selectProfile(String id) async {
    _requireProfile(id);
    await _store.setSettings(settings.copyWith(lastProfileId: id));
    _notify();
  }

  /// Replaces the split tunnel rules of a profile.
  ///
  /// When the profile is connected, the new rules are applied to the running
  /// tunnel with [VpnBackend.applySplit]. Throws [AppStateException] when that fails.
  Future<void> setSplit(String profileId, SplitTunnelConfig split) =>
      _serialMutation(() => _setSplitNow(profileId, split));

  Future<void> _setSplitNow(String profileId, SplitTunnelConfig split) async {
    final updated = _requireProfile(profileId).copyWith(split: split);
    await _store.putProfile(updated);
    if (_activeProfileId == profileId && isConnected) {
      _tunnelProfileId = profileId;
      try {
        await _backend.applySplit(await _buildConfigJson(updated));
      } on Object catch (_) {
        _log('Не удалось применить раздельное туннелирование');
        throw const AppStateException(
          'Не удалось применить правила раздельного туннелирования.',
        );
      }
    }
    _notify();
  }

  /// Saves settings. [AppSettings.lastProfileId] is owned by [selectProfile],
  /// so a null value keeps the current selection.
  ///
  /// On desktop, a change of [AppSettings.autostart] is applied to the OS first.
  /// If that fails, nothing is saved and [AppStateException] is thrown.
  Future<void> updateSettings(AppSettings next) async {
    final current = settings;
    final merged = next.lastProfileId == null
        ? next.copyWith(lastProfileId: current.lastProfileId)
        : next;
    if (merged.autostart != current.autostart && _platform.isDesktop) {
      try {
        await _platform.setAutostart(merged.autostart);
      } on Object catch (_) {
        _log('Не удалось изменить автозапуск');
        throw const AppStateException(
          'Не удалось изменить автозапуск. Проверьте права и повторите.',
        );
      }
    }
    await _store.setSettings(merged);
    _notify();
  }

  /// Starts the tunnel for the selected profile.
  ///
  /// Builds the runtime config: runtime defaults, a tunnel address derived from
  /// device and profile ids, the client keypair (created on first use and
  /// stored in the secret store), and the split tunnel fields. On Windows, when
  /// not elevated, the app relaunches elevated with `--connect`. A refused UAC
  /// prompt becomes [VpnStatus.error].
  ///
  /// Throws [AppStateException] when there is no profile. Other failures set
  /// [vpnStatus] to an error. A second call while a connect is in progress
  /// returns the same operation.
  Future<void> connect() {
    return _pendingConnect ??= _runConnect().whenComplete(() {
      _pendingConnect = null;
    });
  }

  /// Stops the tunnel. Failures set [vpnStatus] to an error.
  Future<void> disconnect() async {
    _tunnelProfileId = null;
    final pending = _pendingConnect;
    if (pending != null &&
        (_status.phase == VpnPhase.disconnected ||
            _status.phase == VpnPhase.error)) {
      // A connect is still preparing (UAC prompt, keypair, config) and the
      // backend has not reported progress yet. Let it finish, then stop it.
      try {
        await pending;
      } on Object catch (_) {}
      _tunnelProfileId = null;
    }
    if (_status.phase == VpnPhase.disconnected) return;
    _log('Отключение');
    try {
      await _backend.disconnect();
    } on VpnBackendException catch (e) {
      _onStatus(VpnStatus(phase: VpnPhase.error, error: e.message));
    } on Object catch (_) {
      _onStatus(
        const VpnStatus(
          phase: VpnPhase.error,
          error: 'Не удалось отключить VPN.',
        ),
      );
    }
  }

  /// Connects when disconnected or in error, and disconnects otherwise.
  /// Does nothing while the phase is [VpnPhase.disconnecting].
  Future<void> toggle() {
    final phase = _status.phase;
    if (phase == VpnPhase.disconnecting) return Future<void>.value();
    if (phase == VpnPhase.disconnected || phase == VpnPhase.error) {
      return connect();
    }
    return disconnect();
  }

  /// Creates or updates the VPS profile for a deployment result.
  ///
  /// The VPS profile is matched by SSH host and port first, then by the owner
  /// key (host, port, public key). Secrets are written: the owner key, the
  /// keyserver admin token, and the SSH password, key and passphrase. A null
  /// secret in [creds] removes the stored one. Returns the saved profile.
  Future<ServerProfile> saveVpsProfile(
    DeployResult result,
    VpsCredentials creds, {
    String? hostKey,
  }) => _serialMutation(() => _saveVpsProfileNow(result, creds, hostKey: hostKey));

  Future<ServerProfile> _saveVpsProfileNow(
    DeployResult result,
    VpsCredentials creds, {
    String? hostKey,
  }) async {
    final owner = result.ownerConfig;
    final host = owner.serverHost;
    final port = int.tryParse(owner.serverPort) ?? int.parse(kDefaultPort);
    final publicKey = owner.serverPublicKey.toLowerCase();
    final existing =
        _findVps(creds.host, creds.port) ??
        _findDuplicate(host, port, publicKey);
    final id = existing?.id ?? generateUuidV4();
    final name = existing?.name ?? creds.host;

    final secrets = _store.secrets;
    await secrets.write(
      SecretKeys.profile(id, SecretKeys.rawKey),
      result.ownerKey,
    );
    await secrets.write(
      SecretKeys.profile(id, SecretKeys.adminToken),
      result.adminToken,
    );
    await _writeOrDelete(id, SecretKeys.vpsPassword, creds.password);
    await _writeOrDelete(id, SecretKeys.vpsPrivateKeyPem, creds.privateKeyPem);
    await _writeOrDelete(id, SecretKeys.vpsPassphrase, creds.passphrase);

    final wasEmpty = _store.profiles.isEmpty;
    final profile = ServerProfile(
      id: id,
      name: name,
      countryCode: existing?.countryCode ?? guessCountryCode(name),
      host: host,
      port: port,
      serverPublicKey: publicKey,
      source: ProfileSource.vps,
      createdAt: existing?.createdAt ?? DateTime.now().toUtc(),
      split: existing?.split ?? SplitTunnelConfig(),
      isFavorite: existing?.isFavorite ?? false,
      vps: VpsCredentials(host: creds.host, port: creds.port, user: creds.user),
      vpsHostKey: hostKey ?? result.hostKeyFingerprint,
      serverVersion: result.serverVersion,
    );
    await _store.putProfile(profile);
    if (wasEmpty) await _selectFirst(id);
    _log('Сервер VPS сохранён: ${creds.host}');
    _notify();
    return profile;
  }

  /// Returns the SSH credentials of a VPS profile with secrets loaded, or null
  /// when the profile is not a VPS profile.
  Future<VpsCredentials?> vpsCredentials(String profileId) async {
    final profile = profileById(profileId);
    final vps = profile?.vps;
    if (profile == null || vps == null) return null;
    final secrets = _store.secrets;
    final password = await secrets.read(
      SecretKeys.profile(profileId, SecretKeys.vpsPassword),
    );
    final pem = await secrets.read(
      SecretKeys.profile(profileId, SecretKeys.vpsPrivateKeyPem),
    );
    final passphrase = await secrets.read(
      SecretKeys.profile(profileId, SecretKeys.vpsPassphrase),
    );
    return VpsCredentials(
      host: vps.host,
      port: vps.port,
      user: vps.user,
      password: _nonEmptyOrNull(password),
      privateKeyPem: _nonEmptyOrNull(pem),
      passphrase: _nonEmptyOrNull(passphrase),
      hostKeyFingerprint: profile.vpsHostKey,
    );
  }

  /// Returns the keyserver admin token of a VPS profile, or null.
  Future<String?> adminToken(String profileId) async {
    final value = await _store.secrets.read(
      SecretKeys.profile(profileId, SecretKeys.adminToken),
    );
    return _nonEmptyOrNull(value);
  }

  /// Saves an issued key. Replaces the key with the same id.
  Future<void> addIssuedKey(IssuedKey key) async {
    await _store.putIssued(key);
    _log('Выдан ключ: ${key.name}');
    _notify();
  }

  /// Removes an issued key and its secrets.
  Future<void> removeIssuedKey(String id) async {
    await _store.removeIssued(id);
    _notify();
  }

  /// Saves the outcome of a server reset: the new owner key, and every key issued from
  /// this server is removed, because the reset cut off its old keys. Returns how many
  /// issued keys were removed.
  Future<int> applyVpsReset(
    String profileId,
    ResetResult result, {
    String? hostKey,
  }) async {
    await updateVpsProfile(
      profileId,
      hostKey: hostKey,
      ownerKey: result.ownerKey,
      ownerConfig: result.ownerConfig,
    );
    final stale = [
      for (final key in _store.issuedKeys)
        if (key.serverId == profileId) key.id,
    ];
    for (final id in stale) {
      await _store.removeIssued(id);
    }
    if (stale.isNotEmpty) _notify();
    _log('Сервер обнулён, ключей удалено: ${stale.length}');
    return stale.length;
  }

  /// Saves the outcome of an in-place core update. When the TCP port changed, the owner
  /// key is rebuilt on the new ports. Keys issued earlier keep the old port and must be
  /// issued again. Returns true when the port changed.
  Future<bool> applyVpsUpdate(
    String profileId,
    UpdateResult result, {
    required String serverVersion,
    String? hostKey,
  }) async {
    final current = profileById(profileId);
    if (current == null || current.vps == null) {
      throw const AppStateException('Профиль VPS не найден.');
    }
    final portChanged = current.port != result.tcpPort;
    String? rebuiltKey;
    ClientConfig? rebuiltConfig;
    if (portChanged) {
      final stored = await ownerKey(profileId);
      if (stored == null) {
        throw const AppStateException(
          'Порт изменился, но владельческий ключ не найден на этом устройстве. '
          'Переустанови сервер.',
        );
      }
      final rebuilt = rebuildOwnerKey(
        parseKey(stored),
        port: '${result.tcpPort}',
        udpPort: '${result.udpPort}',
      );
      rebuiltKey = rebuilt.key;
      rebuiltConfig = rebuilt.config;
    }
    await updateVpsProfile(
      profileId,
      hostKey: hostKey,
      serverVersion: serverVersion,
      needsUpdate: false,
      ownerKey: rebuiltKey,
      ownerConfig: rebuiltConfig,
    );
    if (portChanged) {
      _log(
        'Порт сервера изменился на ${result.tcpPort}, ключ владельца пересобран',
      );
    }
    return portChanged;
  }

  /// Returns the owner key (OBSDN) of a VPS profile, or null.
  Future<String?> ownerKey(String profileId) async {
    final value = await _store.secrets.read(
      SecretKeys.profile(profileId, SecretKeys.rawKey),
    );
    return _nonEmptyOrNull(value);
  }

  /// Updates a VPS profile after a manage operation. Null arguments keep the current value.
  ///
  /// [creds] replaces the SSH host, port and user, and rewrites the SSH secrets (a null
  /// secret removes the stored one). [ownerKey] with [ownerConfig] replaces the owner key
  /// (after SNI, IPv6 or reset changes). [adminToken] replaces the keyserver token.
  /// [hostKey] pins a new SSH host key fingerprint. Returns the saved profile.
  Future<ServerProfile> updateVpsProfile(
    String profileId, {
    VpsCredentials? creds,
    String? hostKey,
    String? serverVersion,
    bool? needsUpdate,
    String? ownerKey,
    ClientConfig? ownerConfig,
    String? adminToken,
  }) => _serialMutation(
    () => _updateVpsProfileNow(
      profileId,
      creds: creds,
      hostKey: hostKey,
      serverVersion: serverVersion,
      needsUpdate: needsUpdate,
      ownerKey: ownerKey,
      ownerConfig: ownerConfig,
      adminToken: adminToken,
    ),
  );

  Future<ServerProfile> _updateVpsProfileNow(
    String profileId, {
    VpsCredentials? creds,
    String? hostKey,
    String? serverVersion,
    bool? needsUpdate,
    String? ownerKey,
    ClientConfig? ownerConfig,
    String? adminToken,
  }) async {
    final current = profileById(profileId);
    if (current == null || current.vps == null) {
      throw const AppStateException('Профиль VPS не найден.');
    }
    final secrets = _store.secrets;
    if (creds != null) {
      await _writeOrDelete(profileId, SecretKeys.vpsPassword, creds.password);
      await _writeOrDelete(
        profileId,
        SecretKeys.vpsPrivateKeyPem,
        creds.privateKeyPem,
      );
      await _writeOrDelete(
        profileId,
        SecretKeys.vpsPassphrase,
        creds.passphrase,
      );
    }
    if (ownerKey != null) {
      await secrets.write(
        SecretKeys.profile(profileId, SecretKeys.rawKey),
        ownerKey,
      );
    }
    if (adminToken != null) {
      await secrets.write(
        SecretKeys.profile(profileId, SecretKeys.adminToken),
        adminToken,
      );
    }
    final owner = ownerConfig;
    final profile = ServerProfile(
      id: current.id,
      name: current.name,
      countryCode: current.countryCode,
      host: owner == null || owner.serverHost.isEmpty
          ? current.host
          : owner.serverHost,
      port: owner == null
          ? current.port
          : (int.tryParse(owner.serverPort) ?? current.port),
      serverPublicKey: owner == null
          ? current.serverPublicKey
          : owner.serverPublicKey.toLowerCase(),
      source: current.source,
      createdAt: current.createdAt,
      split: current.split,
      isFavorite: current.isFavorite,
      vps: creds == null
          ? current.vps
          : VpsCredentials(
              host: creds.host,
              port: creds.port,
              user: creds.user,
            ),
      vpsHostKey: hostKey ?? current.vpsHostKey,
      serverVersion: serverVersion ?? current.serverVersion,
      needsUpdate: needsUpdate ?? current.needsUpdate,
    );
    await _store.putProfile(profile);
    _notify();
    return profile;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pingTimer?.cancel();
    _pingTimer = null;
    _logPublishTimer?.cancel();
    _logPublishTimer = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    unawaited(_statusSub?.cancel());
    unawaited(_statsSub?.cancel());
    unawaited(_logSub?.cancel());
    unawaited(_backend.dispose());
    _logsNotifier.dispose();
    super.dispose();
  }

  Future<void> _runConnect() async {
    final profile = selectedProfile;
    if (profile == null) {
      throw const AppStateException('Сначала добавьте сервер.');
    }
    if (_status.phase == VpnPhase.connected && _activeProfileId == profile.id) {
      return;
    }
    _activeProfileId = profile.id;
    _tunnelProfileId = profile.id;
    _log('Подключение: ${profile.name}');
    _notify();
    try {
      if (_platform.isWindows && !await _platform.isElevated()) {
        // The elevated copy starts with --connect and takes over.
        await _platform.relaunchElevated(const <String>['--connect']);
        _activeProfileId = null;
        return;
      }
      if (!await _backend.ensurePermission()) {
        throw const AppStateException(
          'VPN не разрешён в системе. Разрешите доступ и повторите.',
        );
      }
      final configJson = await _buildConfigJson(profile);
      if (_backend case KillSwitchCapable killSwitch) {
        await killSwitch.setKillSwitch(settings.killSwitch);
      }
      await _backend.connect(
        profileId: profile.id,
        name: profile.name,
        serverHost: profile.host,
        configJson: configJson,
      );
    } on elevation.ElevationDenied catch (e) {
      _failConnect(e.message);
    } on VpnBackendException catch (e) {
      _failConnect(e.message);
    } on AppStateException catch (e) {
      _failConnect(e.messageRu);
    } on KeyFormatException catch (e) {
      _failConnect(e.messageRu);
    } on Object catch (_) {
      _failConnect('Не удалось подключиться к VPN.');
    }
  }

  void _failConnect(String message) {
    _onStatus(VpnStatus(phase: VpnPhase.error, error: message));
    _log(message);
  }

  /// Builds the JSON for the backend: the ClientConfig fields, the client
  /// keypair, and the split tunnel fields (`split_tunnel_mode`, `split_sites`
  /// with the effective entries, `split_presets`).
  Future<String> _buildConfigJson(ServerProfile profile) async {
    final rawKey = await _store.secrets.read(
      SecretKeys.profile(profile.id, SecretKeys.rawKey),
    );
    if (rawKey == null || rawKey.trim().isEmpty) {
      throw const AppStateException(
        'Ключ сервера не найден. Добавьте сервер заново.',
      );
    }
    final base = parseKey(rawKey);
    final keypair = await _clientKeypair(profile.id, base);
    final runtime = buildRuntimeConfig(
      base,
      profileId: '$deviceId/${profile.id}',
      clientPrivateKeyHex: keypair.$1,
      clientPublicKeyHex: keypair.$2,
    );
    final json = runtime.toJson()
      ..addAll(profile.split.toJson())
      ..['split_sites'] = profile.split.effectiveEntries();
    return jsonEncode(json);
  }

  /// A client key embedded in the server key (`c` / `client_key`) wins, like in the
  /// old desktop app: the server may have registered its public half. Otherwise the
  /// stored keypair is used, created on first use.
  Future<(String, String)> _clientKeypair(
    String profileId,
    ClientConfig base,
  ) async {
    final embedded = base.clientPrivateKey.trim().toLowerCase();
    if (embedded.isNotEmpty) {
      final publicKey = await clientPublicKeyFor(embedded);
      if (publicKey != null) return (embedded, publicKey);
    }
    return _loadOrCreateKeypair(profileId);
  }

  Future<(String, String)> _loadOrCreateKeypair(String profileId) async {
    final secrets = _store.secrets;
    final privateKey = await secrets.read(
      SecretKeys.profile(profileId, SecretKeys.clientPrivateKey),
    );
    final publicKey = await secrets.read(
      SecretKeys.profile(profileId, SecretKeys.clientPublicKey),
    );
    if (privateKey != null &&
        privateKey.isNotEmpty &&
        publicKey != null &&
        publicKey.isNotEmpty) {
      return (privateKey, publicKey);
    }
    final (newPrivate, newPublic) = await generateClientKeypair();
    await secrets.write(
      SecretKeys.profile(profileId, SecretKeys.clientPrivateKey),
      newPrivate,
    );
    await secrets.write(
      SecretKeys.profile(profileId, SecretKeys.clientPublicKey),
      newPublic,
    );
    return (newPrivate, newPublic);
  }

  Future<void> _writeOrDelete(String id, String field, String? value) async {
    final key = SecretKeys.profile(id, field);
    if (value == null || value.isEmpty) {
      await _store.secrets.delete(key);
    } else {
      await _store.secrets.write(key, value);
    }
  }

  Future<void> _selectFirst(String id) async {
    await _store.setSettings(settings.copyWith(lastProfileId: id));
  }

  Future<void> _pingOne(ServerProfile profile) async {
    final ms = await tcpPing(profile.host, profile.port, timeout: _pingTimeout);
    if (_disposed || profileById(profile.id) == null) return;
    _pings[profile.id] = ms;
    _notify();
  }

  void _pingAll() {
    for (final profile in _store.profiles) {
      unawaited(_pingOne(profile));
    }
  }

  void _attachLifecycle() {
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycleState);
    _onLifecycleState(
      WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
    );
  }

  void _onLifecycleState(AppLifecycleState state) {
    // `inactive` is a window that lost focus (desktop) or a system dialog on top
    // (mobile): it is still on screen, so stats and pings keep running. Only
    // hidden, paused and detached count as background and stop the timers.
    final active =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    _backend.statsActive = active;
    if (active == (_pingTimer != null)) return;
    _pingTimer?.cancel();
    _pingTimer = null;
    if (active) {
      _pingTimer = Timer.periodic(_pingInterval, (_) => _pingAll());
      _pingAll();
    }
  }

  void _onStatus(VpnStatus next) {
    final changed = next != _status;
    _status = next;
    switch (next.phase) {
      case VpnPhase.disconnected:
      case VpnPhase.error:
        _activeProfileId = null;
        _stats = null;
      case VpnPhase.connecting:
      case VpnPhase.connected:
      case VpnPhase.reconnecting:
        _activeProfileId ??= _tunnelProfileId ?? selectedProfile?.id;
      case VpnPhase.disconnecting:
        break;
    }
    // VpnStatus has value equality: an unchanged status does not rebuild the app.
    if (changed) _notify();
  }

  void _onStats(TrafficStats next) {
    _stats = next;
    _notify();
  }

  void _onStreamError(Object error, [StackTrace? stackTrace]) {
    _log('Ошибка канала VPN');
  }

  /// Adds a log line. Does not notify listeners: log views listen to [logsListenable].
  void _log(String line) {
    _logLines.add(line);
    if (_logLines.length > kAppLogCapacity) {
      _logLines.removeRange(0, _logLines.length - kAppLogCapacity);
    }
    _scheduleLogPublish();
  }

  void _scheduleLogPublish() {
    if (_disposed || _logPublishTimer != null) return;
    final last = _lastLogPublish;
    final wait = last == null
        ? Duration.zero
        : _logPublishInterval - DateTime.now().difference(last);
    if (wait <= Duration.zero) {
      _publishLogs();
      return;
    }
    _logPublishTimer = Timer(wait, _publishLogs);
  }

  void _publishLogs() {
    _logPublishTimer?.cancel();
    _logPublishTimer = null;
    _lastLogPublish = DateTime.now();
    if (_disposed) return;
    _logsNotifier.value = List<String>.unmodifiable(_logLines);
  }

  /// Runs [action] after every mutation queued before it. A failing action does not
  /// block the queue: its error goes to the caller only.
  Future<T> _serialMutation<T>(Future<T> Function() action) {
    final next = _mutationChain.then((_) => action());
    _mutationChain = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  ServerProfile _requireProfile(String id) {
    final profile = profileById(id);
    if (profile == null) throw const AppStateException('Сервер не найден.');
    return profile;
  }

  ServerProfile? _findDuplicate(String host, int port, String publicKey) {
    final target = host.toLowerCase();
    for (final profile in _store.profiles) {
      if (profile.host.toLowerCase() == target &&
          profile.port == port &&
          profile.serverPublicKey == publicKey) {
        return profile;
      }
    }
    return null;
  }

  ServerProfile? _findVps(String host, int port) {
    for (final profile in _store.profiles) {
      final vps = profile.vps;
      if (profile.source == ProfileSource.vps &&
          vps != null &&
          vps.host == host &&
          vps.port == port) {
        return profile;
      }
    }
    return null;
  }
}

/// Makes an [AppState] available below it. Dependents rebuild when the state
/// notifies. Read it with [AppState.of].
class AppScope extends InheritedNotifier<AppState> {
  /// Wraps [child] and provides [state].
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);
}

String? _legacyWindowsDir() {
  if (!Platform.isWindows) return null;
  final appData = Platform.environment['APPDATA'];
  if (appData == null || appData.isEmpty) return null;
  return '$appData${Platform.pathSeparator}ObsidianVPN';
}

VpnBackend _defaultBackend() {
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    return ChannelVpnBackend();
  }
  return DesktopVpnBackend();
}

String? _nonEmptyOrNull(String? value) =>
    value == null || value.isEmpty ? null : value;
