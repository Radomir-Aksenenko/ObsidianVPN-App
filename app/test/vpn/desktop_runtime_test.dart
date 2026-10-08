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
