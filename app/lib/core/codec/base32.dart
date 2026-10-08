import 'dart:typed_data';

const String _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/// Encodes [bytes] as RFC 4648 base32 (uppercase) without '=' padding.
String base32Encode(List<int> bytes) {
  final out = StringBuffer();
  var buffer = 0;
  var bits = 0;
  for (final b in bytes) {
    buffer = (buffer << 8) | (b & 0xff);
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      out.write(_alphabet[(buffer >> bits) & 0x1f]);
    }
    buffer &= (1 << bits) - 1;
  }
  if (bits > 0) {
    out.write(_alphabet[(buffer << (5 - bits)) & 0x1f]);
  }
  return out.toString();
}

/// Decodes RFC 4648 base32.
///
/// Case-insensitive. ASCII whitespace and '-' are ignored. Trailing '=' padding
/// is accepted but not required. Non-zero trailing bits are ignored, matching
/// Go's default base32 decoder. Throws [FormatException] on characters outside
/// the alphabet or on an impossible length (1, 3 or 6 characters mod 8).
Uint8List base32Decode(String input) {
  final cleaned = input
      .replaceAll(RegExp(r'[\s-]'), '')
      .toUpperCase()
      .replaceFirst(RegExp(r'=+$'), '');
  final rem = cleaned.length % 8;
  if (rem == 1 || rem == 3 || rem == 6) {
    throw const FormatException('invalid base32 length');
  }
  final out = Uint8List((cleaned.length * 5) ~/ 8);
  var written = 0;
  var buffer = 0;
  var bits = 0;
  for (final unit in cleaned.codeUnits) {
    final v = unit < 128 ? _alphabet.indexOf(String.fromCharCode(unit)) : -1;
    if (v < 0) {
      throw const FormatException('invalid base32 character');
    }
    buffer = ((buffer << 5) | v) & 0xfff;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out[written++] = (buffer >> bits) & 0xff;
    }
  }
  return out;
}
