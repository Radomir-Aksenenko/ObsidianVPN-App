import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/core/update/update_checker.dart';
import 'package:obsidian_vpn/core/update/windows_updater.dart';

void main() {
  test('only HTTPS GitHub download hosts are trusted', () {
    expect(isTrustedDownloadUrl('https://github.com/a/b/releases/download/v1/x.exe'), isTrue);
    expect(isTrustedDownloadUrl('https://objects.githubusercontent.com/x'), isTrue);
    expect(isTrustedDownloadUrl('http://github.com/x'), isFalse);
    expect(isTrustedDownloadUrl('https://github.com.evil.example/x'), isFalse);
    expect(isTrustedDownloadUrl('file:///C:/x.exe'), isFalse);
  });

  test('silent install arguments ask for a restart', () {
    expect(kSilentInstallArgs, containsAll(['/VERYSILENT', '/RELAUNCH=1']));
  });

  test('downloadInstaller refuses an untrusted URL', () async {
    final asset = const ReleaseAsset(name: 'x-setup.exe', url: 'https://evil.example/x', size: 1);
    expect(
      downloadInstaller(asset, tempRoot: Directory.systemTemp),
      throwsA(isA<UpdateInstallException>()),
    );
  });
}
