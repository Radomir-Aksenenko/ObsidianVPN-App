import 'dart:async';

import 'package:flutter/material.dart';

import 'traffic_format.dart';

/// Session length as `HH:MM:SS`. The 1 s timer exists only while [active] is true;
/// pass active = connected and visible so nothing ticks in the background.
class SessionTimer extends StatefulWidget {
  const SessionTimer({
    super.key,
    required this.connectedAt,
    required this.active,
    required this.style,
  });

  /// When the tunnel came up. Null counts from the moment this widget appeared.
  final DateTime? connectedAt;
  final bool active;
  final TextStyle style;

  @override
  State<SessionTimer> createState() => _SessionTimerState();
}

class _SessionTimerState extends State<SessionTimer> {
  Timer? _timer;
  final DateTime _mounted = DateTime.now();

  /// True while the periodic timer is running. Exposed for tests.
  @visibleForTesting
  bool get isTicking => _timer?.isActive ?? false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(SessionTimer old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.active && _timer == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!widget.active && _timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(widget.connectedAt ?? _mounted);
    return Text(formatSession(elapsed), style: widget.style, maxLines: 1);
  }
}
