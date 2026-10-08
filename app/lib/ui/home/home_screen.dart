import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/tokens.dart';

/// Placeholder. The connect dial replaces it later.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.topStart,
      child: Padding(
        padding: const EdgeInsets.only(top: Space.s24),
        child: Text(
          AppLocalizations.of(context).navHome,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
    );
  }
}
