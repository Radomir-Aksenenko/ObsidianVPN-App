// Раздельное туннелирование для одного профиля (порт ios/Shared/SplitTunnelConfig.swift).
// Ключи JSON совпадают с desktop-профилем: split_tunnel_mode, split_sites, split_presets.
// Файл содержит только данные и разбор строк, без сетевых вызовов.

import 'split_presets.dart';

export 'split_presets.dart';

/// Режим раздельного туннелирования.
enum SplitMode {
  /// Раздельного туннелирования нет: весь трафик идет через VPN.
  off,

  /// Через VPN идет только трафик к перечисленным сайтам и адресам.
  include,

  /// Через VPN идет весь трафик, кроме перечисленных сайтов и адресов.
  exclude;

  /// Значение для JSON (split_tunnel_mode).
  String get wire => name;

  /// Разбирает значение режима, включая алиасы из Go-ядра (core/cmd/client/split_tunnel.go).
  /// Возвращает null для пустого или неизвестного значения.
  static SplitMode? fromWire(String? raw) {
    if (raw == null) return null;
    switch (raw.trim().toLowerCase()) {
      case 'off':
      case 'none':
        return SplitMode.off;
      case 'include':
      case 'only':
      case 'only_selected':
      case 'vpn_only':
        return SplitMode.include;
      case 'exclude':
      case 'except':
      case 'all_except':
      case 'bypass_selected':
        return SplitMode.exclude;
      default:
        return null;
    }
  }
}

/// Правило после разбора строки.
sealed class SplitRule {
  const SplitRule();

  /// Каноническая запись, которая попадает в список и в JSON.
  String get canonical;

  @override
  bool operator ==(Object other) =>
      other is SplitRule &&
      other.runtimeType == runtimeType &&
      other.canonical == canonical;

  @override
  int get hashCode => Object.hash(runtimeType, canonical);

  @override
  String toString() => canonical;
}

/// IPv4-адрес или CIDR.
final class SplitIpv4Rule extends SplitRule {
  const SplitIpv4Rule(this.network);

  final IPv4Network network;

  @override
  String get canonical => network.cidrString;
}

/// IPv6-адрес или CIDR.
final class SplitIpv6Rule extends SplitRule {
  const SplitIpv6Rule(this.network);

  final IPv6Network network;

  @override
  String get canonical => network.cidrString;
}

/// Доменное имя (ASCII, в нижнем регистре).
final class SplitDomainRule extends SplitRule {
  const SplitDomainRule(this.domain);

  final String domain;

  @override
  String get canonical => domain;
}

/// Строка, которую не удалось принять, и причина для показа пользователю.
final class SplitIssue {
  const SplitIssue({required this.input, required this.reasonRu});

  final String input;
  final String reasonRu;

  @override
  bool operator ==(Object other) =>
      other is SplitIssue &&
      other.input == input &&
      other.reasonRu == reasonRu;

  @override
  int get hashCode => Object.hash(input, reasonRu);

  @override
  String toString() => 'SplitIssue($input: $reasonRu)';
}

/// Ошибка разбора одной строки. Текст уже на русском.
final class SplitRuleException implements Exception {
  const SplitRuleException(this.reasonRu);

  final String reasonRu;

  @override
  String toString() => reasonRu;
}

/// IPv4-сеть. Адрес хранится как uint32, биты за пределами префикса обнулены.
final class IPv4Network {
  IPv4Network._(this.address, this.prefix);

  factory IPv4Network({required int address, required int prefix}) {
    final clamped = prefix < 0 ? 0 : (prefix > 32 ? 32 : prefix);
    return IPv4Network._(address & maskFor(clamped), clamped);
  }

  /// Адрес сети (uint32, порядок байтов от старшего).
  final int address;
  final int prefix;

  static int maskFor(int prefix) {
    if (prefix <= 0) return 0;
    return (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
  }

  int get mask => maskFor(prefix);

  String get addressString => dotted(address);

  String get cidrString => prefix == 32 ? addressString : '$addressString/$prefix';

  static String dotted(int value) {
    final a = (value >> 24) & 0xFF;
    final b = (value >> 16) & 0xFF;
    final c = (value >> 8) & 0xFF;
    final d = value & 0xFF;
    return '$a.$b.$c.$d';
  }

  @override
  bool operator ==(Object other) =>
      other is IPv4Network && other.address == address && other.prefix == prefix;

  @override
  int get hashCode => Object.hash(address, prefix);

  @override
  String toString() => cidrString;
}

/// IPv6-сеть. Хранит 16 байт, биты за пределами префикса обнулены.
final class IPv6Network {
  IPv6Network._(this.bytes, this.prefix);

