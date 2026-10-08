import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/tokens.dart';

/// Placeholder. The VPS deploy and access flow replaces it later.
class AccessScreen extends StatelessWidget {
  const AccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.topStart,
      child: Padding(
        padding: const EdgeInsets.only(top: Space.s24),
        child: Text(
          AppLocalizations.of(context).navAccess,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
    );
  }
}
