import '../../l10n/app_localizations.dart';

/// A throughput split for display: [value] with one decimal and its [unit].
class FormattedRate {
  const FormattedRate(this.value, this.unit);

  final String value;
  final String unit;
}

/// Formats [bytesPerSecond] as bits per second: Кбит/с, Мбит/с or Гбит/с, one decimal.
FormattedRate formatRate(int bytesPerSecond, AppLocalizations l10n) {
  final bits = bytesPerSecond < 0 ? 0 : bytesPerSecond * 8;
  if (bits >= 1e9) {
    return FormattedRate((bits / 1e9).toStringAsFixed(1), l10n.unitGbps);
  }
  if (bits >= 1e6) {
    return FormattedRate((bits / 1e6).toStringAsFixed(1), l10n.unitMbps);
  }
  return FormattedRate((bits / 1e3).toStringAsFixed(1), l10n.unitKbps);
}

/// Formats a byte count: Б, КБ, МБ or ГБ (binary steps, one decimal above bytes).
String formatBytes(int bytes, AppLocalizations l10n) {
  if (bytes < 1024) return '$bytes ${l10n.unitByte}';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} ${l10n.unitKilobyte}';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} ${l10n.unitMegabyte}';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} ${l10n.unitGigabyte}';
}

/// `HH:MM:SS` for a session length. Hours do not wrap at 24.
String formatSession(Duration d) {
  final s = d.isNegative ? 0 : d.inSeconds;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(s ~/ 3600)}:${two(s % 3600 ~/ 60)}:${two(s % 60)}';
}
