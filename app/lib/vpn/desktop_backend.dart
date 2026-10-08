import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'desktop_log_parser.dart';
import 'desktop_runtime.dart';
import 'elevation.dart';
import 'vpn_backend.dart';
import 'windows_cleanup.dart';

/// Desktop VPN backend. Runs the bundled Go client as a child process.
///
/// Launch per platform:
/// - Windows: the client directly, with pipes, no shell. Needs elevation.
/// - Linux: `pkexec <client> --config ... --debug`.
/// - macOS: `osascript ... with administrator privileges`. The client runs in the
///   background with stdin read from a FIFO that this app holds open. Output goes
///   to a log file, which is tailed every 250 ms while the run is alive.
///
/// Stats: the Go client prints no traffic counters, and reading OS interface
/// counters would need an adapter name and a periodic poll. So this backend never
/// emits [TrafficStats]. [statsActive] only stores the flag, and no timer runs
/// for stats.
class DesktopVpnBackend implements VpnBackend {
  DesktopVpnBackend({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    _parser = DesktopLogParser(clock: _clock);
    // Startup cleanup of stale Windows routes and DNS policy. It runs in the
    // queue, so a connect started right away waits for it.
    if (Platform.isWindows) unawaited(_serial(cleanupWindowsNetwork));
  }

  static const _ringSize = 500;

  final DateTime Function() _clock;
  late final DesktopLogParser _parser;
  VpnStatus _status = const VpnStatus();
  final _statusBus = StreamController<VpnStatus>.broadcast();
  final _statsBus = StreamController<TrafficStats>.broadcast();
  final _logBus = StreamController<String>.broadcast();
  final _ring = Queue<String>();
  bool _statsActive = false;
  bool _disposed = false;
  Future<void> _queue = Future<void>.value();

  _Run? _run;

  /// Bumped whenever the current run changes, so late events from an old run
  /// are logged but never parsed or reported.
  int _gen = 0;
  DesktopRuntime? _runtime;
  ClientLogFile? _logFile;
  ({String profileId, String name, String serverHost})? _last;

  @override
  Stream<VpnStatus> get status => _replay(() => [_status], _statusBus.stream);

  /// Never emits on desktop, see the class comment.
  @override
  Stream<TrafficStats> get stats => _statsBus.stream;

  @override
  Stream<String> get logs => _replay(() => _ring.toList(), _logBus.stream);

  @override
  set statsActive(bool v) => _statsActive = v;

  bool get statsActive => _statsActive;

  @override
  Future<bool> ensurePermission() async {
    // Linux and macOS ask for the password when connecting (pkexec, osascript).
    if (!Platform.isWindows) return true;
    if (await isElevated()) return true;
    try {
      // On success this relaunches elevated and exits the process.
      await relaunchElevatedWindows(args: const ['--connect']);
    } on ElevationDenied {
      return false;
    }
  }

  @override
  Future<void> connect({
    required String profileId,
    required String name,
    required String serverHost,
    required String configJson,
  }) {
    return _serial(
      () => _connectNow(
        profileId: profileId,
        name: name,
        serverHost: serverHost,
        configJson: configJson,
      ),
    );
  }

  @override
  Future<void> disconnect() => _serial(_disconnectNow);

  /// Reconnects with the new config when a tunnel is running. Otherwise does nothing:
  /// the next connect takes the config it is given.
  @override
  Future<void> applySplit(String configJson) {
    return _serial(() async {
      final last = _last;
      if (_run == null || last == null) return;
      await _connectNow(
        profileId: last.profileId,
        name: last.name,
        serverHost: last.serverHost,
        configJson: configJson,
      );
    });
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await _serial(_disconnectNow);
    _disposed = true;
    await _statusBus.close();
    await _statsBus.close();
    await _logBus.close();
    _logFile?.close();
  }

  Future<void> _connectNow({
    required String profileId,
    required String name,
    required String serverHost,
    required String configJson,
  }) async {
    if (_disposed) {
      throw const VpnBackendException('VPN-бэкенд уже остановлен.');
    }
    if (_run != null) await _disconnectNow();
    _last = (profileId: profileId, name: name, serverHost: serverHost);
    _emit(const VpnStatus(phase: VpnPhase.connecting));
    try {
      if (Platform.isWindows && !await ensurePermission()) {
        throw const ElevationDenied();
      }
      final rt = await _prepareRuntime();
      final cfgPath = await rt.writeConfig(profileId, configJson);
      _writeLog('--- connect "$name" -> $serverHost ---');
      final gen = ++_gen;
      final run = await _launch(rt, cfgPath, profileId, gen);
      _run = run;
      unawaited(run.done.then((_) => _onRunEnded(gen)));
    } on ElevationDenied catch (e) {
      _emit(VpnStatus(phase: VpnPhase.error, error: e.message));
      rethrow;
    } catch (e) {
      final message = e is VpnBackendException
          ? e.message
          : 'Не удалось запустить клиент: $e';
      _emit(VpnStatus(phase: VpnPhase.error, error: message));
      throw VpnBackendException(message);
    }
  }

  Future<void> _disconnectNow() async {
    final run = _run;
    _gen++;
    _run = null;
    if (run != null) {
      _emit(const VpnStatus(phase: VpnPhase.disconnecting));
      await run.stop();
    }
    _emit(const VpnStatus());
    await cleanupWindowsNetwork();
  }

  /// The client exited on its own: report the error and clean up the network.
  void _onRunEnded(int gen) {
    if (gen != _gen || _run == null) return;
    final tail = _ring.length > 40
        ? _ring.skip(_ring.length - 40).toList()
        : _ring.toList();
    _gen++;
    _run = null;
    _emit(VpnStatus(phase: VpnPhase.error, error: humanizeExit(tail)));
    if (Platform.isWindows) unawaited(_serial(cleanupWindowsNetwork));
  }

  void _handleLine(int gen, String raw) {
    _writeLog(raw);
    if (gen != _gen || _run == null) return;
    _publish(_parser.feed(raw));
  }

  /// Masks secret lines, then stores the line in the ring buffer, the log stream
  /// and the log file.
  void _writeLog(String raw) {
    final line = containsSecret(raw) ? maskedLogLine : raw;
    _ring.add(line);
    while (_ring.length > _ringSize) {
      _ring.removeFirst();
    }
    if (!_logBus.isClosed) _logBus.add(line);
    _logFile?.writeLine(line);
  }

  /// Runs [action] after everything queued before it. connect, disconnect and
  /// applySplit never overlap.
  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  /// Resets the parser to [next] and publishes it.
  void _emit(VpnStatus next) {
    _parser.reset(next);
    _publish(next);
  }

  void _publish(VpnStatus next) {
    if (next == _status) return;
    _status = next;
    if (!_statusBus.isClosed) _statusBus.add(next);
  }

  Future<DesktopRuntime> _prepareRuntime() async {
    final cached = _runtime;
    if (cached != null) return cached;
    final support = await getApplicationSupportDirectory();
    final rt = DesktopRuntime(support.path);
    await rt.extract();
    _logFile ??= ClientLogFile(rt.clientLogPath);
    _runtime = rt;
    return rt;
  }

  Future<_Run> _launch(
    DesktopRuntime rt,
    String cfgPath,
    String profileId,
    int gen,
  ) async {
    void onLine(String line) => _handleLine(gen, line);
    final args = ['--config', cfgPath, '--debug'];

    if (Platform.isWindows) {
      // The client is a console-subsystem exe. The pipes are the only I/O and no
      // shell is used. Dart is believed to start children with CREATE_NO_WINDOW,
      // which keeps a console from appearing for this GUI parent. Not verified here.
      final proc = await Process.start(
        rt.clientPath,
        args,
        workingDirectory: rt.runtimePath,
        runInShell: false,
        mode: ProcessStartMode.normal,
      );
      return _PipeRun(proc, onLine);
    }

    if (Platform.isLinux) {
      final id = safeProfileId(profileId);
      final proc = await Process.start(
        'pkexec',
        [rt.clientPath, ...args],
        workingDirectory: rt.runtimePath,
        runInShell: false,
      );
      // Closing stdin asks the client to exit. If it ignores that, SIGTERM goes to
      // pkexec, which does not reliably forward it, so a pkill fallback runs too.
      return _PipeRun(
        proc,
        onLine,
        forceKill: () async {
          await Process.run('pkexec', ['pkill', '-KILL', '-f', '$id.json']);
        },
      );
    }

    return _launchMac(rt, cfgPath, profileId, onLine);
  }

  Future<_Run> _launchMac(
    DesktopRuntime rt,
    String cfgPath,
    String profileId,
    void Function(String) onLine,
  ) async {
    final fifo = rt.pathFor(profileId, '.stdin');
    final log = rt.pathFor(profileId, '.run.log');
    final stale = File(fifo);
    if (await stale.exists()) await stale.delete();
    final mk = await Process.run('mkfifo', [fifo]);
    if (mk.exitCode != 0) {
      throw VpnBackendException('Не удалось создать канал stdin: ${mk.stderr}');
    }

    // Redirection order matters: stdout and stderr go to the log first, then stdin
    // opens the FIFO. Otherwise the child keeps the osascript pipe open while it
    // waits for a writer, and do shell script never returns.
    final command =
        '${shellQuote(rt.clientPath)} --config ${shellQuote(cfgPath)} --debug '
        '> ${shellQuote(log)} 2>&1 < ${shellQuote(fifo)} & echo \$!';
    final result = await _osascriptAdmin(command);
    final pid = int.tryParse((result.stdout as String).trim());
    if (result.exitCode != 0 || pid == null) {
      throw const VpnBackendException(
        'Нужны права администратора для запуска клиента.',
      );
    }

    // Opening the FIFO for writing blocks until the client opens it for reading.
    final writer = await File(fifo)
        .open(mode: FileMode.writeOnly)
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw const VpnBackendException(
            'Клиент не открыл канал stdin. Попробуйте подключиться снова.',
          ),
        );
    return _OsaRun(pid: pid, stdin: writer, logPath: log, onLine: onLine);
  }
}

