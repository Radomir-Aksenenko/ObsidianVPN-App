import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/core/models/profile.dart';
import 'package:obsidian_vpn/core/update/update_checker.dart';
import 'package:obsidian_vpn/state/update_controller.dart';

const Duration _long = Duration(hours: 6);

/// Lets zero-delay timers and the check future run.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 30));

String _releaseJson(String tag) => jsonEncode(<String, Object?>{
  'tag_name': tag,
  'html_url': 'https://github.com/example/app/releases/tag/$tag',
  'body': 'Notes',
  'draft': false,
  'prerelease': false,
  'assets': <Object?>[],
});

/// Stands in for GitHub: counts requests, answers with [reply] (null means a
/// failed fetch) and, when [gate] is set, holds each answer until it completes.
class _FakeGithub {
  _FakeGithub(this.reply);

  String? reply;
  int calls = 0;
  Completer<void>? gate;

  Future<String?> fetch(Uri uri) async {
    calls++;
    final hold = gate;
    if (hold != null) await hold.future;
    return reply;
  }
}

void main() {
  late _FakeGithub github;
  late AppSettings settings;

  UpdateController build({
    Duration firstCheckDelay = Duration.zero,
    Duration interval = _long,
  }) {
    final created = UpdateController(
      checker: UpdateChecker(currentVersion: '2.0.0', fetch: github.fetch),
      readSettings: () => settings,
      firstCheckDelay: firstCheckDelay,
      interval: interval,
    );
    addTearDown(created.dispose);
    return created;
  }

  setUp(() {
    github = _FakeGithub(_releaseJson('v2.1.0'));
    settings = const AppSettings();
  });

  test('start does nothing when checkUpdates is off', () async {
    settings = const AppSettings(checkUpdates: false);
    final controller = build();

    controller.start();
    await _settle();

    expect(github.calls, 0);
    expect(controller.available, isNull);
    expect(controller.checking, isFalse);
  });

  test('start runs the first check and queues one startup prompt', () async {
    final controller = build();

    controller.start();
    await _settle();

    expect(github.calls, 1);
    expect(controller.available?.version, '2.1.0');
    expect(controller.takePrompt()?.version, '2.1.0');
    expect(controller.takePrompt(), isNull);
  });

  test('periodic checks prompt once per version in a session', () async {
    final controller = build(interval: const Duration(milliseconds: 5));

    controller.start();
    await _settle();

    expect(github.calls, greaterThan(1));
    expect(controller.takePrompt()?.version, '2.1.0');
    expect(controller.takePrompt(), isNull);
  });

  test(
    'a skipped version gets no startup prompt but stays in the status',
    () async {
      settings = const AppSettings(skippedUpdateVersion: '2.1.0');
      final controller = build();

      controller.start();
      await _settle();

      expect(controller.available?.version, '2.1.0');
      expect(controller.takePrompt(), isNull);
    },
  );

  test('checkNow ignores checkUpdates and a skipped version', () async {
    settings = const AppSettings(
      checkUpdates: false,
      skippedUpdateVersion: '2.1.0',
    );
    final controller = build();

    final release = await controller.checkNow();

    expect(release?.version, '2.1.0');
    expect(github.calls, 1);
    expect(controller.available?.version, '2.1.0');
    expect(controller.takePrompt()?.version, '2.1.0');
  });

  test('checkNow reports up to date when the release is not newer', () async {
    github.reply = _releaseJson('v2.0.0');
    final controller = build();

    final release = await controller.checkNow();

    expect(release, isNull);
    expect(controller.available, isNull);
    expect(controller.lastCheckFailed, isFalse);
    expect(controller.lastCheckedAt, isNotNull);
    expect(controller.takePrompt(), isNull);
  });

  test('concurrent checkNow calls share one fetch', () async {
    github.gate = Completer<void>();
    final controller = build();

    final first = controller.checkNow();
    final second = controller.checkNow();
    expect(controller.checking, isTrue);

    github.gate!.complete();
    final results = await Future.wait([first, second]);

    expect(github.calls, 1);
    expect(identical(results[0], results[1]), isTrue);
    expect(results[0]?.version, '2.1.0');
    expect(controller.checking, isFalse);
  });

  test(
    'a failed fetch sets lastCheckFailed and keeps the known release',
    () async {
      final controller = build();
      await controller.checkNow();
      expect(controller.available?.version, '2.1.0');

      github.reply = null;
      final release = await controller.checkNow();

      expect(release, isNull);
      expect(controller.lastCheckFailed, isTrue);
      expect(controller.available?.version, '2.1.0');

      github.reply = _releaseJson('v2.0.0');
      await controller.checkNow();
      expect(controller.lastCheckFailed, isFalse);
    },
  );

  test('a fetch that throws counts as a failed check', () async {
    final controller = UpdateController(
      checker: UpdateChecker(
        currentVersion: '2.0.0',
        fetch: (uri) async => throw StateError('offline'),
      ),
      readSettings: () => settings,
    );
    addTearDown(controller.dispose);

    await controller.checkNow();

    expect(controller.lastCheckFailed, isTrue);
    expect(controller.checking, isFalse);
  });

  test('dispose cancels the timers, so no check runs afterwards', () async {
    final controller = UpdateController(
      checker: UpdateChecker(currentVersion: '2.0.0', fetch: github.fetch),
      readSettings: () => settings,
      firstCheckDelay: const Duration(milliseconds: 5),
    );

    controller.start();
    controller.dispose();
    await _settle();

    expect(github.calls, 0);
  });
}
