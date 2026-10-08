import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/vpn/desktop_runtime.dart';

void main() {
  group('secret masking', () {
    test('lines with key or token names are secret', () {
      expect(containsSecret('client_private_key=abc'), isTrue);
      expect(containsSecret('reality_auth_key: 00ff'), isTrue);
      expect(containsSecret('got Token refresh'), isTrue);
    });

    test('ordinary client lines are not secret', () {
      expect(containsSecret('session 1234abcd: ready'), isFalse);
      expect(containsSecret('tun address set 10.8.0.5/24'), isFalse);
    });
  });

  test('safeProfileId keeps only file-name safe characters', () {
    expect(safeProfileId('abc-123_x'), 'abc-123_x');
    expect(safeProfileId('../../etc/passwd'), '______etc_passwd');
    expect(safeProfileId(''), 'profile');
  });

  test('shellQuote wraps the value and escapes single quotes', () {
    expect(shellQuote('/a b/c'), "'/a b/c'");
    expect(shellQuote("it's"), "'it'\\''s'");
  });

  group('run configs', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('obsidian-config-test-');
    });

    tearDown(() {
      dir.deleteSync(recursive: true);
    });

    test('deleteConfigFile removes a written config and ignores a missing file', () async {
      final rt = DesktopRuntime(dir.path);
      Directory(rt.runtimePath).createSync(recursive: true);
      final path = await rt.writeConfig('profile-1', '{"client_private_key":"aa"}');
      expect(File(path).existsSync(), isTrue);

      DesktopRuntime.deleteConfigFile(path);
      expect(File(path).existsSync(), isFalse);

      DesktopRuntime.deleteConfigFile(path);
    });

    test('deleteStaleConfigs removes json configs and keeps the other runtime files', () async {
      final rt = DesktopRuntime(dir.path);
      Directory(rt.runtimePath).createSync(recursive: true);
      await rt.writeConfig('stale-a', '{}');
      await rt.writeConfig('stale-b', '{}');
      File(rt.pathFor('stale-a', '.run.log')).writeAsStringSync('log');
      File(rt.pathFor('stale-a', '.stdin')).writeAsStringSync('');

      await rt.deleteStaleConfigs();

      expect(File(rt.pathFor('stale-a', '.json')).existsSync(), isFalse);
      expect(File(rt.pathFor('stale-b', '.json')).existsSync(), isFalse);
      expect(File(rt.pathFor('stale-a', '.run.log')).existsSync(), isTrue);
      expect(File(rt.pathFor('stale-a', '.stdin')).existsSync(), isTrue);
    });

    test('deleteStaleConfigs does nothing when the runtime folder is missing', () async {
      await DesktopRuntime(dir.path).deleteStaleConfigs();
      expect(Directory(DesktopRuntime(dir.path).runtimePath).existsSync(), isFalse);
    });
  });

  group('ClientLogFile', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('obsidian-log-test-');
    });

    tearDown(() {
      dir.deleteSync(recursive: true);
    });

    test('appends lines and rotates to client.log.1 at the size limit', () {
      final path = '${dir.path}${Platform.pathSeparator}client.log';
      final log = ClientLogFile(path, maxBytes: 40);

      log.writeLine('first line of text here'); // 24 bytes with newline
      log.writeLine('second line of text here'); // rotates before writing
      log.close();

      final current = File(path).readAsStringSync();
      final backup = File('$path.1').readAsStringSync();
      expect(backup, 'first line of text here\n');
      expect(current, 'second line of text here\n');
    });

    test('a second rotation replaces the old backup', () {
      final path = '${dir.path}${Platform.pathSeparator}client.log';
      final log = ClientLogFile(path, maxBytes: 30);

      log.writeLine('aaaaaaaaaaaaaaaaaaaa'); // 21 bytes
      log.writeLine('bbbbbbbbbbbbbbbbbbbb'); // rotates
      log.writeLine('cccccccccccccccccccc'); // rotates again
      log.close();

      expect(File('$path.1').readAsStringSync(), 'bbbbbbbbbbbbbbbbbbbb\n');
      expect(File(path).readAsStringSync(), 'cccccccccccccccccccc\n');
    });
  });
}
