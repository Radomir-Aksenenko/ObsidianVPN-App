import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// True on Windows, macOS and Linux. Always false on web.
bool get isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

/// Windows and Linux draw their own title area. macOS keeps native traffic lights.
bool get usesCustomTitleBar => !kIsWeb && (Platform.isWindows || Platform.isLinux);

bool get isMacOS => !kIsWeb && Platform.isMacOS;
