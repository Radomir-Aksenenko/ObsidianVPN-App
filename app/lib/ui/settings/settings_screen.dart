import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/tokens.dart';

/// Placeholder. Settings, logs and about replace it later.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.topStart,
      child: Padding(
        padding: const EdgeInsets.only(top: Space.s24),
        child: Text(
          AppLocalizations.of(context).navSettings,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
    );
  }
}
