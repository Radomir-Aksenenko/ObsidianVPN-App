import 'package:flutter/material.dart' hide Durations;
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/theme.dart';
import '../../vps/vps_models.dart';
import '../widgets/widgets.dart';

/// Scaffold for pushed VPS screens: app bar and one column of at most 560 px.
class VpsPage extends StatelessWidget {
  const VpsPage({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.obs.colors;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(title),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Space.s20, Space.s8, Space.s20, Space.s32),
            children: children,
          ),
        ),
      ),
    );
  }
}

/// Body text in the secondary colour, used under titles and in sheets.
TextStyle vpsBodyDim(BuildContext context) {
  final base = Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 15);
  return base.copyWith(color: context.obs.colors.textDim, height: 1.4);
}

/// Message for a failed VPS operation. [VpsException] text is already Russian and
/// user-facing; anything else gets the generic line.
String vpsErrorText(AppLocalizations l, Object error) {
  return error is VpsException ? error.messageRu : l.vpsErrorGeneric;
}

/// Confirmation sheet. Returns true only when the user confirms.
Future<bool> confirmSheet(
  BuildContext context, {
  required String title,
  required String text,
  required String action,
  String? cancelLabel,
  bool destructive = false,
}) async {
  final result = await showAdaptiveSheet<bool>(context, (ctx) {
    final l = AppLocalizations.of(ctx);
    return ObsSheet(
      title: title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(text, style: vpsBodyDim(ctx)),
          const SizedBox(height: Space.s20),
          ObsButton(
            label: action,
            kind: destructive ? ObsButtonKind.destructive : ObsButtonKind.primary,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
          const SizedBox(height: Space.s8),
          ObsButton(
            label: cancelLabel ?? l.vpsCancel,
            kind: ObsButtonKind.secondary,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
        ],
      ),
    );
  });
  return result ?? false;
}

/// Security warning for a changed SSH host key. "Отмена" is the safe default.
/// Returns true only when the user trusts the new key.
Future<bool> showHostKeyChangedDialog(
  BuildContext context,
  HostKeyChangedException error,
) async {
  final result = await showAdaptiveSheet<bool>(context, (ctx) {
    final l = AppLocalizations.of(ctx);
    final c = ctx.obs.colors;
    return ObsSheet(
      title: l.vpsHostKeyTitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.vpsHostKeyText, style: vpsBodyDim(ctx).copyWith(color: c.danger)),
          const SizedBox(height: Space.s16),
          _Fingerprint(label: l.vpsHostKeyExpected, value: error.expected),
          const SizedBox(height: Space.s12),
          _Fingerprint(label: l.vpsHostKeyActual, value: error.actual),
          const SizedBox(height: Space.s20),
          ObsButton(
            label: l.vpsCancel,
            kind: ObsButtonKind.secondary,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          const SizedBox(height: Space.s8),
          ObsButton(
            label: l.vpsHostKeyTrust,
            kind: ObsButtonKind.destructive,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
  });
  return result ?? false;
}

class _Fingerprint extends StatelessWidget {
  const _Fingerprint({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.obs.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: vpsBodyDim(context).copyWith(fontSize: 12)),
        const SizedBox(height: 4),
        SelectableText(value, style: context.obs.mono.copyWith(fontSize: 12, color: c.text)),
      ],
    );
  }
}

/// Copies [text] to the clipboard and confirms with a toast.
Future<void> copyText(BuildContext context, String text, String message) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showObsToast(context, message, kind: ObsToastKind.success);
}

/// Small mono label for server facts (REALITY, IPv4, SSH saved).
class VpsBadge extends StatelessWidget {
  const VpsBadge(this.text, {super.key, this.accent = false});

  final String text;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = context.obs.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent ? c.emberSoft : c.surfaceHi,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: context.obs.mono.copyWith(fontSize: 11, color: accent ? c.ember : c.textDim),
      ),
    );
  }
}
