import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/core/update/update_checker.dart';

const String _latestSample = r'''
{
  "url": "https://api.github.com/repos/Radomir-Aksenenko/ObsidianVPN-App/releases/1001",
  "html_url": "https://github.com/Radomir-Aksenenko/ObsidianVPN-App/releases/tag/v2.1.0",
  "tag_name": "v2.1.0",
  "target_commitish": "main",
  "name": "Obsidian 2.1.0",
  "draft": false,
  "prerelease": false,
  "created_at": "2026-09-01T10:00:00Z",
  "published_at": "2026-09-01T10:30:00Z",
  "body": "- Faster reconnects\n- Split tunnel on Linux",
  "assets": [
    {
      "name": "Obsidian-2.1.0-windows-x64.zip",
      "size": 52000000,
      "browser_download_url": "https://github.com/Radomir-Aksenenko/ObsidianVPN-App/releases/download/v2.1.0/Obsidian-2.1.0-windows-x64.zip",
      "content_type": "application/zip"
    },
    {
      "name": "Obsidian-2.1.0-windows-x64-setup.exe",
      "size": 48123904,
      "browser_download_url": "https://github.com/Radomir-Aksenenko/ObsidianVPN-App/releases/download/v2.1.0/Obsidian-2.1.0-windows-x64-setup.exe",
      "content_type": "application/x-msdownload"
    },
    {
      "name": "Obsidian-2.1.0-macos.zip",
      "size": 61000000,
      "browser_download_url": "https://github.com/Radomir-Aksenenko/ObsidianVPN-App/releases/download/v2.1.0/Obsidian-2.1.0-macos.zip",
      "content_type": "application/zip"
    },
    {
      "name": "Obsidian-2.1.0-linux-x64.tar.gz",
      "size": 45000000,
      "browser_download_url": "https://github.com/Radomir-Aksenenko/ObsidianVPN-App/releases/download/v2.1.0/Obsidian-2.1.0-linux-x64.tar.gz",
      "content_type": "application/gzip"
    },
    {
      "name": "Obsidian-2.1.0-android.apk",
      "size": 30000000,
      "browser_download_url": "https://github.com/Radomir-Aksenenko/ObsidianVPN-App/releases/download/v2.1.0/Obsidian-2.1.0-android.apk",
      "content_type": "application/vnd.android.package-archive"
    }
  ]
}
''';

Map<String, Object?> _sampleJson([Map<String, Object?> overrides = const {}]) => {
  ...jsonDecode(_latestSample) as Map<String, Object?>,
  ...overrides,
};

AppRelease _release(List<String> assetNames, {String version = '2.1.0'}) =>
    AppRelease(
      version: version,
      tagName: 'v$version',
      htmlUrl: 'https://example.com/release',
      notes: '',
      publishedAt: null,
      assets: [
        for (final name in assetNames)
          ReleaseAsset(name: name, url: 'https://example.com/$name', size: 1),
      ],
    );

