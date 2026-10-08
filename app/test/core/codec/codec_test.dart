import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/core/codec/base32.dart';
import 'package:obsidian_vpn/core/codec/client_config.dart';
import 'package:obsidian_vpn/core/codec/obsidian_key.dart';

/// Builds an OBSDN key from raw compact JSON, for error-case fixtures.
String obsdnFromRawJson(String json) {
  final compressed = ZLibCodec(level: 9)
      .encode(utf8.encode(json));
  final b32 = base32Encode(compressed);
  final groups = <String>[];
  for (var i = 0; i < b32.length; i += 4) {
    groups.add(b32.substring(i, i + 4 > b32.length ? b32.length : i + 4));
  }
  return 'OBSDN-${groups.join('-')}';
}

Map<String, dynamic> _asMap(Object? v) => v as Map<String, dynamic>;

void main() {
  final vectors = _asMap(
    jsonDecode(File('test/core/codec/vectors.json').readAsStringSync()),
  );
  final configs = (vectors['configs'] as List).cast<Map<String, dynamic>>();
  final parses = (vectors['parses'] as List).cast<Map<String, dynamic>>();

  group('base32', () {
    test('RFC 4648 vectors encode without padding', () {
      const cases = {
        '': '',
        'f': 'MY',
        'fo': 'MZXQ',
        'foo': 'MZXW6',
        'foob': 'MZXW6YQ',
        'fooba': 'MZXW6YTB',
        'foobar': 'MZXW6YTBOI',
      };
      cases.forEach((plain, encoded) {
        expect(base32Encode(utf8.encode(plain)), encoded, reason: plain);
      });
    });

    test('RFC 4648 vectors decode, with or without padding', () {
      expect(utf8.decode(base32Decode('MZXW6YTBOI')), 'foobar');
      expect(utf8.decode(base32Decode('MZXW6YTB')), 'fooba');
      expect(utf8.decode(base32Decode('MZXW6YQ=')), 'foob');
      expect(utf8.decode(base32Decode('MY======')), 'f');
      expect(base32Decode('').length, 0);
    });

    test('decode is case-insensitive and ignores dashes and whitespace', () {
      expect(utf8.decode(base32Decode('mzxw6ytboi')), 'foobar');
      expect(utf8.decode(base32Decode('MZXW-6YTB\nOI')), 'foobar');
      expect(utf8.decode(base32Decode(' mzxw 6ytb\toi ')), 'foobar');
    });

    test('random round trip', () {
      final rnd = Random(42);
      for (var len = 0; len < 64; len++) {
        final bytes = List<int>.generate(len, (_) => rnd.nextInt(256));
        expect(base32Decode(base32Encode(bytes)), bytes, reason: 'len=$len');
      }
    });

    test('invalid character and impossible length throw FormatException', () {
      expect(() => base32Decode('MZXW1'), throwsFormatException);
      expect(() => base32Decode('M'), throwsFormatException);
      expect(() => base32Decode('MZXW6Y'), throwsFormatException);
      expect(() => base32Decode('MZXW!'), throwsFormatException);
    });
  });

  group('ClientConfig JSON', () {
    test('fromJson then toJson reproduces Go json.Marshal output', () {
      for (final v in configs) {
        final go = _asMap(v['config']);
        expect(ClientConfig.fromJson(go).toJson(), go, reason: v['name'] as String);
      }
    });

    test('omitempty: zero values are dropped, the four untagged fields stay', () {
      const c = ClientConfig(serverHost: 'h.example', serverPort: '443');
      expect(c.toJson(), {
        'protocol_version': 0,
        'server_host': 'h.example',
        'server_port': '443',
        'server_public_key': '',
      });
    });

    test('copyWith changes only the given fields', () {
      final base = ClientConfig.fromJson(_asMap(configs.first['config']));
      final changed = base.copyWith(token: 'new', maxDevices: 7, mtu: 1200);
      expect(changed.token, 'new');
      expect(changed.maxDevices, 7);
      expect(changed.mtu, 1200);
      expect(changed.serverHost, base.serverHost);
      expect(changed.signatures, base.signatures);
      expect(base.token, isNot('new'));
    });
  });

  group('parseKey', () {
    test('parses every Go-generated URI and OBSDN key like Go decodes them', () {
      for (final v in configs) {
        final name = v['name'] as String;
        expect(parseKey(v['uri'] as String).toJson(), _asMap(v['decoded_uri']),
            reason: '$name uri');
        expect(parseKey(v['obsdn'] as String).toJson(),
            _asMap(v['decoded_obsdn']),
            reason: '$name obsdn');
      }
    });

    test('parses Go vectors for vpn://, vpn://obsidian/, and legacy aliases', () {
      for (final p in parses) {
        expect(parseKey(p['input'] as String).toJson(),
            _asMap(p['expected']),
            reason: p['name'] as String);
      }
    });

    test('vpn://obsidian/ and vpn:// forms match the obsidian:// form', () {
      final uri = configs.first['uri'] as String;
      final rest = uri.substring('obsidian://'.length);
      final expected = parseKey(uri).toJson();
      expect(parseKey('vpn://$rest').toJson(), expected);
      expect(parseKey('vpn://obsidian/$rest').toJson(), expected);
      expect(parseKey('VPN://$rest').toJson(), expected);
    });

    test('tolerates surrounding whitespace, line breaks and lowercase OBSDN', () {
      final v = configs[1];
      final key = v['obsdn'] as String;
      final noDashes = key.replaceFirst('OBSDN-', '').replaceAll('-', '');
      final wrapped = key.replaceAllMapped(
        RegExp(r'(.{20})'),
        (m) => '${m[1]}\n',
      );
      final expected = _asMap(v['decoded_obsdn']);
      expect(parseKey('  $key  ').toJson(), expected);
      expect(parseKey(wrapped).toJson(), expected);
      expect(parseKey(key.toLowerCase()).toJson(), expected);
      expect(parseKey(noDashes).toJson(), expected);
      expect(parseKey('  ${v['uri']}\r\n').toJson(), _asMap(v['decoded_uri']));
    });
  });

  group('encodeUri', () {
    test('matches Go EncodeURI byte for byte (IPv6 bracket fix applied)', () {
      for (final v in configs) {
        final c = ClientConfig.fromJson(_asMap(v['config']));
        expect(encodeUri(c), v['uri'] as String, reason: v['name'] as String);
      }
    });

    test('round-trips through parseKey to the Go-decoded config', () {
      for (final v in configs) {
        final c = ClientConfig.fromJson(_asMap(v['config']));
        expect(parseKey(encodeUri(c)).toJson(), _asMap(v['decoded_uri']),
            reason: v['name'] as String);
      }
    });

    test('label argument overrides the config label', () {
      final c = ClientConfig.fromJson(_asMap(configs[0]['config']));
      final uri = encodeUri(c, label: 'Сервер 1');
      expect(uri.endsWith('#%D0%A1%D0%B5%D1%80%D0%B2%D0%B5%D1%80%201'), isTrue);
      expect(parseKey(uri).label, 'Сервер 1');
    });
  });

  group('encodeObsdn', () {
    test('compact payload matches the Go-generated compact JSON exactly', () {
      for (final v in configs) {
        final c = ClientConfig.fromJson(_asMap(v['config']));
        expect(obsdnCompactJson(c), v['compact_json'] as String,
            reason: v['name'] as String);
      }
    });

    test('key decodes to the same config Go decodes from its own key', () {
      for (final v in configs) {
        final c = ClientConfig.fromJson(_asMap(v['config']));
        expect(parseKey(encodeObsdn(c)).toJson(), _asMap(v['decoded_obsdn']),
            reason: v['name'] as String);
      }
    });

    test('key has OBSDN prefix and 4-char groups of base32 alphabet', () {
      final key = encodeObsdn(ClientConfig.fromJson(_asMap(configs[1]['config'])));
      expect(key.startsWith('OBSDN-'), isTrue);
      expect(RegExp(r'^OBSDN-([A-Z2-7]{4}-)*[A-Z2-7]{1,4}$').hasMatch(key), isTrue);
    });
  });

  group('KeyFormatException', () {
    final bad = <String, String>{
      'empty': '',
      'whitespace only': '   \n ',
      'garbage': 'garbage',
      'unsupported scheme': 'http://example.com',
      'no host': 'obsidian://',
      'vpn without host': 'vpn://',
      'no public key': 'obsidian://203.0.113.10:443',
      'bad port': 'obsidian://3f8a@host:12x4',
      'wrong prefix': 'OBSDX-PDND-ZSGR',
    };
    bad.forEach((name, input) {
      test('throws for $name', () {
        expect(() => parseKey(input), throwsA(isA<KeyFormatException>()));
      });
    });

    test('corrupted base32 (invalid character) throws', () {
      final key = configs[0]['obsdn'] as String;
      final broken = '${key.substring(0, 12)}!${key.substring(13)}';
      expect(() => parseKey(broken), throwsA(isA<KeyFormatException>()));
    });

    test('truncated key throws', () {
      final key = configs[0]['obsdn'] as String;
      expect(() => parseKey(key.substring(0, key.length - 9)),
          throwsA(isA<KeyFormatException>()));
    });

    test('flipped character in the zlib payload throws', () {
      final key = configs[1]['obsdn'] as String;
      final pos = key.length ~/ 2;
      final original = key[pos];
      final replacement = original == 'A' ? 'B' : 'A';
      final broken = key.substring(0, pos) + replacement + key.substring(pos + 1);
      expect(() => parseKey(broken), throwsA(isA<KeyFormatException>()));
    });

    test('OBSDN payload that is not zlib throws', () {
      final raw = base32Encode(utf8.encode('{"h":"x"}'));
      expect(() => parseKey('OBSDN-$raw'), throwsA(isA<KeyFormatException>()));
    });

    test('OBSDN payload missing a required field throws', () {
      final key = obsdnFromRawJson('{"h":"203.0.113.10","p":"443","u":"443"}');
      expect(() => parseKey(key), throwsA(isA<KeyFormatException>()));
    });

    test('OBSDN payload that is not a JSON object throws', () {
      expect(() => parseKey(obsdnFromRawJson('[1,2,3]')),
          throwsA(isA<KeyFormatException>()));
    });

    test('messages are Russian and free of dashes', () {
      for (final input in ['', 'garbage', 'obsidian://']) {
        try {
          parseKey(input);
          fail('expected KeyFormatException for "$input"');
        } on KeyFormatException catch (e) {
          expect(e.messageRu, isNotEmpty);
          expect(e.messageRu.contains('—'), isFalse);
          expect(e.messageRu.contains('–'), isFalse);
          expect(RegExp(r'[А-Яа-яЁё]').hasMatch(e.messageRu), isTrue);
        }
      }
    });
  });

  group('keyPreview', () {
    test('host:port, bracketed for IPv6', () {
      expect(keyPreview(const ClientConfig(serverHost: 'a.example', serverPort: '443')),
          'a.example:443');
      expect(keyPreview(const ClientConfig(serverHost: '2001:db8::1', serverPort: '8443')),
          '[2001:db8::1]:8443');
      expect(keyPreview(const ClientConfig(serverHost: 'a.example')), 'a.example:8443');
    });
  });

  group('buildRuntimeConfig', () {
    test('tun address derivation matches the SHA-256 formula', () {
      // sha256("profile-1") starts 0x50135a42 -> host 2 + n % 253 = 139
      expect(deriveTunAddress('profile-1'), '10.8.0.139/24');
      // sha256("abc") starts 0xba7816bf -> host 36
      expect(deriveTunAddress('abc'), '10.8.0.36/24');
    });

    test('applies derivations and keeps the client keypair', () {
      final base = ClientConfig.fromJson(_asMap(configs[0]['config']));
      final out = buildRuntimeConfig(
        base.copyWith(tunAddress: '', dns: '10.8.0.1', mtu: 9000),
        profileId: 'profile-1',
        clientPrivateKeyHex: 'aa' * 32,
        clientPublicKeyHex: 'bb' * 32,
      );
      expect(out.tunAddress, '10.8.0.139/24');
      expect(out.dns, '1.1.1.1');
      expect(out.mtu, 1420);
      expect(out.clientPrivateKey, 'aa' * 32);
      expect(out.clientPublicKey, 'bb' * 32);
      expect(out.serverHost, base.serverHost);
    });

    test('keeps a custom tun address and the 1.1.1.1 DNS', () {
      final base = ClientConfig.fromJson(_asMap(configs[0]['config']));
      final out = buildRuntimeConfig(
        base.copyWith(tunAddress: '10.9.0.5/24', dns: '1.1.1.1'),
        profileId: 'profile-1',
        clientPrivateKeyHex: 'aa' * 32,
        clientPublicKeyHex: 'bb' * 32,
      );
      expect(out.tunAddress, '10.9.0.5/24');
      expect(out.dns, '1.1.1.1');
    });

    test('treats the default 10.8.0.2/24 tun address as unset', () {
      final base = ClientConfig.fromJson(_asMap(configs[0]['config']))
          .copyWith(tunAddress: '10.8.0.2/24');
      final out = buildRuntimeConfig(
        base,
        profileId: 'abc',
        clientPrivateKeyHex: 'aa' * 32,
        clientPublicKeyHex: 'bb' * 32,
      );
      expect(out.tunAddress, '10.8.0.36/24');
    });
  });

  group('generateClientKeypair', () {
    test('returns two 64-char lowercase hex keys that match each other', () async {
      final (priv, pub) = await generateClientKeypair();
      final hex = RegExp(r'^[0-9a-f]{64}$');
      expect(hex.hasMatch(priv), isTrue);
      expect(hex.hasMatch(pub), isTrue);
      expect(priv == pub, isFalse);

      final seed = <int>[
        for (var i = 0; i < 64; i += 2) int.parse(priv.substring(i, i + 2), radix: 16),
      ];
      final kp = await X25519().newKeyPairFromSeed(seed);
      final derived = (await kp.extractPublicKey()).bytes;
      final derivedHex =
          derived.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(derivedHex, pub);
    });

    test('two calls produce different keys', () async {
      final a = await generateClientKeypair();
      final b = await generateClientKeypair();
      expect(a.$1 == b.$1, isFalse);
    });
  });
}
