import 'package:flutter/material.dart' hide Durations;

import '../../core/models/profile.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../../vps/deployer.dart';
import '../../vps/key_issuer.dart';
import '../widgets/widgets.dart';
import 'deploy_wizard_screen.dart';
import 'issue_key_sheet.dart';
import 'issued_key_screen.dart';
import 'server_manage_screen.dart';
import 'vps_common.dart';

/// Access tab: own VPS servers (deploy, manage) and keys issued from them.
class AccessScreen extends StatelessWidget {
  const AccessScreen({super.key, this.deployer});

  /// Passed to the deploy and manage screens. Tests inject a fake one.
  final VpsDeployer? deployer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.obs.colors;
    final state = AppState.of(context);
    final servers = state.profiles.where((p) => p.source == ProfileSource.vps).toList();
    final keys = state.issuedKeys;
    final hasServers = servers.isNotEmpty;

    void openDeploy() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => DeployWizardScreen(deployer: deployer)),
      );
    }

    if (!hasServers && keys.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.s20, Space.s24, Space.s20, Space.s24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.navAccess, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: Space.s24),
                ObsEmptyState(
                  text: l.accessEmpty,
                  actionLabel: l.accessDeploy,
                  onAction: openDeploy,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.s20, Space.s24, Space.s20, Space.s32),
          children: [
            Text(l.navAccess, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: Space.s24),
            SectionLabel(l.accessServers),
            const SizedBox(height: Space.s8),
            ObsGroup(
              children: <Widget>[
                for (final profile in servers)
                  _ServerRow(
                    profile: profile,
                    ping: state.pings[profile.id],
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ServerManageScreen(
                          profileId: profile.id,
                          deployer: deployer,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Space.s12),
            ObsButton(
              label: l.accessDeploy,
              kind: ObsButtonKind.secondary,
              onPressed: openDeploy,
            ),
            const SizedBox(height: Space.s24),
            SectionLabel(l.accessKeys),
            const SizedBox(height: Space.s8),
            if (keys.isEmpty)
              Text(l.accessKeysEmpty, style: vpsBodyDim(context).copyWith(fontSize: 13))
            else
              ObsGroup(
                children: <Widget>[
                  for (final key in keys)
                    _KeyRow(issued: key),
                ],
              ),
            const SizedBox(height: Space.s12),
            ObsButton(
              label: l.accessIssue,
              onPressed: hasServers ? () => showIssueKeySheet(context) : null,
            ),
            if (!hasServers) ...[
              const SizedBox(height: Space.s8),
              Text(
                l.accessIssueNeedsServer,
                style: vpsBodyDim(context).copyWith(fontSize: 12, color: c.textDim),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ServerRow extends StatelessWidget {
  const _ServerRow({required this.profile, required this.ping, required this.onTap});

  final ServerProfile profile;
  final int? ping;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final vps = profile.vps;
    return ObsRow(
      title: profile.name,
      subtitle: vps == null ? profile.host : '${vps.user}@${vps.host}:${vps.port}',
      subtitleMono: true,
      leading: CountryTag(profile.countryCode),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (profile.needsUpdate) ...[
            VpsBadge(l.accessNeedsUpdate, accent: true),
            const SizedBox(width: Space.s8),
          ],
          PingBadge(ping),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.issued});

  final IssuedKey issued;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.obs.colors;
    return ObsRow(
      title: issued.name,
      subtitle: '${l.accessDevices(issued.devices)} · ${_validity(l)}',
      trailing: PopupMenuButton<String>(
        tooltip: l.accessKeyMore,
        icon: Icon(Icons.more_horiz_rounded, color: c.textDim),
        onSelected: (_) => _delete(context),
        itemBuilder: (_) => <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            value: 'delete',
            child: Text(l.accessKeyDelete, style: TextStyle(color: c.danger)),
          ),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => IssuedKeyScreen(issued: issued)),
      ),
    );
  }

  String _validity(AppLocalizations l) {
    if (issued.days == 0) return l.accessForever;
    final expires = issued.created.add(Duration(days: issued.days));
    final left = expires.difference(DateTime.now().toUtc()).inDays;
    return left <= 0 ? l.accessExpired : l.accessDaysLeft(left);
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
    await AppState.of(context).removeIssuedKey(issued.id);
    if (context.mounted) showObsToast(context, l.accessKeyDeleted, kind: ObsToastKind.success);
  }
}
