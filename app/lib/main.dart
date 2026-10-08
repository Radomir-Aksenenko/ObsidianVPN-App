import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'platform_info.dart';

Future<void> main(List<String> args) async {
  runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (details) {
        debugPrint('FlutterError: ${details.exceptionAsString()}');
        final stack = details.stack;
        if (stack != null) debugPrint(stack.toString());
      };

      if (isDesktop) await _initDesktopWindow();

      runApp(ObsidianBootstrap(launchArgs: args));
    },
    (error, stack) {
      debugPrint('Uncaught error: $error');
      debugPrint(stack.toString());
    },
  );
}

Future<void> _initDesktopWindow() async {
  await windowManager.ensureInitialized();

  const options = WindowOptions(
    size: Size(420, 760),
    minimumSize: Size(380, 640),
    center: true,
    backgroundColor: Color(0xFF0B0C0E),
    titleBarStyle: TitleBarStyle.hidden,
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setTitle('Obsidian');
    await windowManager.show();
    await windowManager.focus();
  });
}
