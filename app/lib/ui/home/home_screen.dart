import 'package:flutter/material.dart' hide Durations;
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../platform_info.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../../vpn/vpn_backend.dart';
import '../shell.dart';
import '../widgets/widgets.dart';
import 'connect_dial.dart';
import 'log_sheet.dart';
import 'server_picker.dart';
import 'session_timer.dart';
import 'traffic_format.dart';

class _ToggleIntent extends Intent {
  const _ToggleIntent();
}

/// Fires only when the Home page root itself has focus, so Enter on a focused
/// row or button still activates that row or button.
class _ToggleAction extends Action<_ToggleIntent> {
  _ToggleAction(this.node, this.onToggle);

  final FocusNode node;
  final VoidCallback onToggle;

  @override
  bool isEnabled(_ToggleIntent intent) => node.hasPrimaryFocus;

  @override
  Object? invoke(_ToggleIntent intent) {
    onToggle();
    return null;
  }
}

/// The hero screen: wordmark and status, the connect dial, the server row, live
/// traffic (only while connected and measured) and the split tunnel row.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onOpenSplit});

  /// Called when the split tunnel row is tapped. Defaults to switching the shell
  /// to the Servers tab, where the split editor lives.
  final VoidCallback? onOpenSplit;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FocusNode _focus = FocusNode(debugLabel: 'home');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _goTo(ShellTab tab) => ShellNav.maybeOf(context)?.goTo(tab);

  Future<void> _toggle() async {
    final state = AppState.of(context);
    if (state.selectedProfile == null) {
      _goTo(ShellTab.servers);
      return;
    }
    try {
      await state.toggle();
    } on AppStateException catch (e) {
      if (mounted) showObsToast(context, e.messageRu, kind: ObsToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppState.of(context);
    final status = state.vpnStatus;
    final visible =
        (ShellNav.maybeOf(context)?.tab ?? ShellTab.home) == ShellTab.home;

    final page = LayoutBuilder(
      builder: (context, box) {
        final scrolls = box.maxHeight < 660;
        final top = _TopBar(status: status);
        final hero = _Hero(
          status: status,
          timerActive: visible && status.phase == VpnPhase.connected,
          onToggle: _toggle,
          onOpenLogs: () => showLogSheet(context, state.logs),
        );
        final bottom = _Lower(
          state: state,
          onAddServer: () => _goTo(ShellTab.servers),
          onOpenSplit: widget.onOpenSplit ?? () => _goTo(ShellTab.servers),
        );

        if (scrolls) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                top,
                const SizedBox(height: Space.s24),
                hero,
                const SizedBox(height: Space.s24),
                bottom,
                const SizedBox(height: Space.s16),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            top,
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: Space.s16),
                  child: hero,
                ),
              ),
            ),
            bottom,
            const SizedBox(height: Space.s16),
          ],
        );
      },
    );

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.space): _ToggleIntent(),
        SingleActivator(LogicalKeyboardKey.enter): _ToggleIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): _ToggleIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _ToggleIntent: _ToggleAction(_focus, _toggle),
        },
        child: Focus(focusNode: _focus, autofocus: isDesktop, child: page),
      ),
    );
  }
}

/// Status word shown top right, in the order of [VpnPhase].
@visibleForTesting
String statusWord(AppLocalizations l10n, VpnStatus s) {
  return switch (s.phase) {
    VpnPhase.disconnected => l10n.homeStatusDisconnected,
    VpnPhase.connecting => l10n.homeStatusConnecting(s.stage.clamp(1, 4)),
    VpnPhase.connected => l10n.homeStatusConnected,
    VpnPhase.reconnecting => l10n.homeStatusReconnecting,
    VpnPhase.disconnecting => l10n.homeStatusDisconnecting,
    VpnPhase.error => l10n.homeStatusError,
  };
}

