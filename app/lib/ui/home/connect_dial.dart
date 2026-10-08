import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Durations;
import 'package:flutter/services.dart';

import '../../theme/theme.dart';
import '../../vpn/vpn_backend.dart';

const double _dialSize = 220;
const double _coreSize = 168;
const double _stroke = 6;
const int _segments = 4;
const double _segmentDeg = 84;
const double _gapDeg = 6;
const double _sweepDeg = 30;

double _rad(double deg) => deg * math.pi / 180;

/// How many ring segments (0..4) are lit ember for [s]. The phase decides the
/// result, not the stage: connected lights all segments and disconnected or
/// disconnecting lights none, because some backends report connected with a
/// stage below 4 (Android never sends stage 2). A failed handshake lights the
/// segments before the failed one.
int litSegments(VpnStatus s) => switch (s.phase) {
  VpnPhase.connected => _segments,
  VpnPhase.connecting || VpnPhase.reconnecting => s.stage,
  VpnPhase.error => math.min(s.stage, _segments - 1),
  VpnPhase.disconnected || VpnPhase.disconnecting => 0,
};

/// Where each of the 4 ring segments starts, in degrees from 3 o'clock (clockwise).
/// The first gap is centred on 12 o'clock.
double _segmentStart(int i) => -90 + _gapDeg / 2 + i * (_segmentDeg + _gapDeg);

/// The connect dial from DESIGN.md: a ring of 4 stage segments around a core with
/// a power glyph. The ring is driven by [status]: segments fill ember as
/// `status.stage` grows (220 ms each), a 30 degree sweep rotates only while the
/// phase is connecting or reconnecting, connected is static, and an error paints
/// the failed stage segment in danger. Nothing animates while idle or connected.
class ConnectDial extends StatefulWidget {
  const ConnectDial({
    super.key,
    required this.status,
    required this.onPressed,
    required this.semanticLabel,
    this.semanticValue,
  });

  final VpnStatus status;

  /// Called on tap (and Space or Enter when the dial has focus).
  final VoidCallback onPressed;

  /// Action the tap performs, for screen readers ("Подключить").
  final String semanticLabel;

  /// Current state for screen readers ("ЗАЩИЩЕНО").
  final String? semanticValue;

  @override
  State<ConnectDial> createState() => _ConnectDialState();
}