/// Live status and log lines, and the replayed current value for a new listener.
Stream<T> _replay<T>(List<T> Function() snapshot, Stream<T> live) {
  StreamSubscription<T>? sub;
  late final StreamController<T> out;
  out = StreamController<T>(
    onListen: () {
      for (final value in snapshot()) {
        out.add(value);
      }
      sub = live.listen(out.add, onError: out.addError, onDone: out.close);
    },
    onCancel: () => sub?.cancel(),
  );
  return out.stream;
}

Future<ProcessResult> _osascriptAdmin(String shell) {
  final escaped = shell.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  return Process.run('osascript', [
    '-e',
    'do shell script "$escaped" with administrator privileges',
  ]);
}

abstract class _Run {
  /// Completes when the client is gone and its output has been drained.
  Future<void> get done;

  /// Asks the client to stop: EOF on stdin first, then force. Never throws.
  Future<void> stop();
}

/// Client started with pipes (Windows, Linux).
class _PipeRun implements _Run {
  _PipeRun(this._proc, void Function(String) onLine, {this._forceKill}) {
    done = Future.wait<Object?>([
      _proc.exitCode,
      _pump(_proc.stdout, onLine),
      _pump(_proc.stderr, onLine),
    ]).then((_) {});
  }

  final Process _proc;
  final Future<void> Function()? _forceKill;

