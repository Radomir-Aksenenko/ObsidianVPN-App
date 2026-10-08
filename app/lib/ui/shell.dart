import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/app_localizations.dart';
import '../platform_info.dart';
import '../theme/theme.dart';
import 'home/home_screen.dart';
import 'servers/servers_screen.dart';
import 'settings/settings_screen.dart';
import 'vps/access_screen.dart';
import 'widgets/desktop_title_bar.dart';

const double _wideBreakpoint = 720;
const double _bottomBarHeight = 64;
const double _navItemHeight = 64;
const double _railWidth = 76;
const double _contentMaxWidth = 560;
const double _macTitleInset = 28;

/// The four top-level destinations, in nav order.
enum ShellTab { home, servers, access, settings }

/// Lets screens read and change the active tab: `ShellNav.maybeOf(context)?.goTo(ShellTab.servers)`.
/// Depending on it rebuilds the widget when the tab changes, so a screen can tell
/// whether it is visible (the pages stay alive in an IndexedStack).
class ShellNav extends InheritedWidget {
  const ShellNav({
    super.key,
    required this.tab,
    required this.goTo,
    required super.child,
  });

  /// The visible tab.
  final ShellTab tab;

  /// Switches to [tab].
  final ValueChanged<ShellTab> goTo;

  /// The nearest shell navigation, or null outside a [Shell] (tests).
  static ShellNav? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellNav>();

  @override
  bool updateShouldNotify(ShellNav old) => old.tab != tab;
}

/// Adaptive scaffold: bottom bar below 720 px, left rail from 720 px up.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final destinations = <_Destination>[
      _Destination(
        icon: Icons.home_outlined,
        activeIcon: Icons.home_rounded,
        label: l10n.navHome,
      ),
      _Destination(
        icon: Icons.dns_outlined,
        activeIcon: Icons.dns_rounded,
        label: l10n.navServers,
      ),
      _Destination(
        icon: Icons.vpn_key_outlined,
        activeIcon: Icons.vpn_key_rounded,
        label: l10n.navAccess,
      ),
      _Destination(
        icon: Icons.settings_outlined,
        activeIcon: Icons.settings_rounded,
        label: l10n.navSettings,
      ),
    ];
    const pages = <Widget>[
      HomeScreen(),
      ServersScreen(),
      AccessScreen(),
      SettingsScreen(),
    ];

    void select(int i) => setState(() => _index = i);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _wideBreakpoint;
        final gutter = wide ? Space.gutterWide : Space.gutterNarrow;

        final pagesView = Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: gutter),
              child: IndexedStack(
                index: _index,
                sizing: StackFit.expand,
                children: pages,
              ),
            ),
          ),
        );

        final body = wide
            ? Row(
                children: [
                  _NavRail(
                    key: const ValueKey('shell-nav'),
                    destinations: destinations,
                    selected: _index,
                    onSelected: select,
                  ),
                  Expanded(child: pagesView),
                ],
              )
            : pagesView;

        final scaffold = Scaffold(
          bottomNavigationBar: wide
              ? null
              : _BottomBar(
                  key: const ValueKey('shell-nav'),
                  destinations: destinations,
                  selected: _index,
                  onSelected: select,
                ),
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                if (usesCustomTitleBar) const DesktopTitleBar(),
                if (isMacOS)
                  DragToMoveArea(
                    child: const SizedBox(
                      height: _macTitleInset,
                      width: double.infinity,
                    ),
                  ),
                Expanded(child: body),
              ],
            ),
          ),
        );

        return ShellNav(
          tab: ShellTab.values[_index],
          goTo: (tab) => select(tab.index),
          child: scaffold,
        );
      },
    );
  }
}

class _Destination {
  const _Destination({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    super.key,
    required this.destinations,
    required this.selected,
    required this.onSelected,
  });

  final List<_Destination> destinations;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.obs.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Material(
        color: c.surface,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: _bottomBarHeight,
            child: Row(
              children: [
                for (var i = 0; i < destinations.length; i++)
                  Expanded(
                    child: _NavItem(
                      destination: destinations[i],
                      selected: i == selected,
                      onTap: () => onSelected(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavRail extends StatelessWidget {
  const _NavRail({
    super.key,
    required this.destinations,
    required this.selected,
    required this.onSelected,
  });

  final List<_Destination> destinations;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.obs.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: c.line)),
      ),
      child: Material(
        color: c.surface,
        child: SizedBox(
          width: _railWidth,
          child: Column(
            children: [
              const SizedBox(height: Space.s12),
              for (var i = 0; i < destinations.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.s8,
                    vertical: 2,
                  ),
                  child: SizedBox(
                    height: _navItemHeight - 4,
                    child: _NavItem(
                      destination: destinations[i],
                      selected: i == selected,
                      onTap: () => onSelected(i),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.obs.colors;
    final color = selected ? c.ember : c.textDim;
    final labelStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      fontSize: 12,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
      color: color,
    );

    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        hoverColor: c.surfaceHi,
        borderRadius: BorderRadius.circular(Radii.button),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.s4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? destination.activeIcon : destination.icon,
                size: 22,
                color: color,
              ),
              const SizedBox(height: Space.s4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(destination.label, maxLines: 1, style: labelStyle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
