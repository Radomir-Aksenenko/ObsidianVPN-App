import 'package:flutter/material.dart' hide Durations;
import 'package:flutter/services.dart' show LengthLimitingTextInputFormatter;

import '../../core/codec/obsidian_key.dart';
import '../../core/models/profile.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../../vps/key_issuer.dart';
import '../../vps/vps_models.dart';
import '../widgets/widgets.dart';
import 'issued_key_screen.dart';
import 'vps_common.dart';

/// Opens the "new key" sheet. After a key is issued, opens its [IssuedKeyScreen].
Future<void> showIssueKeySheet(BuildContext context, {String? serverId}) async {
  final issued = await showAdaptiveSheet<IssuedKey>(
    context,
    (ctx) => _IssueKeySheet(initialServerId: serverId),
  );
  if (issued == null || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => IssuedKeyScreen(issued: issued)),
  );
}

class _IssueKeySheet extends StatefulWidget {
  const _IssueKeySheet({this.initialServerId});

  final String? initialServerId;

  @override
  State<_IssueKeySheet> createState() => _IssueKeySheetState();
}

class _IssueKeySheetState extends State<_IssueKeySheet> {
  final TextEditingController _name = TextEditingController();
  bool _nameReady = false;
  int _days = 30;
  int _devices = 3;
  String? _serverId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _serverId = widget.initialServerId;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_nameReady) {
      _nameReady = true;
      _name.text = AppLocalizations.of(context).accessIssueNameHint;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  List<ServerProfile> _ownServers(AppState state) {
    return state.profiles.where((p) => p.source == ProfileSource.vps).toList();
  }

  String? _selectedId(List<ServerProfile> servers) {
    if (servers.isEmpty) return null;
    for (final s in servers) {
      if (s.id == _serverId) return s.id;
    }
    return servers.first.id;
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    final state = AppState.of(context);
    final servers = _ownServers(state);
    final serverId = _selectedId(servers);
    if (serverId == null) {
      showObsToast(context, l.accessIssueNeedsServer, kind: ObsToastKind.error);
      return;
    }
    final typed = _name.text.trim();
    final name = typed.isEmpty ? l.accessIssueNameHint : typed;
    setState(() => _busy = true);
    try {
      final key = await state.ownerKey(serverId);
      if (key == null) throw VpsException(l.vpsOwnerKeyMissing);
      final issued = issueKey(
        serverConfig: parseKey(key),
        name: name,
        days: _days,
        devices: _devices,
        serverId: serverId,
      );
      await state.addIssuedKey(issued);
      if (!mounted) return;
      Navigator.of(context).pop(issued);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showObsToast(context, vpsErrorText(l, e), kind: ObsToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = AppState.of(context);
    final servers = _ownServers(state);
    final selected = _selectedId(servers);
    return ObsSheet(
      title: l.accessIssueTitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ObsTextField(
            controller: _name,
            label: l.accessIssueName,
            inputFormatters: [LengthLimitingTextInputFormatter(kMaxKeyNameLength)],
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: Space.s20),
          SectionLabel(l.accessIssueValidity),
          const SizedBox(height: Space.s8),
          _ValidityPicker(
            value: _days,
            options: <({int days, String label})>[
              (days: 7, label: l.accessValidity7),
              (days: 30, label: l.accessValidity30),
              (days: 90, label: l.accessValidity90),
              (days: 0, label: l.accessForever),
            ],
            onChanged: (value) => setState(() => _days = value),
          ),
          const SizedBox(height: Space.s20),
          ObsGroup(
            children: <Widget>[
              ObsRow(
                title: l.accessIssueDevices,
                trailing: _Stepper(
                  value: _devices,
                  lessLabel: l.accessFewer,
                  moreLabel: l.accessMore,
                  onChanged: (value) => setState(() => _devices = value),
                ),
              ),
            ],
          ),
          if (servers.length > 1) ...[
            const SizedBox(height: Space.s20),
            SectionLabel(l.accessIssueServer),
            const SizedBox(height: Space.s8),
            ObsGroup(
              children: <Widget>[
                for (final s in servers)
                  ObsRow(
                    title: s.name,
                    subtitle: s.host,
                    subtitleMono: true,
                    selected: s.id == selected,
                    onTap: () => setState(() => _serverId = s.id),
                  ),
              ],
            ),
          ],
          const SizedBox(height: Space.s24),
          ObsButton(
            label: l.accessIssueSubmit,
            loading: _busy,
            onPressed: _busy || selected == null ? null : _submit,
          ),
        ],
      ),
    );
  }
}

/// Validity choice: 7, 30, 90 days or no expiry (0). ObsSegmented takes at most three.
class _ValidityPicker extends StatelessWidget {
  const _ValidityPicker({required this.value, required this.options, required this.onChanged});

  final int value;
  final List<({int days, String label})> options;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.obs.colors;
    return Wrap(
      spacing: Space.s8,
      runSpacing: Space.s8,
      children: <Widget>[
        for (final option in options)
          InkWell(
            borderRadius: BorderRadius.circular(Radii.chip),
            onTap: () => onChanged(option.days),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: Space.s16, vertical: Space.s8),
              decoration: BoxDecoration(
                color: option.days == value ? c.emberSoft : c.surfaceHi,
                borderRadius: BorderRadius.circular(Radii.chip),
                border: Border.all(
                  color: option.days == value ? c.ember : Colors.transparent,
                ),
              ),
              child: Text(
                option.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: option.days == value ? c.ember : c.text,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.lessLabel,
    required this.moreLabel,
    required this.onChanged,
  });

  final int value;
  final String lessLabel;
  final String moreLabel;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.obs.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: lessLabel,
          icon: const Icon(Icons.remove_rounded, size: 22),
          onPressed: value > kMinKeyDevices ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 32,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: context.obs.mono.copyWith(fontSize: 15, color: c.text),
          ),
        ),
        IconButton(
          tooltip: moreLabel,
          icon: const Icon(Icons.add_rounded, size: 22),
          onPressed: value < kMaxKeyDevices ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}
