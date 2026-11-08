import 'dart:async';
import 'dart:io';

import 'update_checker.dart';

/// Arguments that make the Inno Setup installer run without any window, close
/// the running app and start the new one when it is done (`/RELAUNCH=1` is read
/// by obsidian.iss).
const List<String> kSilentInstallArgs = <String>[
  '/VERYSILENT',
  '/SUPPRESSMSGBOXES',
  '/NORESTART',
  '/CLOSEAPPLICATIONS',
  '/RELAUNCH=1',
];

/// Thrown when the installer could not be downloaded or started.
final class UpdateInstallException implements Exception {
  /// Creates an exception with a short [message] for the log.
  const UpdateInstallException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'UpdateInstallException: $message';
}

/// Whether [url] is a GitHub release download over HTTPS. Anything else is
/// refused, so a tampered release feed cannot point the updater elsewhere.
bool isTrustedDownloadUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https') return false;
  final host = uri.host.toLowerCase();
  return host == 'github.com' ||
      host == 'objects.githubusercontent.com' ||
      host == 'release-assets.githubusercontent.com';
}

/// Downloads the Windows installer [asset] into a fresh temp folder.
///
/// [onProgress] receives a value in 0..1 (only when the size is known). The
/// byte count must match the size GitHub reported, otherwise the file is deleted
/// and [UpdateInstallException] is thrown.
Future<File> downloadInstaller(
  ReleaseAsset asset, {
  void Function(double fraction)? onProgress,
  Directory? tempRoot,
}) async {
  if (!isTrustedDownloadUrl(asset.url)) {
    throw const UpdateInstallException('untrusted download url');
  }
  final root = tempRoot ?? Directory.systemTemp;
  final dir = await root.createTemp('obsidian_update_');
  final name = asset.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..userAgent = 'ObsidianVPN-updater';
  try {
    final request = await client.getUrl(Uri.parse(asset.url));
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw UpdateInstallException('http ${response.statusCode}');
    }
    final total = response.contentLength > 0 ? response.contentLength : asset.size;
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call((received / total).clamp(0.0, 1.0));
      }
    } finally {
      await sink.close();
    }
    if (asset.size > 0 && received != asset.size) {
      throw UpdateInstallException('size mismatch: $received of ${asset.size}');
    }
    return file;
  } on UpdateInstallException {
    await _cleanup(dir);
    rethrow;
  } on Object catch (e) {
    await _cleanup(dir);
    throw UpdateInstallException('download failed: $e');
  } finally {
    client.close(force: true);
  }
}

/// Starts [installer] silently with administrator rights (one UAC prompt) and
/// returns once Windows has started it. Throws [UpdateInstallException] when the
/// user declines the prompt or the process cannot be started.
Future<void> launchSilentInstaller(File installer) async {
  final args = kSilentInstallArgs.map((a) => "'$a'").join(',');
  final path = installer.path.replaceAll("'", "''");
  final result = await Process.run('powershell', <String>[
    '-NoProfile',
    '-NonInteractive',
    '-WindowStyle',
    'Hidden',
    '-Command',
    "Start-Process -FilePath '$path' -ArgumentList $args -Verb RunAs",
  ]);
  if (result.exitCode != 0) {
    throw UpdateInstallException('installer not started: ${result.stderr}');
  }
}

Future<void> _cleanup(Directory dir) async {
  try {
    await dir.delete(recursive: true);
  } on Object {
    // A leftover temp folder is harmless.
  }
}
