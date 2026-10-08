import 'dart:math';

import 'package:obsidian_vpn/core/codec/client_config.dart';
import 'package:obsidian_vpn/core/codec/obsidian_key.dart';
import 'package:obsidian_vpn/vps/deploy_scripts.dart';
import 'package:obsidian_vpn/vps/vps_models.dart';

/// Max MTU written into keys (desktop keys.rs SAFE_MTU).
const int kSafeMtu = 1420;
const int kMinKeyDevices = 1;
const int kMaxKeyDevices = 20;

/// Longest key name. The name is part of the key and its QR code, which must stay scannable.
const int kMaxKeyNameLength = 40;

/// A key issued for one client of our own server.
class IssuedKey {
  const IssuedKey({
    required this.id,
    required this.name,
    required this.serverId,
    required this.devices,
    required this.days,
    required this.key,
    required this.uri,
    required this.created,
  });

  factory IssuedKey.fromJson(Map<String, dynamic> json) {
    return IssuedKey(
      id: json['id'] as String,
      name: json['name'] as String,
      serverId: json['serverId'] as String,
      devices: (json['devices'] as num).toInt(),
      days: (json['days'] as num).toInt(),
      key: json['key'] as String,
      uri: json['uri'] as String,
      created: DateTime.parse(json['created'] as String),
    );
  }

  final String id;
  final String name;
  final String serverId;
  final int devices;

  /// 0 means no expiry.
  final int days;

  /// OBSDN-XXXX key (the payload carries expiry and device limit).
  final String key;

  /// obsidian:// URI with label, expiry and device limit.
  final String uri;
  final DateTime created;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'serverId': serverId,
        'devices': devices,
        'days': days,
        'key': key,
        'uri': uri,
        'created': created.toUtc().toIso8601String(),
      };
}

/// Issues a key for [serverConfig] (the server's ClientConfig, as in
/// DeployResult.ownerConfig). Mirrors desktop lib.rs issue_key:
/// the expiry is `days` from now (date only, UTC, 0 means none), the device limit is
/// [devices], MTU is capped at [kSafeMtu], and the key carries no client private key.
///
/// Throws [VpsException] for out-of-range input.
IssuedKey issueKey({
  required ClientConfig serverConfig,
  required String name,
  int days = 0,
  int devices = 1,
  String? serverId,
  DateTime? now,
  Random? random,
}) {
  if (devices < kMinKeyDevices || devices > kMaxKeyDevices) {
    throw const VpsException('Количество устройств должно быть от 1 до 20.');
  }
  if (days < 0) {
    throw const VpsException('Срок действия не может быть отрицательным.');
  }
  if (serverConfig.serverHost.trim().isEmpty) {
    throw const VpsException('В конфигурации сервера нет адреса.');
  }

  final created = (now ?? DateTime.now()).toUtc();
  final expires = days == 0 ? '' : _isoDate(created.add(Duration(days: days)));
  final trimmedName = String.fromCharCodes(name.trim().runes.take(kMaxKeyNameLength)).trim();
  final label = trimmedName.isEmpty ? 'Guest' : trimmedName;
  final realityOn =
      serverConfig.realityEnabled || serverConfig.realityAuthKey.isNotEmpty;

  final config = serverConfig.copyWith(
    clientPrivateKey: '',
    clientPublicKey: '',
    token: '',
    expires: expires,
    maxDevices: devices,
    mtu: kSafeMtu,
    realityEnabled: realityOn,
    label: label,
  );

  return IssuedKey(
    id: _uuidV4(random ?? Random.secure()),
    name: label,
    serverId: serverId ?? '${serverConfig.serverHost}:${serverConfig.serverPort}',
    devices: devices,
    days: days,
    key: encodeObsdn(config),
    uri: encodeUri(config, label: label),
    created: created,
  );
}

String _isoDate(DateTime utc) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-${two(utc.day)}';
}

String _uuidV4(Random rng) {
  final b = List<int>.generate(16, (_) => rng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = hexEncode(b);
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
