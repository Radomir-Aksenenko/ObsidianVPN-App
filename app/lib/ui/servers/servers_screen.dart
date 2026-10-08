import 'package:flutter/material.dart' hide Durations;
import 'package:flutter/services.dart';

import '../../core/models/profile.dart';
import '../../l10n/app_localizations.dart';
import '../../platform_info.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../shell.dart';
import '../widgets/widgets.dart';
import 'add_key_sheet.dart';
import 'qr_scan_screen.dart';
import 'server_actions.dart';

/// Servers tab. Favorites come first. Tap selects a server; the more button opens its actions.
/// Footer: add by key, and scan a QR code where the camera is available.
class ServersScreen extends StatefulWidget {
  const ServersScreen({super.key});

  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen> {
  final FocusNode _focus = FocusNode(debugLabel: 'servers');
  bool _wasVisible = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// Takes the keyboard focus when the tab becomes visible, so Ctrl+V reaches this page
  /// (another tab of the shell holds the focus until then).
  void _focusWhenShown(bool visible) {
    if (visible && !_wasVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_editingText()) _focus.requestFocus();
      });
    }
    _wasVisible = visible;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = AppState.of(context);
    final profiles = state.profiles;
    final favorites = [
      for (final p in profiles)
        if (p.isFavorite) p,
    ];
    final others = [
      for (final p in profiles)
        if (!p.isFavorite) p,
    ];
    final selectedId = state.selectedProfile?.id;
    final pings = state.pings;
    final canScanQr = isMobile || isMacOS;

    List<Widget> rows(List<ServerProfile> list) => [
      for (final p in list)
        _ServerRow(
          profile: p,
          selected: p.id == selectedId,
          pinged: pings.containsKey(p.id),
          ping: pings[p.id],
          onSelect: () => state.selectProfile(p.id),
          onMore: () => showServerActions(context, p),
        ),
    ];

    final List<Widget> sections;
    if (profiles.isEmpty) {
      sections = [
        ObsEmptyState(
          text: l10n.serversEmpty,
          actionLabel: l10n.serversAddKey,
          onAction: () => showAddKeySheet(context),
        ),
      ];
    } else {
      sections = [
        if (favorites.isNotEmpty)
          ObsGroup(
            label: l10n.serversSectionFavorites,
            children: rows(favorites),
          ),
        if (others.isNotEmpty)
          ObsGroup(
            label: favorites.isEmpty ? null : l10n.serversSectionAll,
            children: rows(others),
          ),
      ];
    }

    final footer = <Widget>[
      if (profiles.isNotEmpty)
        ObsButton(
          label: l10n.serversAddKey,
          icon: Icons.add_rounded,
          onPressed: () => showAddKeySheet(context),
        ),
      if (canScanQr) ...[
        if (profiles.isNotEmpty) const SizedBox(height: Space.s8),
        ObsButton(
          label: l10n.serversScanQr,
          kind: ObsButtonKind.secondary,
          icon: Icons.qr_code_scanner_rounded,
          onPressed: () => _scanQr(context),
        ),
      ],
    ];

    // The pages of the shell stay alive in an IndexedStack, so the shortcut must also
    // check that this tab is the visible one.
    final visible = (ShellNav.maybeOf(context)?.tab ?? ShellTab.servers) == ShellTab.servers;
    _focusWhenShown(visible);
    return CallbackShortcuts(
      bindings: _pasteBindings(context, visible),
      child: Focus(
        focusNode: _focus,
        child: TabPage(
          title: l10n.serversTitle,
          footer: footer.isEmpty
              ? null
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: footer,
                ),
          children: sections,
        ),
      ),
    );
  }

  /// Ctrl+V (Cmd+V on macOS) opens the add sheet prefilled from the clipboard.
  Map<ShortcutActivator, VoidCallback> _pasteBindings(BuildContext context, bool visible) {
    if (!isDesktop || !visible) return const <ShortcutActivator, VoidCallback>{};
    // No key repeat: holding Ctrl+V must not stack several sheets.
    final activator = isMacOS
        ? const SingleActivator(LogicalKeyboardKey.keyV, meta: true, includeRepeats: false)
        : const SingleActivator(LogicalKeyboardKey.keyV, control: true, includeRepeats: false);
    return <ShortcutActivator, VoidCallback>{
      activator: () {
        // Inside a text field Ctrl+V pastes into that field.
        if (_editingText()) return;
        _pasteFromClipboard(context);
      },
    };
  }


  Future<void> _pasteFromClipboard(BuildContext context) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!context.mounted) return;
    if (text.isEmpty) {
      showObsToast(context, AppLocalizations.of(context).serversClipboardEmpty);
      return;
    }
    await showAddKeySheet(context, initialText: text);
  }

  Future<void> _scanQr(BuildContext context) async {
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const QrScanScreen()),
    );
    if (value == null || !context.mounted) return;
    await showAddKeySheet(context, initialText: value);
  }
}

/// True when the focused widget is a text field.
bool _editingText() {
  final focus = FocusManager.instance.primaryFocus?.context;
  if (focus == null) return false;
  return focus.widget is EditableText ||
      focus.findAncestorWidgetOfExactType<EditableText>() != null;
}

class _ServerRow extends StatefulWidget {
  const _ServerRow({
    required this.profile,
    required this.selected,
    required this.pinged,
    required this.ping,
    required this.onSelect,
    required this.onMore,
  });

  final ServerProfile profile;
  final bool selected;
  final bool pinged;
  final int? ping;
  final VoidCallback onSelect;
  final VoidCallback onMore;

  @override
  State<_ServerRow> createState() => _ServerRowState();
}

class _ServerRowState extends State<_ServerRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.obs.colors;
    final p = widget.profile;
    final portSuffix = p.port == 443 ? '' : ':${p.port}';
    // Touch platforms always show the more button. Desktop shows it on hover.
    final showMore = isMobile || _hover;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: ObsRow(
        leading: CountryTag(p.countryCode),
        title: p.name,
        subtitle: '${p.host}$portSuffix',
        subtitleMono: true,
        selected: widget.selected,
        semanticLabel: p.name,
        onTap: widget.onSelect,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.pinged) PingBadge(widget.ping),
            if (widget.selected) ...[
              const SizedBox(width: Space.s8),
              Icon(Icons.check_rounded, size: 20, color: c.ember),
            ],
            if (showMore) ...[
              const SizedBox(width: Space.s4),
              IconButton(
                tooltip: l10n.serversMore,
                constraints: const BoxConstraints.tightFor(
                  width: 40,
                  height: 40,
                ),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.more_horiz_rounded,
                  size: 22,
                  color: c.textDim,
                ),
                onPressed: widget.onMore,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
