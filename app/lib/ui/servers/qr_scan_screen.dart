import 'package:flutter/material.dart' hide Durations;
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/theme.dart';
import '../widgets/widgets.dart';

/// Full-screen QR scanner for access keys. Pops with the first non-empty QR value, or null.
/// Shown only on Android, iOS and macOS.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
  );
  bool _found = false;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_found) return;
    String? value;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim();
      if (raw != null && raw.isNotEmpty) {
        value = raw;
        break;
      }
    }
    if (value == null) return;
    _found = true;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.obs.colors;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(
              controller: _scanner,
              onDetect: _onDetect,
              errorBuilder: (context, error) => _ScanError(
                error: error,
                onClose: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          Positioned.fill(
            child: ValueListenableBuilder<MobileScannerState>(
              valueListenable: _scanner,
              builder: (context, state, _) {
                if (state.error != null) return const SizedBox.shrink();
                return IgnorePointer(
                  child: CustomPaint(painter: _FramePainter(color: c.ember)),
                );
              },
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.s8,
                    vertical: Space.s4,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: l10n.sheetClose,
                        icon: const Icon(Icons.close_rounded),
                        color: Colors.white,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Text(
                          l10n.qrTitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      ValueListenableBuilder<MobileScannerState>(
                        valueListenable: _scanner,
                        builder: (context, state, _) {
                          final on = state.torchState == TorchState.on;
                          return IconButton(
                            tooltip: l10n.qrTorch,
                            icon: Icon(
                              on
                                  ? Icons.flashlight_on_rounded
                                  : Icons.flashlight_off_rounded,
                            ),
                            color: on ? c.ember : Colors.white,
                            onPressed: state.error == null
                                ? () => _scanner.toggleTorch()
                                : null,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                ValueListenableBuilder<MobileScannerState>(
                  valueListenable: _scanner,
                  builder: (context, state, _) {
                    if (state.error != null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.all(Space.s24),
                      child: Text(
                        l10n.qrHint,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Camera error panel: permission denied explains how to allow it; other errors say to paste the key.
class _ScanError extends StatelessWidget {
  const _ScanError({required this.error, required this.onClose});

  final MobileScannerException error;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.gutterNarrow),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (denied) ...[
                Text(
                  l10n.qrDeniedTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: Space.s8),
                Text(
                  l10n.qrDeniedBody,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
              ] else
                Text(
                  l10n.qrError,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
              const SizedBox(height: Space.s24),
              ObsButton(
                label: l10n.sheetClose,
                kind: ObsButtonKind.secondary,
                expand: false,
                onPressed: onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dims the camera outside a centered square and draws the square as a 1 px ember hairline.
class _FramePainter extends CustomPainter {
  const _FramePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final side = (size.shortestSide * 0.68).clamp(180.0, 300.0);
    final frame = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: side,
      height: side,
    );
    final rounded = RRect.fromRectAndRadius(frame, const Radius.circular(16));

    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(rounded),
    );
    canvas.drawPath(outside, Paint()..color = const Color(0x8C000000));
    canvas.drawRRect(
      rounded,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _FramePainter oldDelegate) => oldDelegate.color != color;
}
