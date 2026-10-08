import 'dart:convert';
import 'dart:io';

/// Returns the `input` of the parse vector called [name] in
/// test/core/codec/vectors.json. Tests run from the package root.
String parseVectorInput(String name) {
  final json = jsonDecode(
    File('test/core/codec/vectors.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final parses = json['parses'] as List<dynamic>;
  for (final entry in parses) {
    final vector = entry as Map<String, dynamic>;
    if (vector['name'] == name) return vector['input'] as String;
  }
  throw StateError('no parse vector named $name');
}

/// A valid key with host legacy.example.net, port 8443.
String keyLegacyHost() => parseVectorInput('obsidian_legacy_aliases_no_port');

/// A valid key with host host.example, port 8443.
String keyOtherHost() =>
    parseVectorInput('obsidian_pk_query_overrides_userinfo_and_plus_in_label');
