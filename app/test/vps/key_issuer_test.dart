import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/core/codec/client_config.dart';
import 'package:obsidian_vpn/core/codec/obsidian_key.dart';
import 'package:obsidian_vpn/vps/key_issuer.dart';
import 'package:obsidian_vpn/vps/vps_models.dart';

String _hex64(String c) => List.filled(64, c).join();

ClientConfig _serverConfig() => ClientConfig(
      protocolVersion: 2,
      serverHost: '203.0.113.10',
      serverPort: '443',
      udpPort: '443',
      serverPublicKey: _hex64('a'),
      realityEnabled: true,
      realityAuthKey: _hex64('b'),
      realitySni: 'www.microsoft.com',
      enableUdpData: true,
      enableIpv6: false,
      dns: '10.8.0.1',
      junkCount: 7,
      noiseMinSec: 10,
      noiseMaxSec: 40,
      keepaliveSec: 20,
      profile: 'fast-secure',
      jitter: 'off',
      keyserver: 'http://203.0.113.10:8444',
      mtu: 1420,
    );

final DateTime _now = DateTime.utc(2026, 10, 8, 12);

void main() {
  group('issueKey', () {
    test('OBSDN key decodes back with expiry, devices and server fields', () {
      final issued = issueKey(
        serverConfig: _serverConfig(),
        name: 'Phone',
        days: 30,
        devices: 3,
        serverId: 'srv-1',
        now: _now,
        random: Random(1),
      );

      final decoded = parseKey(issued.key);
      expect(decoded.expires, '2026-11-07');
      expect(decoded.maxDevices, 3);
      expect(decoded.serverHost, '203.0.113.10');
      expect(decoded.serverPort, '443');
      expect(decoded.serverPublicKey, _hex64('a'));
      expect(decoded.realityAuthKey, _hex64('b'));
      expect(decoded.realitySni, 'www.microsoft.com');
      expect(decoded.mtu, 1420);
      expect(decoded.clientPrivateKey, isEmpty);
      expect(decoded.keyserver, 'http://203.0.113.10:8444');
    });

    test('obsidian:// URI carries label, expiry and device limit', () {
      final issued = issueKey(
        serverConfig: _serverConfig(),
        name: 'Laptop',
        days: 7,
        devices: 2,
        now: _now,
        random: Random(2),
      );

      final decoded = parseKey(issued.uri);
      expect(decoded.label, 'Laptop');
      expect(decoded.expires, '2026-10-15');
      expect(decoded.maxDevices, 2);
      expect(decoded.serverHost, '203.0.113.10');
    });

    test('days = 0 means no expiry', () {
      final issued = issueKey(
        serverConfig: _serverConfig(),
        name: 'Owner',
        days: 0,
        devices: 3,
        now: _now,
        random: Random(3),
      );
      expect(parseKey(issued.key).expires, isEmpty);
      expect(issued.days, 0);
    });

    test('empty name becomes Guest', () {
      final issued = issueKey(
        serverConfig: _serverConfig(),
        name: '   ',
        now: _now,
        random: Random(4),
      );
      expect(issued.name, 'Guest');
      expect(parseKey(issued.uri).label, 'Guest');
    });

    test('metadata fields are set on the model', () {
      final issued = issueKey(
        serverConfig: _serverConfig(),
        name: 'Phone',
        days: 30,
        devices: 5,
        serverId: 'srv-9',
        now: _now,
        random: Random(5),
      );
      expect(issued.serverId, 'srv-9');
      expect(issued.devices, 5);
      expect(issued.days, 30);
      expect(issued.created, _now);
      expect(
        issued.id,
        matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
      );
    });

    test('device count outside 1..20 is rejected', () {
      expect(
        () => issueKey(serverConfig: _serverConfig(), name: 'x', devices: 0),
        throwsA(isA<VpsException>()),
      );
      expect(
        () => issueKey(serverConfig: _serverConfig(), name: 'x', devices: 21),
        throwsA(isA<VpsException>()),
      );
    });

    test('negative days are rejected', () {
      expect(
        () => issueKey(serverConfig: _serverConfig(), name: 'x', days: -1),
        throwsA(isA<VpsException>()),
      );
    });

    test('server without a host is rejected', () {
      expect(
        () => issueKey(serverConfig: const ClientConfig(), name: 'x'),
        throwsA(isA<VpsException>()),
      );
    });

    test('IssuedKey survives a JSON round trip', () {
      final issued = issueKey(
        serverConfig: _serverConfig(),
        name: 'Phone',
        days: 30,
        devices: 3,
        serverId: 'srv-1',
        now: _now,
        random: Random(6),
      );
      final back = IssuedKey.fromJson(issued.toJson());
      expect(back.id, issued.id);
      expect(back.name, issued.name);
      expect(back.serverId, issued.serverId);
      expect(back.devices, issued.devices);
      expect(back.days, issued.days);
      expect(back.key, issued.key);
      expect(back.uri, issued.uri);
      expect(back.created, issued.created);
    });
  });
}
