import 'dart:convert';
import 'dart:io';

/// Latest non-prerelease release of the desktop app on GitHub.
const String kLatestReleaseUrl =
    'https://api.github.com/repos/Radomir-Aksenenko/ObsidianVPN-App/releases/latest';

/// A file attached to a GitHub release.
final class ReleaseAsset {
  /// Creates an asset description.
  const ReleaseAsset({
    required this.name,
    required this.url,
    required this.size,
  });

  /// File name, for example `Obsidian-2.1.0-windows-x64-setup.exe`.
  final String name;

  /// Direct download URL (GitHub `browser_download_url`).
  final String url;

  /// Size in bytes as reported by GitHub, or 0 when unknown.
  final int size;
}

/// A published release of the desktop app.
final class AppRelease {
  /// Creates a release. Use [AppRelease.tryParse] to build one from GitHub JSON.
  const AppRelease({
    required this.version,
    required this.tagName,
    required this.htmlUrl,
    required this.notes,
    required this.publishedAt,
    required this.assets,
  });

  /// Semver string without the leading `v`, for example `2.1.0`.
  final String version;

  /// Git tag as published, for example `v2.1.0`.
  final String tagName;

  /// Release page on GitHub, for opening in a browser.
  final String htmlUrl;

  /// Release notes (GitHub `body`). Empty when the release has none.
  final String notes;

  /// Publication time in UTC, or null when missing or unparsable.
  final DateTime? publishedAt;

  /// Files attached to the release.
  final List<ReleaseAsset> assets;

  /// Parses one object from the GitHub `releases/latest` response.
  ///
  /// Returns null for drafts and prereleases, and when the tag, its version
  /// or the release page URL is missing or invalid. Assets without a name or
  /// download URL are skipped. Never throws.
  static AppRelease? tryParse(Map<String, Object?> json) {
    if (json['draft'] == true || json['prerelease'] == true) return null;

    final tag = json['tag_name'];
    final htmlUrl = json['html_url'];
    if (tag is! String || htmlUrl is! String || htmlUrl.isEmpty) return null;

    final tagName = tag.trim();
    if (_parseVersion(tagName) == null) return null;

    final body = json['body'];
    final published = json['published_at'];

    final assets = <ReleaseAsset>[];
    final rawAssets = json['assets'];
    if (rawAssets is List<Object?>) {
      for (final item in rawAssets) {
        if (item is! Map<String, Object?>) continue;
        final name = item['name'];
        final url = item['browser_download_url'];
        if (name is! String || url is! String) continue;
        final size = item['size'];
        assets.add(
          ReleaseAsset(name: name, url: url, size: size is int ? size : 0),
        );
      }
    }

    return AppRelease(
      version: _stripV(tagName),
      tagName: tagName,
      htmlUrl: htmlUrl,
      notes: body is String ? body : '',
      publishedAt: published is String
          ? DateTime.tryParse(published)?.toUtc()
          : null,
      assets: List.unmodifiable(assets),
    );
  }
}

/// Compares two version strings and returns -1, 0 or 1.
///
/// Accepts `MAJOR.MINOR.PATCH` with an optional leading `v`, an optional
/// `+build` suffix (ignored) and an optional `-pre` suffix. A pre-release is
/// lower than the same version without a suffix. Input that cannot be parsed
/// is treated as `0.0.0`.
int compareVersions(String a, String b) {
  final left = _parseVersion(a) ?? _zero;
  final right = _parseVersion(b) ?? _zero;
  return _compareParsed(left, right).sign;
}

/// Picks the installer or archive for [os] (a `Platform.operatingSystem`
/// value). Windows prefers the setup `.exe` and falls back to the zip.
/// Returns null for unsupported platforms or when no matching asset exists.
ReleaseAsset? pickAssetForPlatform(AppRelease r, String os) {
  final suffixes = switch (os) {
    'windows' => const ['-windows-x64-setup.exe', '-windows-x64.zip'],
    'macos' => const ['-macos.zip'],
    'linux' => const ['-linux-x64.tar.gz'],
    _ => const <String>[],
  };
  for (final suffix in suffixes) {
    for (final asset in r.assets) {
      if (asset.name.toLowerCase().endsWith(suffix)) return asset;
    }
  }
  return null;
}

/// Whether the user should be told about [r].
///
/// Returns false only when [skippedVersion] is the same version as [r]
/// (a leading `v` is ignored).
bool shouldNotify(AppRelease r, {String? skippedVersion}) {
  if (skippedVersion == null) return true;
  return _stripV(skippedVersion.trim()) != r.version;
}

/// Outcome of one [UpdateChecker.check].
final class UpdateCheckResult {
  /// Creates a result. A plain `UpdateCheckResult()` means "up to date".
  const UpdateCheckResult({this.release, this.failed = false});

  /// A newer release, or null when the app is up to date or the check failed.
  final AppRelease? release;

  /// True when GitHub could not be read or its answer could not be used.
  final bool failed;
}

/// Checks GitHub for a newer release of the running app.
final class UpdateChecker {
  /// Creates a checker for an app running [currentVersion].
  ///
  /// [fetch] returns the response body, or null when there is no usable
  /// response. The default performs an HTTP GET with [timeout] and returns the
  /// body only for status 200. Tests inject their own [fetch].
  UpdateChecker({
    required this.currentVersion,
    Future<String?> Function(Uri uri)? fetch,
    this.timeout = const Duration(seconds: 10),
  }) : _fetch =
           fetch ??
           ((uri) => _httpGet(
             uri,
             timeout: timeout,
             userAgent: 'ObsidianVPN/$currentVersion',
           ));

