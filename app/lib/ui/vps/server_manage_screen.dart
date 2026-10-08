import 'package:flutter/material.dart' hide Durations;

import '../../l10n/app_localizations.dart';
import '../../core/codec/client_config.dart';
import '../../core/codec/obsidian_key.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../../vps/deployer.dart';
import '../../vps/owner_key.dart';
import '../../vps/vps_models.dart';
import '../widgets/widgets.dart';
import 'deploy_progress.dart';
import 'ssh_form.dart';
import 'vps_common.dart';

/// Manages one VPS profile: SNI, IPv6, core version, SSH access and reset.
///
/// Settings that change the owner key (SNI, IPv6, reset) rebuild it and save it. Keys
/// issued earlier keep the old settings, so the screen says they must be issued again.
class ServerManageScreen extends StatefulWidget {
  const ServerManageScreen({super.key, required this.profileId, this.deployer});

  final String profileId;

  /// Replaces the real deployer in tests.
  final VpsDeployer? deployer;

  @override
  State<ServerManageScreen> createState() => _ServerManageScreenState();
}

class _ServerManageScreenState extends State<ServerManageScreen> {
  late final VpsDeployer _deployer = widget.deployer ?? VpsDeployer();
  final TextEditingController _sni = TextEditingController();
  String? _sniError;
  VpsCredentials? _creds;
  bool _ipv6 = false;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _load();
    }
  }

  @override
  void dispose() {
    _sni.dispose();
    super.dispose();
  }

  bool get _canManage {
    final creds = _creds;
    return creds != null &&
        (creds.usesKey || (creds.password ?? '').isNotEmpty);
  }

  Future<void> _load() async {
    final state = AppState.of(context);
    final creds = await state.vpsCredentials(widget.profileId);
    final cfg = await _readOwner(state);
    if (!mounted) return;
    setState(() {
      _creds = creds;
      if (cfg != null) {
        _ipv6 = cfg.enableIpv6;
        _sni.text = cfg.realitySni.isEmpty ? kDefaultSni : cfg.realitySni;
      }
    });
  }

  Future<ClientConfig?> _readOwner(AppState state) async {
    final key = await state.ownerKey(widget.profileId);
    if (key == null) return null;
    try {
      return parseKey(key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _reloadCreds() async {
    final state = AppState.of(context);
    final creds = await state.vpsCredentials(widget.profileId);
    if (mounted) setState(() => _creds = creds);
  }

  VpsCredentials _pinned(VpsCredentials creds, String? trustedHostKey) {
    return trustedHostKey == null
        ? creds
        : creds.copyWith(hostKeyFingerprint: trustedHostKey);
  }

  /// Rebuilds the owner key from the stored one with the new setting, then saves it.
  Future<void> _saveOwner(
    AppState state, {
    String? hostKey,
    String? sni,
    bool? ipv6,
  }) async {
    final l = AppLocalizations.of(context);
    final key = await state.ownerKey(widget.profileId);
    if (key == null) throw VpsException(l.vpsOwnerKeyMissing);
    final rebuilt = rebuildOwnerKey(parseKey(key), sni: sni, ipv6: ipv6);
    await state.updateVpsProfile(
      widget.profileId,
      hostKey: hostKey,
      ownerKey: rebuilt.key,
      ownerConfig: rebuilt.config,
    );
  }

  Future<void> _applySni() async {
    final l = AppLocalizations.of(context);
    final value = _sni.text.trim().toLowerCase();
    final valid = isValidSni(value);
    setState(() => _sniError = valid ? null : l.vpsSniInvalid);
    final creds = _creds;
    if (!valid || creds == null) return;
    final state = AppState.of(context);
    final outcome = await showDeployProgressSheet<String>(
      context,
      title: l.vpsSheetSni,
      start: (trusted) => _deployer.changeSni(_pinned(creds, trusted), value),
    );
    if (outcome == null || !mounted) return;
    await _saveOwnerSafely(state, hostKey: outcome.hostKey, sni: outcome.value);
    if (!mounted) return;
    setState(() => _sni.text = outcome.value);
    showObsToast(context, l.vpsSniDone, kind: ObsToastKind.success);
  }

  Future<void> _setIpv6(bool enabled) async {
    final l = AppLocalizations.of(context);
    final creds = _creds;
    if (creds == null) return;
    final state = AppState.of(context);
    final outcome = await showDeployProgressSheet<bool>(
      context,
      title: l.vpsSheetIpv6,
      start: (trusted) => _deployer.setIpv6(_pinned(creds, trusted), enabled),
    );
    if (outcome == null || !mounted) return;
    await _saveOwnerSafely(
      state,
      hostKey: outcome.hostKey,
      ipv6: outcome.value,
    );
    if (!mounted) return;
    setState(() => _ipv6 = outcome.value);
    showObsToast(context, l.vpsIpv6Done, kind: ObsToastKind.success);
  }

  Future<void> _checkVersion() async {
    final l = AppLocalizations.of(context);
    final creds = _creds;
    if (creds == null) return;
    final state = AppState.of(context);
    final outcome = await showDeployProgressSheet<VpsStatus>(
      context,
      title: l.vpsSheetCheck,
      start: (trusted) => _deployer.checkVersion(_pinned(creds, trusted)),
    );
    if (outcome == null || !mounted) return;
    final status = outcome.value;
    await state.updateVpsProfile(
      widget.profileId,
      hostKey: outcome.hostKey,
      serverVersion: status.version,
      needsUpdate: !status.upToDate,
    );
    if (!mounted) return;
    showObsToast(
      context,
      status.upToDate ? l.vpsCheckLatest : l.vpsCheckOutdated,
      kind: ObsToastKind.info,
    );
  }

  Future<void> _update() async {
    final l = AppLocalizations.of(context);
    final creds = _creds;
    if (creds == null) return;
    final state = AppState.of(context);
    final outcome = await showDeployProgressSheet<UpdateResult>(
      context,
      title: l.vpsSheetUpdate,
      start: (trusted) => _deployer.update(_pinned(creds, trusted)),
    );
    if (outcome == null || !mounted) return;
    try {
      final portChanged = await state.applyVpsUpdate(
        widget.profileId,
        outcome.value,
        serverVersion: _deployer.bundledVersion,
        hostKey: outcome.hostKey,
      );
      if (!mounted) return;
      showObsToast(
        context,
        portChanged ? l.vpsUpdateDonePortChanged : l.vpsUpdateDone,
        kind: ObsToastKind.success,
      );
    } on AppStateException catch (e) {
      if (mounted) showObsToast(context, e.messageRu, kind: ObsToastKind.error);
    }
  }

  Future<void> _editSsh() async {
    final l = AppLocalizations.of(context);
    final current = _creds;
    if (current == null) return;
    final form = SshFormController(initial: current);
    final saved = await showAdaptiveSheet<VpsCredentials>(context, (ctx) {
      return ObsSheet(
        title: l.vpsSshSection,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SshForm(controller: form),
            const SizedBox(height: Space.s24),
            ObsButton(
              label: l.vpsSaveSsh,
              onPressed: () {
                final creds = form.build(l);
                if (creds != null) Navigator.of(ctx).pop(creds);
              },
            ),
          ],
        ),
      );
    });
    form.dispose();
    if (saved == null || !mounted) return;
    final state = AppState.of(context);
    await state.updateVpsProfile(widget.profileId, creds: saved);
    await _reloadCreds();
    if (!mounted) return;
    showObsToast(context, l.vpsSshSaved, kind: ObsToastKind.success);
  }

  Future<void> _reset() async {
    final l = AppLocalizations.of(context);
    final creds = _creds;
    if (creds == null) return;
    final ok = await confirmSheet(
      context,
      title: l.vpsResetTitle,
      text: l.vpsResetText,
      action: l.vpsResetConfirm,
      destructive: true,
    );
    if (!ok || !mounted) return;
    final state = AppState.of(context);
    final outcome = await showDeployProgressSheet<ResetResult>(
      context,
      title: l.vpsSheetReset,
      start: (trusted) => _deployer.reset(_pinned(creds, trusted)),
    );
    if (outcome == null || !mounted) return;
    final result = outcome.value;
    final removed = await state.applyVpsReset(
      widget.profileId,
      result,
      hostKey: outcome.hostKey,
    );
    if (!mounted) return;
    setState(() {
      _ipv6 = result.ownerConfig.enableIpv6;
      _sni.text = result.realitySni.isEmpty ? kDefaultSni : result.realitySni;
    });
    showObsToast(
      context,
      removed > 0 ? l.vpsResetDoneRevoked(removed) : l.vpsResetDone,
      kind: ObsToastKind.success,
    );
  }

  /// Like [_saveOwner], but a missing owner key shows a toast instead of throwing.
  Future<void> _saveOwnerSafely(
    AppState state, {
    String? hostKey,
    String? sni,
    bool? ipv6,
  }) async {
    try {
      await _saveOwner(state, hostKey: hostKey, sni: sni, ipv6: ipv6);
    } on VpsException catch (e) {
      if (mounted) showObsToast(context, e.messageRu, kind: ObsToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.obs.colors;
    final state = AppState.of(context);
    final profile = state.profileById(widget.profileId);
    final vps = profile?.vps;
    if (profile == null || vps == null) {
      return VpsPage(
        title: l.vpsManageTitle,
        children: [Text(l.vpsErrorGeneric)],
      );
    }
    final canManage = _canManage;
    final showBanner = _creds != null && !canManage;
    return VpsPage(
      title: l.vpsManageTitle,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${vps.user}@${vps.host}:${vps.port}',
                style: context.obs.mono.copyWith(fontSize: 15, color: c.text),
              ),
            ),
            PingBadge(state.pings[profile.id]),
          ],
        ),
        const SizedBox(height: Space.s8),
        Wrap(
          spacing: Space.s8,
          runSpacing: Space.s8,
          children: <Widget>[
            VpsBadge(l.vpsBadgeReality(profile.port), accent: true),
            VpsBadge(_ipv6 ? l.vpsBadgeDualStack : l.vpsBadgeIpv4),
            if (canManage) VpsBadge(l.vpsBadgeCreds),
          ],
        ),
        if (showBanner) ...[
          const SizedBox(height: Space.s20),
          Container(
            padding: const EdgeInsets.all(Space.s16),
            decoration: BoxDecoration(
              color: c.surfaceHi,
              borderRadius: BorderRadius.circular(Radii.row),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.vpsNoCreds,
                  style: vpsBodyDim(context).copyWith(color: c.warn),
                ),
                const SizedBox(height: Space.s12),
                ObsButton(
                  label: l.vpsAddCreds,
                  kind: ObsButtonKind.secondary,
                  onPressed: _editSsh,
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: Space.s24),
        SectionLabel(l.vpsSniSection),
        const SizedBox(height: Space.s8),
        SniPicker(controller: _sni, errorText: _sniError),
        const SizedBox(height: Space.s12),
        ObsButton(
          label: l.vpsSniApply,
          kind: ObsButtonKind.secondary,
          onPressed: canManage ? _applySni : null,
        ),
        const SizedBox(height: Space.s8),
        Text(
          l.vpsReissueNote,
          style: vpsBodyDim(context).copyWith(fontSize: 12),
        ),
        const SizedBox(height: Space.s24),
        ObsGroup(
          children: <Widget>[
            ObsRow(
              title: 'IPv6',
              trailing: ObsSwitch(
                value: _ipv6,
                onChanged: canManage ? _setIpv6 : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.s8),
        Text(
          l.vpsReissueNote,
          style: vpsBodyDim(context).copyWith(fontSize: 12),
        ),
        const SizedBox(height: Space.s24),
        SectionLabel(l.vpsCoreSection),
        const SizedBox(height: Space.s8),
        ObsGroup(
          children: <Widget>[
            ObsRow(
              title: l.vpsCoreVersion(profile.serverVersion ?? '-'),
              subtitle: profile.needsUpdate ? l.vpsUpdateNeeded : l.vpsUpToDate,
            ),
          ],
        ),
        const SizedBox(height: Space.s12),
        if (profile.needsUpdate) ...[
          ObsButton(label: l.vpsUpdate, onPressed: canManage ? _update : null),
          const SizedBox(height: Space.s8),
        ],
        ObsButton(
          label: l.vpsCheckUpdates,
          kind: ObsButtonKind.secondary,
          onPressed: canManage ? _checkVersion : null,
        ),
        const SizedBox(height: Space.s24),
        SectionLabel(l.vpsSshSection),
        const SizedBox(height: Space.s8),
        ObsButton(
          label: l.vpsEditSsh,
          kind: ObsButtonKind.secondary,
          onPressed: _creds == null ? null : _editSsh,
        ),
        const SizedBox(height: Space.s24),
        ObsButton(
          label: l.vpsResetAction,
          kind: ObsButtonKind.destructive,
          onPressed: canManage ? _reset : null,
        ),
      ],
    );
  }
}
