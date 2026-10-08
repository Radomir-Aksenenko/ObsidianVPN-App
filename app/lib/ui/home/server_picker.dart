import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../widgets/widgets.dart';

/// Opens the server picker. Choosing a row selects that profile and closes the sheet.
/// With no profiles it shows the empty state; [onAddServer] runs after the sheet closes.
Future<void> showServerPicker(
  BuildContext context, {
  required AppState state,
  required VoidCallback onAddServer,
}) {
  return showAdaptiveSheet<void>(context, (sheetContext) {
    final l10n = AppLocalizations.of(sheetContext);
    final profiles = state.profiles;
    final selectedId = state.selectedProfile?.id;

    final Widget body;
    if (profiles.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ObsEmptyState(
          text: l10n.homeNoServers,
          actionLabel: l10n.homeAddServer,
          onAction: () {
            Navigator.of(sheetContext).pop();
            onAddServer();
          },
        ),
      );
    } else {
      body = SingleChildScrollView(
        child: ObsGroup(
          children: [
            for (final p in profiles)
              ObsRow(
                leading: CountryTag(p.countryCode),
                title: p.name,
                subtitle: p.host,
                subtitleMono: true,
                selected: p.id == selectedId,
                trailing: p.id == selectedId
                    ? Icon(
                        Icons.check_rounded,
                        size: 20,
                        color: Theme.of(sheetContext).colorScheme.primary,
                      )
                    : _PingOf(state: state, id: p.id),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await state.selectProfile(p.id);
                },
              ),
          ],
        ),
      );
    }
    return ObsSheet(title: l10n.homeServerPickerTitle, child: body);
  });
}

class _PingOf extends StatelessWidget {
  const _PingOf({required this.state, required this.id});

  final AppState state;
  final String id;

  @override
  Widget build(BuildContext context) {
    final pings = state.pings;
    if (!pings.containsKey(id)) return const SizedBox.shrink();
    return PingBadge(pings[id]);
  }
}
