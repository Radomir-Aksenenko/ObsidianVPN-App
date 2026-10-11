import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/models/profile.dart';
import '../core/update/update_checker.dart';

/// Delay before the first automatic check after the app starts.
const Duration kFirstUpdateCheckDelay = Duration(seconds: 8);

/// Time between automatic checks, counted from the first one.
const Duration kUpdateCheckInterval = Duration(hours: 6);

/// Update state of the desktop app: the newest release known to be newer,
/// whether a check is running, and the one-time startup prompt.
///
/// Created by the shell on desktop only. [settings] is read at each check, so
/// a change of `checkUpdates` or `skippedUpdateVersion` applies at once.
final class UpdateController extends ChangeNotifier {
  /// Creates a controller. The timers are not started until [start].
  UpdateController({
    required this.checker,
    required this.readSettings,
    this.firstCheckDelay = kFirstUpdateCheckDelay,
    this.interval = kUpdateCheckInterval,
  });

  /// Fetches and compares the latest release.
  final UpdateChecker checker;

  /// Returns the current settings. Called at each check.
  final AppSettings Function() readSettings;

  /// Delay before the first automatic check.
  final Duration firstCheckDelay;

  /// Time between automatic checks after the first one.
  final Duration interval;

  AppRelease? _available;
  bool _checking = false;
  bool _lastCheckFailed = false;
  DateTime? _lastCheckedAt;
  Future<AppRelease?>? _inFlight;
  bool _forcePrompt = false;
  AppRelease? _prompt;
  String? _promptedVersion;
  Timer? _firstTimer;
  Timer? _periodic;
  bool _disposed = false;

  /// Newest release that is newer than the running app, or null.
  AppRelease? get available => _available;

  /// True while a check is running.
  bool get checking => _checking;

  /// True when the latest check could not reach GitHub or read its answer.
  bool get lastCheckFailed => _lastCheckFailed;

  /// When the latest check finished, or null before the first one.
  DateTime? get lastCheckedAt => _lastCheckedAt;

  /// Starts the automatic checks: one after [firstCheckDelay], then one every
  /// [interval]. Does nothing when `checkUpdates` is off. Calling it again
  /// while the timers run does nothing.
  void start() {
    if (_disposed || !readSettings().checkUpdates) return;
    if (_firstTimer != null || _periodic != null) return;
    _firstTimer = Timer(firstCheckDelay, () {
      _firstTimer = null;
      _periodic = Timer.periodic(interval, (_) => _automatic());
      _automatic();
    });
  }

  /// Checks now, whatever `checkUpdates` says. A newer release is queued for
  /// the update sheet even when its version was skipped. A check that is
  /// already running is shared, not repeated. Returns the newer release, or
  /// null when the app is up to date or the check failed.
  Future<AppRelease?> checkNow() => _run(manual: true);

  /// Returns the release to show in the update sheet and clears it, so each
  /// prompt is taken once. The shell calls this after every change.
  AppRelease? takePrompt() {
    final release = _prompt;
    _prompt = null;
    return release;
  }

  void _automatic() {
    if (!readSettings().checkUpdates) return;
    _run(manual: false);
  }

  Future<AppRelease?> _run({required bool manual}) {
    final running = _inFlight;
    if (running != null) {
      if (manual) _forcePrompt = true;
      return running;
    }
    _forcePrompt = manual;
    final future = _perform();
    _inFlight = future;
    return future;
  }

  Future<AppRelease?> _perform() async {
    _checking = true;
    _notify();

    UpdateCheckResult result;
    try {
      result = await checker.check();
    } on Object {
      result = const UpdateCheckResult(failed: true);
    }

    _inFlight = null;
    _checking = false;
    _lastCheckedAt = DateTime.now();
    final force = _forcePrompt;
    _forcePrompt = false;

    final release = result.release;
    if (result.failed) {
      _lastCheckFailed = true;
    } else {
      _lastCheckFailed = false;
      _available = release;
      if (release != null && (force || _shouldPromptAutomatically(release))) {
        _prompt = release;
        _promptedVersion = release.version;
      }
    }
    _notify();
    return release;
  }

  /// An automatic check prompts once per session per version, and only when
  /// the user has not skipped that version.
  bool _shouldPromptAutomatically(AppRelease release) {
    final settings = readSettings();
    return settings.checkUpdates &&
        release.version != _promptedVersion &&
        shouldNotify(release, skippedVersion: settings.skippedUpdateVersion);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _firstTimer?.cancel();
    _periodic?.cancel();
    _firstTimer = null;
    _periodic = null;
    super.dispose();
  }
}

/// Makes an [UpdateController] available below it. Pass a null [controller]
/// where updates are not supported (mobile, web), so the settings rows stay
/// hidden.
class UpdateScope extends InheritedNotifier<UpdateController> {
  /// Wraps [child] and provides [controller] (or nothing when null).
  const UpdateScope({
    super.key,
    required UpdateController? controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller above [context], or null when updates are not supported.
  /// Does not rebuild the caller on changes; use a ListenableBuilder for that.
  static UpdateController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<UpdateScope>()?.notifier;
}