class _ConnectDialState extends State<ConnectDial>
    with TickerProviderStateMixin {
  // Ring fill in segments, 0..4.
  late final AnimationController _fill = AnimationController(
    vsync: this,
    lowerBound: 0,
    upperBound: _segments.toDouble(),
  );
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  // Connected tint of the core, 0..1.
  late final AnimationController _tint = AnimationController(vsync: this);

  bool _pressed = false;
  bool _hovered = false;
  bool _noMotion = false;

  static bool _isSweepPhase(VpnPhase p) =>
      p == VpnPhase.connecting || p == VpnPhase.reconnecting;

  /// Index of the segment that failed, or null when there is no error.
  static int? _errorSegment(VpnStatus s) =>
      s.phase == VpnPhase.error ? math.min(s.stage, _segments - 1) : null;

  static double _fillTarget(VpnStatus s) => litSegments(s).toDouble();

  @override
  void initState() {
    super.initState();
    _fill.value = _fillTarget(widget.status);
    _tint.value = widget.status.phase == VpnPhase.connected ? 1 : 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _noMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _syncSweep();
  }

  @override
  void didUpdateWidget(ConnectDial old) {
    super.didUpdateWidget(old);
    final from = old.status;
    final to = widget.status;
    if (from.phase != to.phase || from.stage != to.stage) _animateTo(to);
    if (from.phase != VpnPhase.connected && to.phase == VpnPhase.connected) {
      _haptic(HapticFeedback.mediumImpact);
    }
    _syncSweep();
  }

  void _animateTo(VpnStatus s) {
    final target = _fillTarget(s);
    final delta = (target - _fill.value).abs();
    if (_noMotion || delta == 0) {
      _fill.value = target;
    } else {
      final ms = target > _fill.value ? 220 * delta : 220;
      _fill.animateTo(
        target,
        duration: Duration(milliseconds: ms.round()),
        curve: Curves.easeOut,
      );
    }
    final tintTarget = s.phase == VpnPhase.connected ? 1.0 : 0.0;
    if (_noMotion) {
      _tint.value = tintTarget;
    } else {
      _tint.animateTo(
        tintTarget,
        duration: Durations.stateChange,
        curve: Durations.curve,
      );
    }
  }

  /// The sweep is the only looping animation. It runs strictly while connecting.
  void _syncSweep() {
    final want = _isSweepPhase(widget.status.phase) && !_noMotion;
    if (want && !_sweep.isAnimating) {
      _sweep.repeat();
    } else if (!want && _sweep.isAnimating) {
      _sweep.stop();
    }
  }

  void _haptic(Future<void> Function() impact) {
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      impact();
    }
  }

  void _tap() {
    _haptic(HapticFeedback.lightImpact);
    widget.onPressed();
  }

  @override
  void dispose() {
    _fill.dispose();
    _sweep.dispose();
    _tint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.obs.colors;
    final phase = widget.status.phase;
    final glyph = switch (phase) {
      VpnPhase.connected => c.ember,
      VpnPhase.connecting || VpnPhase.reconnecting => c.text,
      _ => c.textDim,
    };

    return Semantics(
      button: true,
      label: widget.semanticLabel,
      value: widget.semanticValue,
      onTap: _tap,
      excludeSemantics: true,
      child: RepaintBoundary(
        child: FocusableActionDetector(
          mouseCursor: SystemMouseCursors.click,
          onShowHoverHighlight: (v) => setState(() => _hovered = v),
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                _tap();
                return null;
              },
            ),
          },
          child: Listener(
            onPointerDown: (_) => setState(() => _pressed = true),
            onPointerUp: (_) => setState(() => _pressed = false),
            onPointerCancel: (_) => setState(() => _pressed = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _tap,
              supportedDevices: const {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.stylus,
              },
              child: AnimatedScale(
                scale: _pressed ? 0.97 : 1,
                duration: _noMotion ? Duration.zero : Durations.press,
                curve: Durations.curve,
                child: SizedBox.square(
                  dimension: _dialSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size.square(_dialSize),
                        painter: DialPainter(
                          colors: c,
                          fill: _fill,
                          sweep: _sweep,
                          tint: _tint,
                          sweeping: _sweep,
                          errorSegment: _errorSegment(widget.status),
                          hovered: _hovered,
                        ),
                      ),
                      TweenAnimationBuilder<Color?>(
                        tween: ColorTween(end: glyph),
                        duration: _noMotion
                            ? Duration.zero
                            : Durations.stateChange,
                        builder: (context, color, _) => Icon(
                          Icons.power_settings_new_rounded,
                          size: 36,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the ring, the core and the connected tint of [ConnectDial]. Repaints on the
/// three controllers only.
class DialPainter extends CustomPainter {
  DialPainter({
    required this.colors,
    required this.fill,
    required this.sweep,
    required this.tint,
    required this.sweeping,
    required this.errorSegment,
    required this.hovered,
  }) : super(repaint: Listenable.merge([fill, sweep, tint]));

  final ObsidianColors colors;

  /// Filled segments, 0..4 (fractions fill the next segment partly).
  final Animation<double> fill;

  /// Sweep position 0..1; drawn only while [sweeping] is animating.
  final Animation<double> sweep;

  /// Connected tint of the core, 0..1.
  final Animation<double> tint;
  final AnimationController sweeping;
  final int? errorSegment;
  final bool hovered;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final ringRadius = (size.width - _stroke) / 2;
    final ringRect = Rect.fromCircle(center: center, radius: ringRadius);

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // Core.
    final coreRadius = _coreSize / 2;
    canvas.drawCircle(center, coreRadius, Paint()..color = colors.surfaceHi);
    final t = tint.value;
    if (t > 0) {
      final glow = colors.ember.withValues(alpha: 0.26 * t);
      canvas.drawCircle(
        center,
        coreRadius,
        Paint()
          ..shader = RadialGradient(
            colors: [glow, colors.emberSoft.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: coreRadius)),
      );
    }
    canvas.drawCircle(
      center,
      coreRadius - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = hovered ? colors.textFaint : colors.line,
    );

    // Base segments, then the ember fill of each.
    final filled = fill.value;
    for (var i = 0; i < _segments; i++) {
      final start = _rad(_segmentStart(i));
      final sweepRad = _rad(_segmentDeg);
      ring.color = colors.idleRing;
      canvas.drawArc(ringRect, start, sweepRad, false, ring);

      if (errorSegment == i) {
        ring.color = colors.danger;
        canvas.drawArc(ringRect, start, sweepRad, false, ring);
        continue;
      }
      final p = (filled - i).clamp(0.0, 1.0);
      if (p > 0.02) {
        ring.color = colors.ember;
        canvas.drawArc(ringRect, start, sweepRad * p, false, ring);
      }
    }

    // Rotating highlight: only while the sweep controller runs.
    if (sweeping.isAnimating) {
      final head = -90 + sweep.value * 360;
      ring.color = Color.lerp(colors.ember, colors.text, 0.5)!;
      for (var i = 0; i < _segments; i++) {
        final segStart = _segmentStart(i);
        final segEnd = segStart + _segmentDeg;
        for (final wrap in const [-360.0, 0.0, 360.0]) {
          final a = math.max(head + wrap, segStart);
          final b = math.min(head + wrap + _sweepDeg, segEnd);
          if (b - a > 0.5) {
            canvas.drawArc(ringRect, _rad(a), _rad(b - a), false, ring);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(DialPainter old) =>
      old.colors != colors ||
      old.errorSegment != errorSegment ||
      old.hovered != hovered ||
      old.fill != fill ||
      old.sweep != sweep ||
      old.tint != tint;
}