void main() {
  group('compareVersions', () {
    test('orders versions by numeric MAJOR.MINOR.PATCH', () {
      const cases = <(String, String, int)>[
        ('2.0.0', '2.0.0', 0),
        ('2.0.0', '2.0.1', -1),
        ('2.0.1', '2.0.0', 1),
        ('2.0.1', '2.1.0', -1),
        ('2.1.0', '10.0.0', -1),
        ('10.0.0', '2.1.0', 1),
        ('1.1.1', '1.10.0', -1),
      ];
      for (final (a, b, expected) in cases) {
        expect(compareVersions(a, b), expected, reason: '$a vs $b');
      }
    });

    test('ignores a leading v and the +build suffix', () {
      expect(compareVersions('v2.0.0', '2.0.0'), 0);
      expect(compareVersions('V2.0.0', 'v2.0.0'), 0);
      expect(compareVersions('2.0.0+5', '2.0.0'), 0);
      expect(compareVersions('2.0.1+7', 'v2.0.0+9'), 1);
    });

    test('treats a pre-release as lower than the same release', () {
      expect(compareVersions('2.0.0-rc.1', '2.0.0'), -1);
      expect(compareVersions('2.0.0', '2.0.0-rc.1'), 1);
      expect(compareVersions('2.0.0-rc.1', 'v2.0.0-rc.1+build.4'), 0);
      expect(compareVersions('2.0.0-rc.1', '1.9.9'), 1);
    });

    test('compares pre-release identifiers as semver does', () {
      expect(compareVersions('2.0.0-alpha', '2.0.0-beta'), -1);
      expect(compareVersions('2.0.0-alpha', '2.0.0-alpha.1'), -1);
      expect(compareVersions('2.0.0-rc.2', '2.0.0-rc.10'), -1);
      expect(compareVersions('2.0.0-1', '2.0.0-alpha'), -1);
    });

    test('treats garbage as 0.0.0 so it never claims an update', () {
      expect(compareVersions('garbage', '0.0.0'), 0);
      expect(compareVersions('', '0.0.0'), 0);
      expect(compareVersions('nightly', '0.0.1'), -1);
      expect(compareVersions('1.2.3.4', '0.0.0'), 0);
      expect(compareVersions('2.0.0-', '2.0.0'), -1);
      expect(compareVersions('2.0.0-rc..1', '2.0.0'), -1);
    });

    test('accepts a missing minor or patch component as zero', () {
      expect(compareVersions('1.2', '1.2.0'), 0);
      expect(compareVersions('2', '1.9.9'), 1);
    });
  });

  group('AppRelease.tryParse', () {
    test('parses a GitHub release object', () {
      final release = AppRelease.tryParse(_sampleJson());

      expect(release, isNotNull);
      expect(release!.version, '2.1.0');
      expect(release.tagName, 'v2.1.0');
      expect(
        release.htmlUrl,
        'https://github.com/Radomir-Aksenenko/ObsidianVPN-App/releases/tag/v2.1.0',
      );
      expect(release.notes, '- Faster reconnects\n- Split tunnel on Linux');
      expect(release.publishedAt, DateTime.utc(2026, 9, 1, 10, 30));
      expect(release.assets, hasLength(5));

      final setup = release.assets[1];
      expect(setup.name, 'Obsidian-2.1.0-windows-x64-setup.exe');
      expect(
        setup.url,
        'https://github.com/Radomir-Aksenenko/ObsidianVPN-App/releases/download/v2.1.0/Obsidian-2.1.0-windows-x64-setup.exe',
      );
      expect(setup.size, 48123904);
    });

    test('rejects drafts and prereleases', () {
      expect(AppRelease.tryParse(_sampleJson({'prerelease': true})), isNull);
      expect(AppRelease.tryParse(_sampleJson({'draft': true})), isNull);
    });

    test('rejects a missing or invalid tag, version or page URL', () {
      final noTag = _sampleJson()..remove('tag_name');
      expect(AppRelease.tryParse(noTag), isNull);
      expect(AppRelease.tryParse(_sampleJson({'tag_name': 'nightly'})), isNull);
      expect(AppRelease.tryParse(_sampleJson({'tag_name': 'vv2.1.0'})), isNull);
      expect(AppRelease.tryParse(_sampleJson({'tag_name': 42})), isNull);
      expect(AppRelease.tryParse(_sampleJson({'html_url': ''})), isNull);
      final noUrl = _sampleJson()..remove('html_url');
      expect(AppRelease.tryParse(noUrl), isNull);
    });

    test('keeps the release with empty notes and an unknown date', () {
      final release = AppRelease.tryParse(
        _sampleJson({'body': null, 'published_at': 'yesterday'}),
      );

      expect(release, isNotNull);
      expect(release!.notes, '');
      expect(release.publishedAt, isNull);
    });

    test('skips assets without a name or download URL', () {
      final release = AppRelease.tryParse(
        _sampleJson({
          'assets': [
            {'name': 'Obsidian-2.1.0-macos.zip'},
            {'browser_download_url': 'https://example.com/x'},
            'not an object',
            {
              'name': 'Obsidian-2.1.0-linux-x64.tar.gz',
              'browser_download_url': 'https://example.com/linux.tar.gz',
            },
          ],
        }),
      );

      expect(release, isNotNull);
      expect(release!.assets.map((a) => a.name), [
        'Obsidian-2.1.0-linux-x64.tar.gz',
      ]);
      expect(release.assets.single.size, 0);
    });
  });

  group('pickAssetForPlatform', () {
    test('prefers the Windows setup over the zip', () {
      final release = _release([
        'Obsidian-2.1.0-windows-x64.zip',
        'Obsidian-2.1.0-windows-x64-setup.exe',
      ]);

      expect(
        pickAssetForPlatform(release, 'windows')?.name,
        'Obsidian-2.1.0-windows-x64-setup.exe',
      );
    });

    test('falls back to the Windows zip when there is no setup', () {
      final release = _release(['Obsidian-2.1.0-windows-x64.zip']);

      expect(
        pickAssetForPlatform(release, 'windows')?.name,
        'Obsidian-2.1.0-windows-x64.zip',
      );
    });

    test('picks the macOS zip and the Linux tarball', () {
      final release = _release([
        'Obsidian-2.1.0-windows-x64-setup.exe',
        'Obsidian-2.1.0-macos.zip',
        'Obsidian-2.1.0-linux-x64.tar.gz',
        'Obsidian-2.1.0-android.apk',
      ]);

      expect(
        pickAssetForPlatform(release, 'macos')?.name,
        'Obsidian-2.1.0-macos.zip',
      );
      expect(
        pickAssetForPlatform(release, 'linux')?.name,
        'Obsidian-2.1.0-linux-x64.tar.gz',
      );
    });

    test('returns null when no asset matches or the OS is unsupported', () {
      final release = _release([
        'Obsidian-2.1.0-android.apk',
        'Obsidian-2.1.0-macos.zip',
      ]);

      expect(pickAssetForPlatform(release, 'windows'), isNull);
      expect(pickAssetForPlatform(release, 'linux'), isNull);
      expect(pickAssetForPlatform(release, 'android'), isNull);
      expect(pickAssetForPlatform(release, 'ios'), isNull);
      expect(pickAssetForPlatform(release, ''), isNull);
    });
  });

  group('shouldNotify', () {
    final release = _release(const []);

    test('is true when nothing was skipped', () {
      expect(shouldNotify(release), isTrue);
    });

    test('is false only for the exact skipped version', () {
      expect(shouldNotify(release, skippedVersion: '2.1.0'), isFalse);
      expect(shouldNotify(release, skippedVersion: 'v2.1.0'), isFalse);
      expect(shouldNotify(release, skippedVersion: '2.1.1'), isTrue);
      expect(shouldNotify(release, skippedVersion: '2.0.0'), isTrue);
    });
  });

  group('UpdateChecker.checkForUpdate', () {
    Future<String?> Function(Uri) serve(Object? json) =>
        (uri) async => jsonEncode(json);

    test('returns the release when it is newer than the current version', () async {
      final checker = UpdateChecker(
        currentVersion: '2.0.0',
        fetch: serve(_sampleJson()),
      );

      final release = await checker.checkForUpdate();

      expect(release, isNotNull);
      expect(release!.version, '2.1.0');
    });

    test('returns null when the current version is the same or newer', () async {
      final same = UpdateChecker(
        currentVersion: '2.1.0',
        fetch: serve(_sampleJson()),
      );
      final newer = UpdateChecker(
        currentVersion: 'v2.2.0',
        fetch: serve(_sampleJson()),
      );

      expect(await same.checkForUpdate(), isNull);
      expect(await newer.checkForUpdate(), isNull);
    });

    test('returns null when the fetch yields no body', () async {
      final checker = UpdateChecker(
        currentVersion: '2.0.0',
        fetch: (uri) async => null,
      );

      expect(await checker.checkForUpdate(), isNull);
    });

    test('returns null for malformed JSON', () async {
      final checker = UpdateChecker(
        currentVersion: '2.0.0',
        fetch: (uri) async => '{"tag_name": ',
      );

      expect(await checker.checkForUpdate(), isNull);
    });

    test('returns null when the fetch throws', () async {
      final checker = UpdateChecker(
        currentVersion: '2.0.0',
        fetch: (uri) async => throw Exception('offline'),
      );

      expect(await checker.checkForUpdate(), isNull);
    });

    test('returns null when the fetch takes longer than the timeout', () async {
      final checker = UpdateChecker(
        currentVersion: '2.0.0',
        fetch: (uri) => Completer<String?>().future,
        timeout: const Duration(milliseconds: 50),
      );

      expect(await checker.checkForUpdate(), isNull);
    });

    test('returns null for prereleases and drafts', () async {
      final prerelease = UpdateChecker(
        currentVersion: '2.0.0',
        fetch: serve(_sampleJson({'prerelease': true})),
      );
      final draft = UpdateChecker(
        currentVersion: '2.0.0',
        fetch: serve(_sampleJson({'draft': true})),
      );

      expect(await prerelease.checkForUpdate(), isNull);
      expect(await draft.checkForUpdate(), isNull);
    });

    test('never claims an update when the current version is garbage', () async {
      final checker = UpdateChecker(
        currentVersion: 'dev',
        fetch: serve(_sampleJson()),
      );

      expect(await checker.checkForUpdate(), isNull);
    });

    test('requests the GitHub latest release endpoint', () async {
      Uri? requested;
      final checker = UpdateChecker(
        currentVersion: '2.0.0',
        fetch: (uri) async {
          requested = uri;
          return null;
        },
      );

      await checker.checkForUpdate();

      expect(requested, Uri.parse(kLatestReleaseUrl));
      expect(
        requested.toString(),
        'https://api.github.com/repos/Radomir-Aksenenko/ObsidianVPN-App/releases/latest',
      );
    });
  });
}
