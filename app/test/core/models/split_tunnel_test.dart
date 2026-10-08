import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/core/models/split_tunnel.dart';

List<String> _canonicals(List<SplitRule> rules) => [for (final rule in rules) rule.canonical];

void main() {
  group('SplitRuleParser: IPv4', () {
    test('single address becomes /32 host rule', () {
      final (rules, issues) = SplitRuleParser.parse('1.2.3.4');
      expect(issues, isEmpty);
      expect(rules.single, isA<SplitIpv4Rule>());
      expect(_canonicals(rules), ['1.2.3.4']);
    });

    test('CIDR is accepted and its address is masked', () {
      final (rules, issues) = SplitRuleParser.parse('10.1.2.3/8');
      expect(issues, isEmpty);
      expect(_canonicals(rules), ['10.0.0.0/8']);
    });

    test('prefix 0 and 32 are accepted', () {
      final (rules, issues) = SplitRuleParser.parse('0.0.0.0/0 9.9.9.9/32');
      expect(issues, isEmpty);
      expect(_canonicals(rules), ['0.0.0.0/0', '9.9.9.9']);
    });

    test('prefix above 32 is rejected with Russian reason', () {
      final (rules, issues) = SplitRuleParser.parse('10.0.0.0/33');
      expect(rules, isEmpty);
      expect(issues.single.input, '10.0.0.0/33');
      expect(issues.single.reasonRu, '«10.0.0.0/33»: маска IPv4 должна быть от 0 до 32');
    });

    test('non-numeric prefix is rejected', () {
      final (rules, issues) = SplitRuleParser.parse('10.0.0.0/x');
      expect(rules, isEmpty);
      expect(issues.single.reasonRu, '«10.0.0.0/x»: неверная маска подсети');
    });

    test('out-of-range octet is rejected as a domain with numeric TLD', () {
      final (rules, issues) = SplitRuleParser.parse('1.2.3.999');
      expect(rules, isEmpty);
      expect(issues.single.reasonRu, '«1.2.3.999»: неверный адрес или домен');
    });

    test('shortened dotted form is rejected', () {
      final (rules, issues) = SplitRuleParser.parse('10.1');
      expect(rules, isEmpty);
      expect(issues.single.reasonRu, '«10.1»: неверный адрес или домен');
    });

    test('leading zero in octet is rejected', () {
      final (rules, issues) = SplitRuleParser.parse('01.2.3.4');
      expect(rules, isEmpty);
      expect(issues, hasLength(1));
    });

    test('bad address in CIDR is rejected', () {
      final (rules, issues) = SplitRuleParser.parse('10.0.0/8');
      expect(rules, isEmpty);
      expect(issues.single.reasonRu, '«10.0.0/8»: неверный адрес подсети');
    });
  });

  group('SplitRuleParser: IPv6', () {
    test('compressed address is kept in canonical form', () {
      final (rules, issues) = SplitRuleParser.parse('2001:db8::1');
      expect(issues, isEmpty);
      expect(rules.single, isA<SplitIpv6Rule>());
      expect(_canonicals(rules), ['2001:db8::1']);
    });

    test('expanded address is compressed like inet_ntop', () {
      final (rules, _) = SplitRuleParser.parse('2001:0db8:0000:0000:0000:0000:0000:0001');
      expect(_canonicals(rules), ['2001:db8::1']);
    });

    test('first longest zero run is compressed', () {
      final (rules, _) = SplitRuleParser.parse('2001:db8:0:0:1:0:0:1');
      expect(_canonicals(rules), ['2001:db8::1:0:0:1']);
    });

    test('unspecified address parses', () {
      final (rules, issues) = SplitRuleParser.parse('::');
      expect(issues, isEmpty);
      expect(_canonicals(rules), ['::']);
    });

    test('IPv4-mapped tail is kept in dotted form', () {
      final (rules, _) = SplitRuleParser.parse('::ffff:1.2.3.4');
      expect(_canonicals(rules), ['::ffff:1.2.3.4']);
    });

    test('IPv6 prefix is masked', () {
      final (rules, issues) = SplitRuleParser.parse('2001:db8:abcd::/32');
      expect(issues, isEmpty);
      expect(rules.single, isA<SplitIpv6Rule>());
      expect(_canonicals(rules), ['2001:db8::/32']);
    });

    test('IPv6 prefix above 128 is rejected', () {
      final (rules, issues) = SplitRuleParser.parse('2001:db8::/129');
      expect(rules, isEmpty);
      expect(issues.single.reasonRu, '«2001:db8::/129»: маска IPv6 должна быть от 0 до 128');
    });

    test('triple colon is rejected', () {
      final (rules, issues) = SplitRuleParser.parse('2001:db8:::1');
      expect(rules, isEmpty);
      expect(issues, hasLength(1));
    });

    test('two compressions are rejected', () {
      final (rules, issues) = SplitRuleParser.parse('1::2::3');
      expect(rules, isEmpty);
      expect(issues, hasLength(1));
    });
  });

  group('SplitRuleParser: URLs and hosts', () {
    test('URL with path and port is reduced to host', () {
      final (rules, issues) = SplitRuleParser.parse('https://Example.com:8443/some/path');
      expect(issues, isEmpty);
      expect(_canonicals(rules), ['example.com']);
    });

    test('host with port is reduced to host', () {
      final (rules, _) = SplitRuleParser.parse('example.com:443');
      expect(_canonicals(rules), ['example.com']);
    });

    test('URL with IPv4 host and port keeps the address', () {
      final (rules, _) = SplitRuleParser.parse('http://1.2.3.4:8080/x');
      expect(rules.single, isA<SplitIpv4Rule>());
      expect(_canonicals(rules), ['1.2.3.4']);
    });

    test('bare path without scheme is rejected as a bad prefix, as in Swift', () {
      final (rules, issues) = SplitRuleParser.parse('example.com/path');
      expect(rules, isEmpty);
      expect(issues.single.reasonRu, '«example.com/path»: неверная маска подсети');
    });

    test('wildcard is rejected with hint', () {
      final (rules, issues) = SplitRuleParser.parse('*.ru');
      expect(rules, isEmpty);
      expect(issues.single.reasonRu, startsWith('«*.ru»: маски вроде *.ru на iOS не работают'));
    });

    test('Cyrillic domain is rejected and points to xn--', () {
      final (rules, issues) = SplitRuleParser.parse('пример.рф');
      expect(rules, isEmpty);
      expect(issues.single.reasonRu, contains('xn--'));
    });

    test('punycode domain is accepted', () {
      final (rules, issues) = SplitRuleParser.parse('xn--e1afmkfd.xn--p1ai');
      expect(issues, isEmpty);
      expect(_canonicals(rules), ['xn--e1afmkfd.xn--p1ai']);
    });

    test('domain with numeric TLD is rejected', () {
      final (rules, issues) = SplitRuleParser.parse('host.123');
      expect(rules, isEmpty);
      expect(issues.single.reasonRu, '«host.123»: неверный адрес или домен');
    });

    test('single label is rejected', () {
      final (rules, issues) = SplitRuleParser.parse('localhost');
      expect(rules, isEmpty);
      expect(issues, hasLength(1));
    });

    test('label starting with hyphen is rejected', () {
      final (rules, issues) = SplitRuleParser.parse('-bad.com');
      expect(rules, isEmpty);
      expect(issues, hasLength(1));
    });

    test('empty label is rejected', () {
      final (rules, issues) = SplitRuleParser.parse('a..b.com');
      expect(rules, isEmpty);
      expect(issues, hasLength(1));
    });

    test('label longer than 63 characters is rejected', () {
      final longLabel = 'a' * 64;
      final (rules, issues) = SplitRuleParser.parse('$longLabel.com');
      expect(rules, isEmpty);
      expect(issues, hasLength(1));
    });

    test('domain is lowercased and trailing dot is trimmed', () {
      final (rules, _) = SplitRuleParser.parse('WWW.Example.COM.');
      expect(_canonicals(rules), ['www.example.com']);
    });
  });

  group('SplitRuleParser: text splitting', () {
    test('comment lines and inline comments are skipped', () {
      const text = '''
# comment line
example.com
   # indented comment
t.me # trailing comment with words
''';
      final (rules, issues) = SplitRuleParser.parse(text);
      expect(issues, isEmpty);
      expect(_canonicals(rules), ['example.com', 't.me']);
    });

    test('newline, space, comma and semicolon separate entries', () {
      final (rules, issues) = SplitRuleParser.parse('a.com,b.com;c.com d.com\ne.com\r\nf.com');
      expect(issues, isEmpty);
      expect(_canonicals(rules), ['a.com', 'b.com', 'c.com', 'd.com', 'e.com', 'f.com']);
    });

    test('duplicates are removed and first order is kept', () {
      final (rules, issues) =
          SplitRuleParser.parse('example.com, EXAMPLE.com; 1.2.3.4 1.2.3.4 example.com');
      expect(issues, isEmpty);
      expect(_canonicals(rules), ['example.com', '1.2.3.4']);
    });

    test('CIDR duplicates are removed after masking', () {
      final (rules, _) = SplitRuleParser.parse('1.2.3.4/24 1.2.3.0/24');
      expect(_canonicals(rules), ['1.2.3.0/24']);
    });

    test('bad entries are reported without blocking good ones', () {
      final (rules, issues) = SplitRuleParser.parse('good.com *.bad.com 10.0.0.0/8');
      expect(_canonicals(rules), ['good.com', '10.0.0.0/8']);
      expect(issues.map((issue) => issue.input), ['*.bad.com']);
    });
  });

  group('SplitMode', () {
    test('wire values', () {
      expect(SplitMode.off.wire, 'off');
      expect(SplitMode.include.wire, 'include');
      expect(SplitMode.exclude.wire, 'exclude');
    });

    test('off aliases', () {
      expect(SplitMode.fromWire('off'), SplitMode.off);
      expect(SplitMode.fromWire('none'), SplitMode.off);
    });

    test('include aliases', () {
      for (final raw in ['include', 'only', 'only_selected', 'vpn_only']) {
        expect(SplitMode.fromWire(raw), SplitMode.include, reason: raw);
      }
    });

    test('exclude aliases', () {
      for (final raw in ['exclude', 'except', 'all_except', 'bypass_selected']) {
        expect(SplitMode.fromWire(raw), SplitMode.exclude, reason: raw);
      }
    });

    test('aliases ignore case and surrounding spaces', () {
      expect(SplitMode.fromWire('  EXCLUDE '), SplitMode.exclude);
    });

    test('unknown and null values give null', () {
      expect(SplitMode.fromWire('bogus'), isNull);
      expect(SplitMode.fromWire(''), isNull);
      expect(SplitMode.fromWire(null), isNull);
    });
  });

  group('SplitTunnelConfig JSON', () {
    test('toJson uses desktop keys and sorted presets', () {
      final config = SplitTunnelConfig(
        mode: SplitMode.include,
        entries: const ['example.com', '10.0.0.0/8'],
        presets: const {SplitPreset.telegram, SplitPreset.ru},
      );
      expect(config.toJson(), {
        'split_tunnel_mode': 'include',
        'split_sites': ['example.com', '10.0.0.0/8'],
        'split_presets': ['ru', 'telegram'],
      });
    });

    test('round trip through JSON text keeps the config', () {
      final config = SplitTunnelConfig(
        mode: SplitMode.exclude,
        entries: const ['example.com', '2001:db8::/32'],
        presets: const {SplitPreset.youtube, SplitPreset.local},
      );
      final decoded = SplitTunnelConfig.fromJson(
        jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>,
      );
      expect(decoded, config);
      expect(decoded.presets, config.presets);
    });

    test('unknown presets are dropped', () {
      final config = SplitTunnelConfig.fromJson({
        'split_tunnel_mode': 'exclude',
        'split_sites': <String>[],
        'split_presets': ['telegram', 'future_set'],
      });
      expect(config.presets, {SplitPreset.telegram});
    });

    test('missing or unknown mode falls back to off', () {
      expect(SplitTunnelConfig.fromJson({}).mode, SplitMode.off);
      expect(SplitTunnelConfig.fromJson({'split_tunnel_mode': 'weird'}).mode, SplitMode.off);
    });

    test('mode alias in JSON is accepted', () {
      final config = SplitTunnelConfig.fromJson({'split_tunnel_mode': 'vpn_only'});
      expect(config.mode, SplitMode.include);
    });

    test('copyWith changes only the given fields', () {
      final base = SplitTunnelConfig(mode: SplitMode.exclude, entries: const ['a.com']);
      final changed = base.copyWith(mode: SplitMode.include);
      expect(changed.mode, SplitMode.include);
      expect(changed.entries, ['a.com']);
      expect(base.mode, SplitMode.exclude);
    });

    test('lists inside the config are unmodifiable', () {
      final config = SplitTunnelConfig(entries: const ['a.com']);
      expect(() => config.entries.add('b.com'), throwsUnsupportedError);
    });
  });

  group('SplitTunnelConfig effective entries and summary', () {
    test('effectiveEntries joins user entries and presets without duplicates', () {
      final config = SplitTunnelConfig(
        mode: SplitMode.exclude,
        entries: const ['t.me', 'custom.org'],
        presets: const {SplitPreset.telegram},
      );
      final effective = config.effectiveEntries();
      expect(effective.first, 't.me');
      expect(effective.where((entry) => entry == 't.me'), hasLength(1));
      expect(effective, contains('custom.org'));
      expect(effective, contains('telegram.org'));
      expect(effective.length, SplitPreset.telegram.entries.length + 1);
    });

    test('summary for off mode', () {
      expect(SplitTunnelConfig(entries: const ['a.com']).summaryRu(), 'Выключен');
    });

    test('summary for exclude mode counts effective entries', () {
      final config = SplitTunnelConfig(
        mode: SplitMode.exclude,
        entries: const ['a.com', 'b.com'],
      );
      expect(config.summaryRu(), 'Исключений: 2');
    });

    test('summary for include mode counts effective entries', () {
      final config = SplitTunnelConfig(
        mode: SplitMode.include,
        entries: const ['a.com'],
        presets: const {SplitPreset.local},
      );
      expect(config.summaryRu(), 'Только список: ${1 + SplitPreset.local.entries.length}');
    });
  });

  group('SplitPreset', () {
    test('every preset has titles and entries', () {
      for (final preset in SplitPreset.values) {
        expect(preset.titleRu, isNotEmpty, reason: preset.name);
        expect(preset.titleEn, isNotEmpty, reason: preset.name);
        expect(preset.entries, isNotEmpty, reason: preset.name);
      }
    });

    test('wire values match desktop names', () {
      expect(SplitPreset.ru.wire, 'ru');
      expect(SplitPreset.local.wire, 'local');
      expect(SplitPreset.fromWire('telegram'), SplitPreset.telegram);
      expect(SplitPreset.fromWire('nope'), isNull);
    });

    test('every preset entry parses with zero issues', () {
      for (final preset in SplitPreset.values) {
        final (rules, issues) = SplitRuleParser.parse(preset.entries.join('\n'));
        expect(issues, isEmpty, reason: preset.name);
        expect(rules, isNotEmpty, reason: preset.name);
      }
    });
  });
}
