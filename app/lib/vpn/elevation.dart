import 'dart:io';

/// The user refused the UAC prompt, or the elevation request failed.
class ElevationDenied implements Exception {
  const ElevationDenied([
    this.message =
        'Нужны права Администратора. Разрешите запрос UAC и повторите подключение.',
  ]);

  final String message;

  @override
  String toString() => message;
}

/// Windows: `net session` succeeds only for an elevated token.
/// Unix: uid 0.
Future<bool> isElevated() async {
  if (Platform.isWindows) {
    final result = await Process.run('net', ['session']);
    return result.exitCode == 0;
  }
  if (Platform.isLinux || Platform.isMacOS) {
    final result = await Process.run('id', ['-u']);
    return result.exitCode == 0 && (result.stdout as String).trim() == '0';
  }
  return false;
}

/// Restarts this executable elevated (UAC) with [args], then exits the current
/// process. Throws [ElevationDenied] when the prompt is refused.
Future<Never> relaunchElevatedWindows({
  List<String> args = const ['--connect'],
}) async {
  final exe = Platform.resolvedExecutable.replaceAll("'", "''");
  final argList = args.join(' ').replaceAll("'", "''");
  final script =
      "Start-Process -FilePath '$exe' -Verb RunAs -ArgumentList '$argList'";
  final result = await Process.run('powershell', [
    '-NoProfile',
    '-NonInteractive',
    '-WindowStyle',
    'Hidden',
    '-Command',
    script,
  ]);
  if (result.exitCode != 0) {
    throw const ElevationDenied();
  }
  exit(0);
}

/// Starts this app at logon with `--autostart`.
/// Windows: scheduled task with highest privileges. Linux: XDG autostart entry.
/// macOS: LaunchAgent. Enabling throws on failure, disabling is best effort.
Future<void> setAutostart(bool enabled) async {
  final exe = Platform.resolvedExecutable;
  if (Platform.isWindows) {
    await _setWindowsAutostart(exe, enabled);
  } else if (Platform.isLinux) {
    await _setLinuxAutostart(exe, enabled);
  } else if (Platform.isMacOS) {
    await _setMacAutostart(exe, enabled);
  }
}

Future<void> _setWindowsAutostart(String exe, bool enabled) async {
  // Legacy task name from the Tauri client, removed in both cases.
  await Process.run('schtasks', ['/Delete', '/TN', 'ObsidianVPN-Client', '/F']);
  await Process.run('schtasks', ['/Delete', '/TN', 'ObsidianVPN', '/F']);
  if (!enabled) return;
  final result = await Process.run('schtasks', [
    '/Create',
    '/TN',
    'ObsidianVPN',
    '/SC',
    'ONLOGON',
    '/RL',
    'HIGHEST',
    '/TR',
    '"$exe" --autostart',
    '/F',
  ]);
  if (result.exitCode != 0) {
    throw StateError(
      'schtasks /Create failed: ${result.stderr}${result.stdout}',
    );
  }
}

String _linuxConfigHome() {
  final xdg = Platform.environment['XDG_CONFIG_HOME'];
  if (xdg != null && xdg.isNotEmpty) return xdg;
  return '${Platform.environment['HOME'] ?? ''}/.config';
}

Future<void> _setLinuxAutostart(String exe, bool enabled) async {
  final file = File('${_linuxConfigHome()}/autostart/obsidian-vpn.desktop');
  if (!enabled) {
    if (await file.exists()) await file.delete();
    return;
  }
  final escaped = exe.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  await file.parent.create(recursive: true);
  await file.writeAsString(
    '[Desktop Entry]\n'
    'Type=Application\n'
    'Name=Obsidian VPN\n'
    'Exec="$escaped" --autostart\n'
    'Terminal=false\n'
    'X-GNOME-Autostart-enabled=true\n',
    flush: true,
  );
}

Future<void> _setMacAutostart(String exe, bool enabled) async {
  final home = Platform.environment['HOME'] ?? '';
  final plist = File('$home/Library/LaunchAgents/com.obsidian.vpn.plist');
  if (plist.existsSync()) {
    await Process.run('launchctl', ['unload', '-w', plist.path]);
  }
  if (!enabled) {
    if (plist.existsSync()) await plist.delete();
    return;
  }
  final xmlExe = exe
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  await plist.parent.create(recursive: true);
  await plist.writeAsString(
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
    '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
    '<plist version="1.0"><dict>\n'
    '  <key>Label</key><string>com.obsidian.vpn</string>\n'
    '  <key>ProgramArguments</key><array>\n'
    '    <string>$xmlExe</string>\n'
    '    <string>--autostart</string>\n'
    '  </array>\n'
    '  <key>RunAtLoad</key><true/>\n'
    '</dict></plist>\n',
    flush: true,
  );
  final result = await Process.run('launchctl', ['load', '-w', plist.path]);
  if (result.exitCode != 0) {
    throw StateError('launchctl load failed: ${result.stderr}');
  }
}