String _actionWord(AppLocalizations l10n, VpnPhase phase) {
  return switch (phase) {
    VpnPhase.disconnected => l10n.homeActionConnect,
    VpnPhase.connecting || VpnPhase.reconnecting => l10n.homeActionCancel,
    VpnPhase.connected => l10n.homeActionDisconnect,
    VpnPhase.error => l10n.homeActionRetry,
    VpnPhase.disconnecting => l10n.homeActionDisconnecting,
  };
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.status});

  final VpnStatus status;

  @override
  Widget build(BuildContext context) {
    final c = context.obs.colors;
    final l10n = AppLocalizations.of(context);
    final color = switch (status.phase) {
      VpnPhase.connected => c.ember,
      VpnPhase.error => c.danger,
      _ => c.textDim,
    };
    return Padding(
      padding: const EdgeInsets.only(top: Space.s16),
      child: Row(
        children: [
          Text(
            l10n.homeWordmark,
            style: Theme.of(context).textTheme.bodyLarge!.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 17,
              letterSpacing: -0.3,
              color: c.textDim,
            ),
          ),
          Expanded(
            child: AnimatedDefaultTextStyle(
              duration: Durations.stateChange,
              style: obsidianMono(
                c,
                size: 11,
                weight: FontWeight.w600,
                letterSpacing: 1.4,
                color: color,
              ),
              child: Text(
                statusWord(l10n, status),
                maxLines: 1,
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.status,
    required this.timerActive,
    required this.onToggle,
    required this.onOpenLogs,
  });

  final VpnStatus status;
  final bool timerActive;
  final VoidCallback onToggle;
  final VoidCallback onOpenLogs;

  @override
  Widget build(BuildContext context) {
    final c = context.obs.colors;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context).textTheme;
    final action = _actionWord(l10n, status.phase);
    final connected = status.phase == VpnPhase.connected;
    final error = status.phase == VpnPhase.error ? status.error : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConnectDial(
          status: status,
          onPressed: onToggle,
          semanticLabel: action,
          semanticValue: statusWord(l10n, status),
        ),
        const SizedBox(height: Space.s24),
        AnimatedSize(
          duration: Durations.stateChange,
          curve: Durations.curve,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (connected) ...[
                SessionTimer(
                  connectedAt: status.connectedAt,
                  active: timerActive,
                  style: context.obs.display,
                ),
                const SizedBox(height: Space.s4),
                Text(
                  action,
                  style: theme.labelLarge!.copyWith(color: c.textDim),
                ),
              ] else ...[
                Text(
                  action,
                  style: theme.titleLarge!.copyWith(
                    color: status.phase == VpnPhase.disconnecting
                        ? c.textDim
                        : c.text,
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: Space.s8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.s16),
                    child: Text(
                      error,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.bodySmall!.copyWith(
                        color: c.danger,
                        height: 1.35,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: onOpenLogs,
                    style: TextButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.s12,
                      ),
                      foregroundColor: c.textDim,
                    ),
                    child: Text(l10n.homeLogs),
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Server row, traffic and split tunnel row.
class _Lower extends StatelessWidget {
  const _Lower({
    required this.state,
    required this.onAddServer,
    required this.onOpenSplit,
  });

  final AppState state;
  final VoidCallback onAddServer;
  final VoidCallback onOpenSplit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = state.vpnStatus;
    final connected = status.phase == VpnPhase.connected;
    final idle =
        status.phase == VpnPhase.disconnected || status.phase == VpnPhase.error;
    final profile = (connected || state.isBusy)
        ? (state.connectedProfile ?? state.selectedProfile)
        : state.selectedProfile;
    final stats = state.stats;

    if (profile == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: Space.s8),
        child: ObsEmptyState(
          text: l10n.homeNoServers,
          actionLabel: l10n.homeAddServer,
          onAction: onAddServer,
        ),
      );
    }

    final c = context.obs.colors;
    final pings = state.pings;
    final serverRow = ObsGroup(
      children: [
        ObsRow(
          leading: CountryTag(profile.countryCode),
          title: profile.name,
          subtitle: profile.host,
          subtitleMono: true,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (pings.containsKey(profile.id)) PingBadge(pings[profile.id]),
              if (idle) ...[
                const SizedBox(width: Space.s8),
                Icon(Icons.chevron_right_rounded, size: 22, color: c.textFaint),
              ],
            ],
          ),
          onTap: idle
              ? () => showServerPicker(
                  context,
                  state: state,
                  onAddServer: onAddServer,
                )
              : null,
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        serverRow,
        AnimatedSize(
          duration: Durations.stateChange,
          curve: Durations.curve,
          alignment: Alignment.topCenter,
          child: connected && stats != null
              ? _TrafficRow(stats: stats)
              : const SizedBox(width: double.infinity, height: Space.s12),
        ),
        ObsGroup(
          children: [
            ObsRow(
              title: l10n.homeSplitTitle,
              subtitle: profile.split.summaryRu(),
              trailing: Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: c.textFaint,
              ),
              onTap: onOpenSplit,
            ),
          ],
        ),
      ],
    );
  }
}

class _TrafficRow extends StatelessWidget {
  const _TrafficRow({required this.stats});

  final TrafficStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.obs.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s20),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _TrafficColumn(
                icon: Icons.south_rounded,
                label: l10n.trafficDownload,
                rate: formatRate(stats.rxBps, l10n),
                total: formatBytes(stats.rxBytes, l10n),
              ),
            ),
            Container(width: 1, color: c.line),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: Space.s20),
                child: _TrafficColumn(
                  icon: Icons.north_rounded,
                  label: l10n.trafficUpload,
                  rate: formatRate(stats.txBps, l10n),
                  total: formatBytes(stats.txBytes, l10n),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrafficColumn extends StatelessWidget {
  const _TrafficColumn({
    required this.icon,
    required this.label,
    required this.rate,
    required this.total,
  });

  final IconData icon;
  final String label;
  final FormattedRate rate;
  final String total;

  @override
  Widget build(BuildContext context) {
    final c = context.obs.colors;
    final caption = Theme.of(context).textTheme.bodySmall!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: c.textFaint),
            const SizedBox(width: Space.s4),
            Text(label, style: caption),
          ],
        ),
        const SizedBox(height: Space.s8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(rate.value, style: context.obs.display),
              const SizedBox(width: Space.s4),
              Text(rate.unit, style: caption.copyWith(color: c.textFaint)),
            ],
          ),
        ),
        const SizedBox(height: Space.s4),
        Text(
          AppLocalizations.of(context).trafficTotal(total),
          style: caption.copyWith(color: c.textFaint),
        ),
      ],
    );
  }
}
