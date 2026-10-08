import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/core/models/profile.dart';
import 'package:obsidian_vpn/core/models/split_tunnel.dart';
import 'package:obsidian_vpn/vps/vps_models.dart';

void main() {
  group('guessCountryCode', () {
    test('matches the keyword table in Latin and Cyrillic', () {
      expect(guessCountryCode('Frankfurt-1'), 'DE');
      expect(guessCountryCode('Хельсинки 2'), 'FI');
      expect(guessCountryCode('Москва'), 'RU');
      expect(guessCountryCode('Нью-Йорк'), 'US');
      expect(guessCountryCode('Tokyo edge'), 'JP');
      expect(guessCountryCode('UK London'), 'GB');
    });

    test('short Latin keywords need a whole word', () {
      expect(guessCountryCode('Ukraine node'), kFallbackCountryCode);
      expect(guessCountryCode('my usa box'), 'US');
    });

    test('falls back to VPN', () {
      expect(guessCountryCode('Lab VPS'), 'VPN');
      expect(guessCountryCode(''), 'VPN');
    });
  });

  test('generateUuidV4 returns a version 4 RFC 4122 id', () {
    final pattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    for (var i = 0; i < 20; i++) {
      expect(generateUuidV4(), matches(pattern));
    }
    expect(generateUuidV4(), isNot(generateUuidV4()));
  });

  test('ServerProfile JSON round-trips and carries no VPS secrets', () {
    final profile = ServerProfile(
      id: 'p1',
      name: 'Lab',
      countryCode: 'VPN',
      host: '198.51.100.7',
      port: 8443,
      serverPublicKey: 'AB' * 32,
      source: ProfileSource.vps,
      createdAt: DateTime.utc(2026, 3, 4, 5, 6, 7),
      split: SplitTunnelConfig(mode: SplitMode.include, entries: const ['a.example']),
      vps: const VpsCredentials(host: '198.51.100.7', user: 'admin', port: 2222),
      vpsHostKey: 'SHA256:abc',
      serverVersion: '1.0.0',
      needsUpdate: true,
    );

    final json = profile.toJson();
    final back = ServerProfile.fromJson(json);

    expect(back.id, 'p1');
    expect(back.serverPublicKey, 'ab' * 32);
    expect(back.source, ProfileSource.vps);
    expect(back.vps?.user, 'admin');
    expect(back.vps?.port, 2222);
    expect(back.vps?.password, isNull);
    expect(back.vpsHostKey, 'SHA256:abc');
    expect(back.split.mode, SplitMode.include);
    expect(back.needsUpdate, isTrue);
    expect(json.toString(), isNot(contains('password')));
  });

  test('ServerProfile.fromJson rejects a missing host or port', () {
    expect(
      () => ServerProfile.fromJson(<String, dynamic>{'id': 'x', 'host': '', 'port': 1}),
      throwsFormatException,
    );
    expect(
      () => ServerProfile.fromJson(<String, dynamic>{'id': 'x', 'host': 'h', 'port': 70000}),
      throwsFormatException,
    );
  });

  test('AppSettings defaults and JSON fallbacks', () {
    const defaults = AppSettings();
    expect(defaults.minimizeToTray, isTrue);
    expect(defaults.killSwitch, isFalse);
    expect(defaults.haptics, isTrue);
    expect(defaults.themeMode, AppThemeMode.system);
    expect(defaults.locale, AppLocalePref.system);

    final fromEmpty = AppSettings.fromJson(<String, dynamic>{});
    expect(fromEmpty.minimizeToTray, isTrue);
    expect(fromEmpty.lastProfileId, isNull);

    final cleared = defaults.copyWith(lastProfileId: 'a').copyWith(clearLastProfileId: true);
    expect(cleared.lastProfileId, isNull);
    expect(AppLocalePref.fromWire('en'), AppLocalePref.en);
    expect(AppThemeMode.fromWire('weird'), AppThemeMode.system);
  });
}
