import 'dart:async';
import 'dart:io';

/// Removes network leftovers of the Windows tunnel. Port of `cleanup_system_network`
/// in desktop/src-tauri/src/vpn.rs. Every command is run with no shell and its
/// failure is ignored. The NRPT rule removal runs in the background, like the
/// original, so it never delays the caller.
///
/// Hidden windows: Dart's Windows process launcher is not expected to open a
/// console window for these children (it is believed to pass CREATE_NO_WINDOW).
/// This was not verified on the dev box.
Future<void> cleanupWindowsNetwork() async {
  if (!Platform.isWindows) return;

  Future<void> run(String exe, List<String> args) async {
    try {
      await Process.run(exe, args, runInShell: false);
    } catch (_) {
      // Ignored by design.
    }
  }

  // Stale split-default and DNS routes.
  await run('route', ['delete', '0.0.0.0', 'mask', '128.0.0.0']);
  await run('route', ['delete', '128.0.0.0', 'mask', '128.0.0.0']);
  await run('route', ['delete', '1.1.1.1']);
  await run('route', ['delete', '1.0.0.1']);
  await run('route', ['delete', '8.8.8.8']);
  await run('route', ['delete', '8.8.4.4']);

  // Global DNS client policy values that break Windows name resolution.
  const dnsPolicy = r'HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient';
  await run('reg', [
    'delete',
    dnsPolicy,
    '/v',
    'DisableSmartNameResolution',
    '/f',
  ]);
  await run('reg', ['delete', dnsPolicy, '/v', 'EnableMulticast', '/f']);

  // Firewall rules that block DNS leaks.
  for (final rule in const [
    'ObsidianVPN-Block-Physical-DNS-UDP',
    'ObsidianVPN-Block-Physical-DNS-TCP',
    'ObsidianVPN-Block-IPv6-DNS-UDP',
    'ObsidianVPN-Block-IPv6-DNS-TCP',
    'ObsidianVPN-Block-Router-DNS',
    'ObsidianVPN-Block-Router-DNS-TCP',
  ]) {
    await run('netsh', [
      'advfirewall',
      'firewall',
      'delete',
      'rule',
      'name=$rule',
    ]);
  }

  await run('ipconfig', ['/flushdns']);

  unawaited(
    run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-WindowStyle',
      'Hidden',
      '-Command',
      'Get-DnsClientNrptRule -ErrorAction SilentlyContinue | '
          "Where-Object DisplayName -eq 'ObsidianVPN-NRPT' | "
          'Remove-DnsClientNrptRule -Force -ErrorAction SilentlyContinue; '
          'Clear-DnsClientCache -ErrorAction SilentlyContinue',
    ]),
  );
}
