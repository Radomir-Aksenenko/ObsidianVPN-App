import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/core/models/profile.dart';

void main() {
  group('AppSettings update fields', () {
    test('defaults: checks on, no skipped version', () {
      const settings = AppSettings();

      expect(settings.checkUpdates, isTrue);
      expect(settings.skippedUpdateVersion, isNull);
      expect(settings.toJson().containsKey('skipped_update_version'), isFalse);
    });

    test('JSON round-trip keeps both fields', () {
      const settings = AppSettings(
        checkUpdates: false,
        skippedUpdateVersion: '2.1.0',
      );

      final back = AppSettings.fromJson(settings.toJson());

      expect(back.checkUpdates, isFalse);
      expect(back.skippedUpdateVersion, '2.1.0');
    });

    test('a file saved before these fields loads with the defaults', () {
      final old = <String, dynamic>{
        'autostart': true,
        'minimize_to_tray': false,
        'kill_switch': false,
      };

      final loaded = AppSettings.fromJson(old);

      expect(loaded.autostart, isTrue);
      expect(loaded.minimizeToTray, isFalse);
      expect(loaded.checkUpdates, isTrue);
      expect(loaded.skippedUpdateVersion, isNull);
    });

    test('a blank or wrong-typed value loads with the defaults', () {
      final loaded = AppSettings.fromJson(<String, dynamic>{
        'check_updates': 'yes',
        'skipped_update_version': '   ',
      });

      expect(loaded.checkUpdates, isTrue);
      expect(loaded.skippedUpdateVersion, isNull);
    });

    test('copyWith sets, keeps and clears skippedUpdateVersion', () {
      const base = AppSettings();

      final skipped = base.copyWith(skippedUpdateVersion: '2.1.0');
      expect(skipped.skippedUpdateVersion, '2.1.0');
      expect(
        skipped.copyWith(checkUpdates: false).skippedUpdateVersion,
        '2.1.0',
      );
      expect(
        skipped.copyWith(clearSkippedUpdateVersion: true).skippedUpdateVersion,
        isNull,
      );
    });
  });
}