  factory IPv6Network({required List<int> bytes, required int prefix}) {
    final clamped = prefix < 0 ? 0 : (prefix > 128 ? 128 : prefix);
    final masked = List<int>.generate(16, (index) {
      final byte = index < bytes.length ? bytes[index] : 0;
      final bitsKept = clamped - index * 8;
      if (bitsKept >= 8) return byte;
      if (bitsKept <= 0) return 0;
      return byte & ((0xFF << (8 - bitsKept)) & 0xFF);
    });
    return IPv6Network._(List.unmodifiable(masked), clamped);
  }

  final List<int> bytes;
  final int prefix;

  String get addressString => SplitRuleParser._formatIpv6(bytes);

  String get cidrString => prefix == 128 ? addressString : '$addressString/$prefix';

  @override
  bool operator ==(Object other) {
    if (other is! IPv6Network || other.prefix != prefix) return false;
    for (var i = 0; i < 16; i++) {
      if (other.bytes[i] != bytes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(prefix, Object.hashAll(bytes));

  @override
  String toString() => cidrString;
}

/// Разбор строк правил. Грамматика повторяет SplitRuleParser из Swift.
abstract final class SplitRuleParser {
  static final RegExp _lineBreak = RegExp(r'\r\n|\r|\n');
  static final RegExp _separator = RegExp(r'[\s,;]+');
  static final RegExp _octet = RegExp(r'^(0|[1-9][0-9]{0,2})$');
  static final RegExp _hextet = RegExp(r'^[0-9a-fA-F]{1,4}$');
  static final RegExp _digitsOnly = RegExp(r'^[0-9]+$');
  static final RegExp _label = RegExp(r'^[a-z0-9-]{1,63}$');
  static final RegExp _dotEdges = RegExp(r'^\.+|\.+$');

  /// Разбирает текст, введенный пользователем: строки, а внутри строки пробелы, запятые и точки с запятой.
  /// Строка, начинающаяся с '#', и все после '#' в токене пропускаются.
  /// Возвращает принятые правила без дублей (в порядке первого появления) и список отказов.
  static (List<SplitRule> rules, List<SplitIssue> issues) parse(String text) {
    final rules = <SplitRule>[];
    final issues = <SplitIssue>[];
    final seen = <String>{};

    for (final line in text.split(_lineBreak)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      for (final token in trimmed.split(_separator)) {
        if (token.isEmpty) continue;
        if (token.startsWith('#')) break;
        try {
          final rule = parseEntry(token);
          if (rule != null && seen.add(rule.canonical)) rules.add(rule);
        } on SplitRuleException catch (error) {
          issues.add(SplitIssue(input: token, reasonRu: error.reasonRu));
        }
      }
    }
    return (rules, issues);
  }

  /// Разбирает одну строку без разбиения на токены.
  /// Возвращает null для пустой строки и комментария. Бросает SplitRuleException при отказе.
  static SplitRule? parseEntry(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty || value.startsWith('#')) return null;

    final slash = value.indexOf('/');
    if (slash >= 0 && !value.contains('://')) {
      final addressPart = value.substring(0, slash);
      final prefix = int.tryParse(value.substring(slash + 1));
      if (prefix == null) {
        throw _error(raw, 'неверная маска подсети');
      }
      final v4 = _parseIpv4(addressPart);
      if (v4 != null) {
        if (prefix < 0 || prefix > 32) {
          throw _error(raw, 'маска IPv4 должна быть от 0 до 32');
        }
        return SplitIpv4Rule(IPv4Network(address: v4, prefix: prefix));
      }
      final v6 = _parseIpv6(addressPart);
      if (v6 != null) {
        if (prefix < 0 || prefix > 128) {
          throw _error(raw, 'маска IPv6 должна быть от 0 до 128');
        }
        return SplitIpv6Rule(IPv6Network(bytes: v6, prefix: prefix));
      }
      throw _error(raw, 'неверный адрес подсети');
    }

    final wholeV6 = _parseIpv6(value);
    if (wholeV6 != null) {
      return SplitIpv6Rule(IPv6Network(bytes: wholeV6, prefix: 128));
    }

    // Ссылки и адреса с портом: оставляем только имя хоста.
    var host = value;
    final scheme = host.indexOf('://');
    if (scheme >= 0) host = host.substring(scheme + 3);
    final pathStart = host.indexOf('/');
    if (pathStart >= 0) host = host.substring(0, pathStart);
    final colon = host.indexOf(':');
    if (colon >= 0) host = host.substring(0, colon);
    host = host.replaceAll(_dotEdges, '');

    final hostV4 = _parseIpv4(host);
    if (hostV4 != null) {
      return SplitIpv4Rule(IPv4Network(address: hostV4, prefix: 32));
    }

    if (host.contains('*')) {
      throw _error(raw, 'маски вроде *.ru на iOS не работают, добавьте сайты по одному');
    }
    if (host.isEmpty || host.length > 253) {
      throw _error(raw, 'неверный адрес или домен');
    }
    if (host.codeUnits.any((unit) => unit > 127)) {
      throw _error(raw, 'кириллические домены пока не поддерживаются, укажите вариант xn--');
    }

    final labels = host.split('.');
    if (labels.length < 2 || !labels.every(_isValidLabel)) {
      throw _error(raw, 'неверный адрес или домен');
    }
    // Зона верхнего уровня не может быть числом: так отсекаются записи вроде 1.2.3.999.
    if (_digitsOnly.hasMatch(labels.last)) {
      throw _error(raw, 'неверный адрес или домен');
    }
    return SplitDomainRule(host);
  }

  static SplitRuleException _error(String raw, String reason) =>
      SplitRuleException('«$raw»: $reason');

  static bool _isValidLabel(String label) {
    if (!_label.hasMatch(label)) return false;
    return !label.startsWith('-') && !label.endsWith('-');
  }

  /// Строгий dotted-quad как inet_pton(AF_INET): ровно четыре октета, без ведущих нулей.
  static int? _parseIpv4(String text) {
    final parts = text.split('.');
    if (parts.length != 4) return null;
    var value = 0;
    for (final part in parts) {
      if (!_octet.hasMatch(part)) return null;
      final octet = int.parse(part);
      if (octet > 255) return null;
      value = (value << 8) | octet;
    }
    return value;
  }

  /// IPv6 как inet_pton(AF_INET6): сжатие "::" не более одного раза, допускается хвост из IPv4.
  static List<int>? _parseIpv6(String text) {
    if (!text.contains(':')) return null;

    var source = text;
    final lastColon = source.lastIndexOf(':');
    final tail = source.substring(lastColon + 1);
    if (tail.contains('.')) {
      final v4 = _parseIpv4(tail);
      if (v4 == null) return null;
      final high = ((v4 >> 16) & 0xFFFF).toRadixString(16);
      final low = (v4 & 0xFFFF).toRadixString(16);
      source = '${source.substring(0, lastColon + 1)}$high:$low';
    }

    final pieces = source.split('::');
    if (pieces.length > 2) return null;
    final head = _hextets(pieces[0]);
    if (head == null) return null;

    if (pieces.length == 1) {
      if (head.length != 8) return null;
      return _toBytes(head);
    }

    final tailWords = _hextets(pieces[1]);
    if (tailWords == null) return null;
    final missing = 8 - head.length - tailWords.length;
    // "::" обязано заменять хотя бы одну группу.
    if (missing < 1) return null;
    return _toBytes([...head, ...List<int>.filled(missing, 0), ...tailWords]);
  }

  static List<int>? _hextets(String part) {
    if (part.isEmpty) return <int>[];
    final words = <int>[];
    for (final group in part.split(':')) {
      if (!_hextet.hasMatch(group)) return null;
      words.add(int.parse(group, radix: 16));
    }
    return words;
  }

  static List<int> _toBytes(List<int> words) {
    final bytes = <int>[];
    for (final word in words) {
      bytes
        ..add((word >> 8) & 0xFF)
        ..add(word & 0xFF);
    }
    return bytes;
  }

  /// Каноническая запись IPv6 как inet_ntop: нижний регистр, самая длинная серия нулей (от 2 групп) сжата.
  static String _formatIpv6(List<int> bytes) {
    final words = List<int>.generate(8, (i) => (bytes[i * 2] << 8) | bytes[i * 2 + 1]);

    var bestBase = -1;
    var bestLen = 0;
    var index = 0;
    while (index < 8) {
      if (words[index] != 0) {
        index++;
        continue;
      }
      var end = index;
      while (end < 8 && words[end] == 0) {
        end++;
      }
      if (end - index > bestLen) {
        bestBase = index;
        bestLen = end - index;
      }
      index = end;
    }
    if (bestLen < 2) bestBase = -1;

    String dottedTail() => '${bytes[12]}.${bytes[13]}.${bytes[14]}.${bytes[15]}';
    if (bestBase == 0 && bestLen == 6) return '::${dottedTail()}';
    if (bestBase == 0 && bestLen == 5 && words[5] == 0xFFFF) {
      return '::ffff:${dottedTail()}';
    }

    String hex(int word) => word.toRadixString(16);
    if (bestBase < 0) return words.map(hex).join(':');

    final head = words.sublist(0, bestBase).map(hex).join(':');
    final rest = words.sublist(bestBase + bestLen).map(hex).join(':');
    return '$head::$rest';
  }
}

/// Все правила (пользовательские и из наборов): настройки профиля.
/// Объект неизменяемый, изменения делаются через copyWith.
final class SplitTunnelConfig {
  SplitTunnelConfig({
    this.mode = SplitMode.off,
    List<String> entries = const <String>[],
    Set<SplitPreset> presets = const <SplitPreset>{},
  })  : entries = List<String>.unmodifiable(entries),
        presets = Set<SplitPreset>.unmodifiable(presets);

  final SplitMode mode;

  /// Пользовательские строки: домены, IP или CIDR.
  final List<String> entries;

  /// Выбранные готовые наборы.
  final Set<SplitPreset> presets;

  SplitTunnelConfig copyWith({
    SplitMode? mode,
    List<String>? entries,
    Set<SplitPreset>? presets,
  }) {
    return SplitTunnelConfig(
      mode: mode ?? this.mode,
      entries: entries ?? this.entries,
      presets: presets ?? this.presets,
    );
  }

  /// Пользовательские строки, затем строки выбранных наборов в фиксированном порядке. Дубли убираются.
  List<String> effectiveEntries() {
    final seen = <String>{};
    final result = <String>[];
    final candidates = <String>[
      ...entries,
      for (final preset in SplitPreset.values)
        if (presets.contains(preset)) ...preset.entries,
    ];
    for (final candidate in candidates) {
      if (seen.add(candidate)) result.add(candidate);
    }
    return result;
  }

  /// Короткая подпись для списка профилей.
  String summaryRu() {
    switch (mode) {
      case SplitMode.off:
        return 'Выключен';
      case SplitMode.exclude:
        return 'Исключений: ${effectiveEntries().length}';
      case SplitMode.include:
        return 'Только список: ${effectiveEntries().length}';
    }
  }

  Map<String, dynamic> toJson() {
    final presetWires = [for (final preset in presets) preset.wire]..sort();
    return <String, dynamic>{
      'split_tunnel_mode': mode.wire,
      'split_sites': List<String>.of(entries),
      'split_presets': presetWires,
    };
  }

  factory SplitTunnelConfig.fromJson(Map<String, dynamic> json) {
    final rawMode = json['split_tunnel_mode'];
    final mode = (rawMode is String ? SplitMode.fromWire(rawMode) : null) ?? SplitMode.off;

    final rawEntries = json['split_sites'];
    final entries = rawEntries is List
        ? rawEntries.whereType<String>().toList()
        : <String>[];

    // Неизвестные наборы из будущих версий пропускаются, а не ломают профиль целиком.
    final rawPresets = json['split_presets'];
    final presets = rawPresets is List
        ? rawPresets
            .whereType<String>()
            .map(SplitPreset.fromWire)
            .whereType<SplitPreset>()
            .toSet()
        : <SplitPreset>{};

    return SplitTunnelConfig(mode: mode, entries: entries, presets: presets);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SplitTunnelConfig &&
        other.mode == mode &&
        _listEquals(other.entries, entries) &&
        _setEquals(other.presets, presets);
  }

  @override
  int get hashCode => Object.hash(mode, Object.hashAll(entries), Object.hashAllUnordered(presets));

  @override
  String toString() => 'SplitTunnelConfig(${toJson()})';

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _setEquals(Set<SplitPreset> a, Set<SplitPreset> b) =>
      a.length == b.length && a.containsAll(b);
}
