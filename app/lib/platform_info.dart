import 'dart:io' show Platform;

import 'package:flutter/foundation.dart'
    show TargetPlatform, kIsWeb, visibleForTesting;

/// Test hook: pretend to run on this platform. Null uses the real platform.
@visibleForTesting
TargetPlatform? debugPlatformOverride;

bool _is(TargetPlatform target, bool Function() real) {
  if (kIsWeb) return false;
  final override = debugPlatformOverride;
  return override != null ? override == target : real();
}

/// True on Windows, macOS and Linux. Always false on web.
bool get isDesktop => isWindows || isMacOS || isLinux;

/// True on Android and iOS.
bool get isMobile =>
    _is(TargetPlatform.android, () => Platform.isAndroid) ||
    _is(TargetPlatform.iOS, () => Platform.isIOS);

/// Windows and Linux draw their own title area. macOS keeps native traffic lights.
bool get usesCustomTitleBar => isWindows || isLinux;

bool get isWindows => _is(TargetPlatform.windows, () => Platform.isWindows);

bool get isLinux => _is(TargetPlatform.linux, () => Platform.isLinux);

bool get isMacOS => _is(TargetPlatform.macOS, () => Platform.isMacOS);