  @override
  late final Future<void> done;

  static Future<void> _pump(
    Stream<List<int>> stream,
    void Function(String) onLine,
  ) async {
    try {
      await stream
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .forEach(onLine);
    } catch (_) {
      // The stream ends with the process. Read errors only end this pump.
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _proc.stdin.close().timeout(const Duration(seconds: 1));
    } catch (_) {
      // Already closed or the process is gone.
    }
    if (await _exitedWithin(const Duration(milliseconds: 1500))) return;
    _proc.kill();
    if (await _exitedWithin(const Duration(milliseconds: 1500))) return;
    await _forceKill?.call();
  }

  Future<bool> _exitedWithin(Duration limit) =>
      _proc.exitCode.then((_) => true).timeout(limit, onTimeout: () => false);
}

/// Client started by the macOS administrator script. Its output is read from a
/// log file, and stdin is a FIFO that this process holds open.
class _OsaRun implements _Run {
  _OsaRun({
    required this.pid,
    required this._stdin,
    required this.logPath,
    required this._onLine,
  }) {
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
  }

  final int pid;
  final String logPath;
  final RandomAccessFile _stdin;
  final void Function(String) _onLine;
  late final Timer _timer;
  final _done = Completer<void>();
  int _offset = 0;
  String _partial = '';
  bool _busy = false;
  int _ticks = 0;

  @override
  Future<void> get done => _done.future;

  Future<void> _tick() async {
    if (_busy || _done.isCompleted) return;
    _busy = true;
    try {
      await _readNew();
      // Checking liveness spawns `ps`, so it runs once a second, not every tick.
      if (++_ticks % 4 == 0 && !await _alive()) {
        await _readNew();
        _finish();
      }
    } catch (_) {
      // Transient read errors are retried on the next tick.
    } finally {
      _busy = false;
    }
  }

  Future<void> _readNew() async {
    final file = File(logPath);
    if (!await file.exists()) return;
    final len = await file.length();
    if (len < _offset) {
      _offset = 0;
      _partial = '';
    }
    if (len == _offset) return;
    final raf = await file.open();
    final List<int> bytes;
    try {
      await raf.setPosition(_offset);
      bytes = await raf.read(len - _offset);
    } finally {
      await raf.close();
    }
    _offset += bytes.length;
    final text =
        _partial + const Utf8Decoder(allowMalformed: true).convert(bytes);
    final parts = text.split('\n');
    _partial = parts.removeLast();
    for (final part in parts) {
      _onLine(part.endsWith('\r') ? part.substring(0, part.length - 1) : part);
    }
  }

  Future<bool> _alive() async =>
      (await Process.run('ps', ['-p', '$pid'])).exitCode == 0;

  Future<bool> _waitDead(Duration limit) async {
    final deadline = DateTime.now().add(limit);
    while (DateTime.now().isBefore(deadline)) {
      if (!await _alive()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return !await _alive();
  }

  Future<void> _closeStdin() async {
    try {
      await _stdin.close();
    } catch (_) {
      // Already closed.
    }
  }

  void _finish() {
    if (_done.isCompleted) return;
    _timer.cancel();
    unawaited(_closeStdin());
    _done.complete();
  }

  @override
  Future<void> stop() async {
    _timer.cancel();
    // Closing the FIFO sends EOF, which the client treats as a stop request.
    await _closeStdin();
    if (!await _waitDead(const Duration(milliseconds: 1500))) {
      await _osascriptAdmin(
        'kill -TERM $pid; sleep 1; kill -KILL $pid 2>/dev/null; true',
      );
    }
    while (_busy) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    try {
      await _readNew();
    } catch (_) {
      // The log is best effort during shutdown.
    }
    _finish();
  }
}