  /// Version of the running app, for example `2.0.0`.
  final String currentVersion;

  /// Upper bound for the whole check.
  final Duration timeout;

  final Future<String?> Function(Uri uri) _fetch;

  /// Returns the latest release when it is strictly newer than
  /// [currentVersion], otherwise null. A [currentVersion] that cannot be
  /// parsed also yields null. Never throws.
  Future<AppRelease?> checkForUpdate() async => (await check()).release;

  /// Like [checkForUpdate], but also reports whether the check failed (no
  /// response, or an answer that could not be used). Never throws.
  Future<UpdateCheckResult> check() async {
    if (_parseVersion(currentVersion) == null) {
      return const UpdateCheckResult();
    }
    try {
      final body = await _fetch(Uri.parse(kLatestReleaseUrl)).timeout(timeout);
      if (body == null) return const UpdateCheckResult(failed: true);
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, Object?>) {
        return const UpdateCheckResult(failed: true);
      }
      final release = AppRelease.tryParse(decoded);
      if (release == null) return const UpdateCheckResult(failed: true);
      return compareVersions(release.version, currentVersion) > 0
          ? UpdateCheckResult(release: release)
          : const UpdateCheckResult();
    } on Object {
      return const UpdateCheckResult(failed: true);
    }
  }
}

/// Opens [url] in the default browser.
///
/// Only `http` and `https` URLs are accepted; anything else is ignored. The
/// URL is passed as a process argument and never goes through a shell. Never
/// throws.
Future<void> openInBrowser(String url) async {
  if (!_isWebUrl(url)) return;
  final command = _browserCommand(url);
  if (command == null) return;
  try {
    await Process.start(
      command.$1,
      command.$2,
      mode: ProcessStartMode.detached,
    );
  } on Object {
    return;
  }
}

Future<String?> _httpGet(
  Uri uri, {
  required Duration timeout,
  required String userAgent,
}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client.getUrl(uri).timeout(timeout);
    request.headers
      ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
      ..set(HttpHeaders.userAgentHeader, userAgent);
    final response = await request.close().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      return null;
    }
    return await response.transform(utf8.decoder).join().timeout(timeout);
  } on Object {
    return null;
  } finally {
    client.close(force: true);
  }
}

bool _isWebUrl(String url) {
  final uri = Uri.tryParse(url);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

(String, List<String>)? _browserCommand(String url) {
  if (Platform.isWindows) {
    return ('rundll32', ['url.dll,FileProtocolHandler', url]);
  }
  if (Platform.isMacOS) return ('open', [url]);
  if (Platform.isLinux) return ('xdg-open', [url]);
  return null;
}

final class _Version {
  const _Version(this.major, this.minor, this.patch, this.pre);

  final int major;
  final int minor;
  final int patch;

  /// Pre-release identifiers, or null for a release.
  final List<String>? pre;
}

const _Version _zero = _Version(0, 0, 0, null);

final RegExp _digits = RegExp(r'^[0-9]+$');
final RegExp _preIdentifier = RegExp(r'^[0-9A-Za-z-]+$');

String _stripV(String s) =>
    (s.startsWith('v') || s.startsWith('V')) ? s.substring(1) : s;

/// Parses `[v]MAJOR[.MINOR[.PATCH]][-pre][+build]`. Returns null when invalid.
_Version? _parseVersion(String input) {
  var s = _stripV(input.trim());

  final plus = s.indexOf('+');
  if (plus >= 0) s = s.substring(0, plus);

  List<String>? pre;
  final dash = s.indexOf('-');
  if (dash >= 0) {
    final ids = s.substring(dash + 1).split('.');
    if (ids.any((id) => !_preIdentifier.hasMatch(id))) return null;
    pre = ids;
    s = s.substring(0, dash);
  }

  final parts = s.split('.');
  if (parts.length > 3) return null;
  final numbers = <int>[];
  for (final part in parts) {
    if (!_digits.hasMatch(part)) return null;
    final n = int.tryParse(part);
    if (n == null) return null;
    numbers.add(n);
  }

  return _Version(
    numbers[0],
    numbers.length > 1 ? numbers[1] : 0,
    numbers.length > 2 ? numbers[2] : 0,
    pre,
  );
}

int _compareParsed(_Version a, _Version b) {
  if (a.major != b.major) return a.major.compareTo(b.major);
  if (a.minor != b.minor) return a.minor.compareTo(b.minor);
  if (a.patch != b.patch) return a.patch.compareTo(b.patch);

  final ap = a.pre;
  final bp = b.pre;
  if (ap == null || bp == null) {
    if (ap == null && bp == null) return 0;
    return ap == null ? 1 : -1;
  }
  return _comparePreRelease(ap, bp);
}

int _comparePreRelease(List<String> a, List<String> b) {
  final shared = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < shared; i++) {
    final x = a[i];
    final y = b[i];
    final xNumeric = _digits.hasMatch(x);
    final yNumeric = _digits.hasMatch(y);
    final int c;
    if (xNumeric && yNumeric) {
      c = _compareDigits(x, y);
    } else if (xNumeric != yNumeric) {
      c = xNumeric ? -1 : 1;
    } else {
      c = x.compareTo(y);
    }
    if (c != 0) return c;
  }
  return a.length.compareTo(b.length);
}

int _compareDigits(String a, String b) {
  final x = a.replaceFirst(RegExp(r'^0+(?=[0-9])'), '');
  final y = b.replaceFirst(RegExp(r'^0+(?=[0-9])'), '');
  if (x.length != y.length) return x.length.compareTo(y.length);
  return x.compareTo(y);
}
