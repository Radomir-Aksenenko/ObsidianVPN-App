import 'package:flutter/material.dart' hide Durations;
import 'package:qr_flutter/qr_flutter.dart';

import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../../vps/key_issuer.dart';
import '../widgets/widgets.dart';
import 'vps_common.dart';

/// Shows an issued key: QR code, facts, copy buttons and the key text.
class IssuedKeyScreen extends StatelessWidget {
  const IssuedKeyScreen({super.key, required this.issued});

  final IssuedKey issued;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.obs.colors;
    final state = AppState.of(context);
    final serverName = state.profileById(issued.serverId)?.name ?? issued.serverId;
    final expires = issued.days == 0
        ? null
        : issued.created.add(Duration(days: issued.days)).toLocal();
    final now = DateTime.now();
    final expired = expires != null && !expires.isAfter(now);
    final expiryAside = expires == null
        ? null
        : (expired ? l.accessExpired : l.accessDaysLeft(expires.difference(now).inDays));

    return VpsPage(
      title: l.accessKeyTitle,
      children: [
        Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final side = constraints.maxWidth < 280 ? constraints.maxWidth : 280.0;
              return Container(
                width: side,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(
                  data: issued.uri,
                  version: QrVersions.auto,
                  size: side - 32,
                  backgroundColor: Colors.white,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: Space.s12),
        Text(
          l.accessKeyQrHint,
          textAlign: TextAlign.center,
          style: vpsBodyDim(context).copyWith(fontSize: 12),
        ),
        const SizedBox(height: Space.s20),
        Text(
          issued.name,
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.text),
        ),
        const SizedBox(height: Space.s16),
        ObsGroup(
          children: <Widget>[
            ObsRow(title: l.accessKeyServer, subtitle: serverName),
            ObsRow(
              title: l.accessKeyExpiry,
              subtitle: expires == null
                  ? l.accessForever
                  : l.accessKeyExpiresOn(_formatDate(expires)),
              trailing: expiryAside == null
                  ? null
                  : Text(
                      expiryAside,
                      style: context.obs.mono.copyWith(fontSize: 12, color: expired ? c.danger : c.textDim),
                    ),
            ),
            ObsRow(
              title: l.accessKeyDevicesLabel,
              trailing: Text(
                '${issued.devices}',
                style: context.obs.mono.copyWith(fontSize: 14, color: c.text),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.s24),
        ObsButton(
          label: l.accessKeyCopyLink,
          onPressed: () => copyText(context, issued.uri, l.accessCopied),
        ),
        const SizedBox(height: Space.s8),
        ObsButton(
          label: l.accessKeyCopyKey,
          kind: ObsButtonKind.secondary,
          onPressed: () => copyText(context, issued.key, l.accessCopied),
        ),
        const SizedBox(height: Space.s16),
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(Radii.row),
            border: Border.all(color: c.line),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              shape: const RoundedRectangleBorder(side: BorderSide.none),
              collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
              tilePadding: const EdgeInsets.symmetric(horizontal: Space.s16),
              childrenPadding: const EdgeInsets.fromLTRB(Space.s16, 0, Space.s16, Space.s16),
              title: Text(
                l.accessKeyShowKey,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text),
              ),
              children: <Widget>[
                SelectableText(
                  issued.key,
                  style: context.obs.mono.copyWith(fontSize: 13, color: c.text),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.s24),
        ObsButton(
          label: l.accessKeyDelete,
          kind: ObsButtonKind.destructive,
          onPressed: () => _delete(context),
        ),
      ],
    );
  }

  Future<void> _delete(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final ok = await confirmSheet(
      context,
      title: l.accessKeyDeleteTitle,
      text: l.accessKeyDeleteText(issued.name),
      action: l.accessKeyDelete,
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final navigator = Navigator.of(context);
    await AppState.of(context).removeIssuedKey(issued.id);
    if (context.mounted) showObsToast(context, l.accessKeyDeleted, kind: ObsToastKind.success);
    navigator.pop();
  }
}

String _formatDate(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year}';
}
