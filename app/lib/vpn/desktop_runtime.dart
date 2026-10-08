import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'vpn_backend.dart';

/// Lines containing any of these are never written to logs or the log stream.
const secretMarkers = ['private_key', 'auth_key', 'token'];
const maskedLogLine = '[line hidden: contains a secret field]';

bool containsSecret(String line) {
  final lower = line.toLowerCase();
  return secretMarkers.any(lower.contains);
}

/// Profile id reduced to characters that are safe in file names.
String safeProfileId(String id) {
  final cleaned = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  return cleaned.isEmpty ? 'profile' : cleaned;
}

/// Single-quotes [s] for POSIX sh.
String shellQuote(String s) => "'${s.replaceAll("'", r"'\''")}'";

/// Name of the bundled client asset for this platform (see ARCHITECTURE.md,
/// "Bundled binaries"). The runtime copy keeps the same name.
String desktopClientAssetName() {
  if (Platform.isWindows) return 'obsidian-client-windows-amd64.exe';
  if (Platform.isMacOS) return 'obsidian-client-darwin-universal';
  if (Platform.isLinux) return 'obsidian-client-linux-amd64';
  throw const VpnBackendException(
    'Desktop VPN backend is not available on this platform.',
  );
}

/// Extracts the bundled client into `<appSupport>/runtime/` and writes per-profile configs.
class DesktopRuntime {
  DesktopRuntime(this.supportPath);

  /// Application support directory, from path_provider.
  final String supportPath;

  String get runtimePath => '$supportPath${Platform.pathSeparator}runtime';
  String get clientLogPath => '$supportPath${Platform.pathSeparator}client.log';
  String get clientPath =>
      '$runtimePath${Platform.pathSeparator}${desktopClientAssetName()}';

  /// Path of a per-profile file, e.g. `pathFor(id, '.json')`.
  String pathFor(String profileId, String suffix) =>
      '$runtimePath${Platform.pathSeparator}${safeProfileId(profileId)}$suffix';

  /// Copies assets into the runtime folder when their sha256 differs.
  /// wintun.dll is copied next to the client on Windows.
  Future<void> extract() async {
    await Directory(runtimePath).create(recursive: true);
    final names = [
      desktopClientAssetName(),
      if (Platform.isWindows) 'wintun.dll',
    ];
    for (final name in names) {
      await _copyIfChanged(name, '$runtimePath${Platform.pathSeparator}$name');
    }
  }

  /// Writes the config for [profileId]. The file holds the client key, so it is
  /// readable by the owner only on unix.
  Future<String> writeConfig(String profileId, String json) async {
    final path = pathFor(profileId, '.json');
    final file = File(path);
    if (!Platform.isWindows) {
      // Create and restrict the file before the key is written into it, so it is
      // never readable by other users, not even for a moment.
      await file.create(recursive: true);
      await Process.run('chmod', ['600', path]);
    }
    await file.writeAsString(json, flush: true);
    return path;
  }

  /// Deletes a run config. The client reads its config once at startup, and the file
  /// holds the client key, so it must not stay on disk after the run. A missing or
  /// locked file is not an error: the next start sweeps it.
  static void deleteConfigFile(String path) {
    try {
      File(path).deleteSync();
    } on FileSystemException {
      // Already gone, or locked.
    }
  }

  /// Deletes every `*.json` config left in `runtime/` by an earlier run, for
  /// example after a crash. Other files (client, DLLs, FIFOs, logs) are kept.
  Future<void> deleteStaleConfigs() async {
    final dir = Directory(runtimePath);
    try {
      if (!await dir.exists()) return;
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          deleteConfigFile(entity.path);
        }
      }
    } on FileSystemException {
      // Listing is best effort: nothing to remove when the folder cannot be read.
    }
  }

  Future<void> _copyIfChanged(String name, String destPath) async {
    final Uint8List bytes;
    try {
      final data = await rootBundle.load('assets/bin/$name');
      bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      throw VpnBackendException(
        'В сборке нет $name. Запустите scripts/build-core-assets.',
      );
    }

    final wanted = await _sha256(bytes);
    final dest = File(destPath);
    if (await dest.exists() &&
        _equal(await _sha256(await dest.readAsBytes()), wanted)) {
      await _makeExecutable(destPath);
      return;
    }

    final tmp = File('$destPath.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    try {
      await tmp.rename(destPath);
    } on FileSystemException {
      // Windows: a running exe or a loaded dll cannot be replaced, but it can be
      // renamed out of the way.
      if (!await _replaceLocked(tmp, dest)) {
        try {
          await tmp.delete();
        } on FileSystemException {
          // Best effort.
        }
        // An old copy that cannot be replaced is still usable. Without any
        // copy there is nothing to run.
        if (!await dest.exists()) {
          throw VpnBackendException('Не удалось записать $name в папку данных.');
        }
        return;
      }
    }
    await _makeExecutable(destPath);
    await _removeStale(destPath);
  }

  /// Moves the locked [dest] aside and renames [tmp] into its place.
  Future<bool> _replaceLocked(File tmp, File dest) async {
    final aside = File('${dest.path}.old-${DateTime.now().millisecondsSinceEpoch}');
    try {
      if (await dest.exists()) await dest.rename(aside.path);
      await tmp.rename(dest.path);
      return true;
    } on FileSystemException {
      if (!await dest.exists() && await aside.exists()) {
        try {
          await aside.rename(dest.path);
        } on FileSystemException {
          // Nothing more to do.
        }
      }
      return false;
    }
  }

  /// Deletes `.old-*` copies left by [_replaceLocked]. Ones still in use stay.
  Future<void> _removeStale(String destPath) async {
    final file = File(destPath);
    final prefix = '${file.uri.pathSegments.last}.old-';
    try {
      await for (final entity in file.parent.list()) {
        if (entity is File && entity.uri.pathSegments.last.startsWith(prefix)) {
          try {
            await entity.delete();
          } on FileSystemException {
            // Still running or locked: removed on a later run.
          }
        }
      }
    } on FileSystemException {
      // Listing is best effort.
    }
  }

  Future<void> _makeExecutable(String path) async {
    if (!Platform.isWindows) await Process.run('chmod', ['755', path]);
  }

  static Future<List<int>> _sha256(List<int> bytes) async =>
      (await Sha256().hash(bytes)).bytes;

  static bool _equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Append-only client log with one rotation: `client.log` becomes `client.log.1`
/// once it reaches [maxBytes]. Synchronous on purpose: writes are small and the
/// order of lines must be kept.
class ClientLogFile {
  ClientLogFile(this.path, {this.maxBytes = 1024 * 1024});

  final String path;
  final int maxBytes;
  RandomAccessFile? _raf;
  int _size = 0;

  void writeLine(String line) {
    try {
      final bytes = utf8.encode('$line\n');
      _raf ??= _open();
      if (_size > 0 && _size + bytes.length > maxBytes) _rotate();
      _raf!.writeFromSync(bytes);
      _size += bytes.length;
    } on FileSystemException {
      // A broken log file must never break the tunnel.
    }
  }

  void close() {
    _raf?.closeSync();
    _raf = null;
  }

  RandomAccessFile _open() {
    final file = File(path);
    _size = file.existsSync() ? file.lengthSync() : 0;
    return file.openSync(mode: FileMode.append);
  }

  void _rotate() {
    close();
    final backup = File('$path.1');
    if (backup.existsSync()) backup.deleteSync();
    File(path).renameSync(backup.path);
    _raf = _open();
  }
}
