import 'package:flutter/material.dart' hide Durations;

import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../../vps/deployer.dart';
import '../../vps/vps_models.dart';
import '../widgets/widgets.dart';
import 'deploy_progress.dart';
import 'ssh_form.dart';
import 'vps_common.dart';

enum _WizardStep { form, progress, done }

/// Deploys the Obsidian core on a clean VPS: SSH form, live progress, then the owner key
/// and the admin token, which is shown once.
class DeployWizardScreen extends StatefulWidget {
  const DeployWizardScreen({super.key, this.deployer});

  /// Replaces the real deployer in tests.
  final VpsDeployer? deployer;

  @override
  State<DeployWizardScreen> createState() => _DeployWizardScreenState();
}

class _DeployWizardScreenState extends State<DeployWizardScreen> {
  late final VpsDeployer _deployer = widget.deployer ?? VpsDeployer();
  final SshFormController _ssh = SshFormController();
  final TextEditingController _sni = TextEditingController(text: kDefaultSni);

  _WizardStep _step = _WizardStep.form;
  VpsCredentials? _creds;
  String _sniValue = kDefaultSni;
  String? _sniError;
  DeployResult? _result;

  @override
  void dispose() {
    _ssh.dispose();
    _sni.dispose();
    super.dispose();
  }

  void _submit() {
    final l = AppLocalizations.of(context);
    final creds = _ssh.build(l);
    final sni = _sni.text.trim().toLowerCase();
    final sniOk = isValidSni(sni);
    setState(() => _sniError = sniOk ? null : l.vpsSniInvalid);
    if (creds == null || !sniOk) return;
    setState(() {
      _creds = creds;
      _sniValue = sni;
      _step = _WizardStep.progress;
    });
  }

  Stream<DeployEvent> _start(String? trustedHostKey) {
    final creds = _creds!;
    final pinned = trustedHostKey == null
        ? creds
        : creds.copyWith(hostKeyFingerprint: trustedHostKey);
    return _deployer.deploy(DeployRequest(creds: pinned, sni: _sniValue));
  }

  Future<void> _onDeployed(DeployOutcome<DeployResult> outcome) async {
    final state = AppState.of(context);
    final result = outcome.value;
    final profile = await state.saveVpsProfile(result, _creds!, hostKey: outcome.hostKey);
    await state.selectProfile(profile.id);
    if (!mounted) return;
    setState(() {
      _result = result;
      _step = _WizardStep.done;
    });
  }

  /// Leaving during the install asks first, because the server would be left half-installed.
  Future<void> _confirmLeave() async {
    final l = AppLocalizations.of(context);
    final ok = await confirmSheet(
      context,
      title: l.vpsCancelDeployTitle,
      text: l.vpsCancelDeployText,
      action: l.vpsCancelDeployAction,
      cancelLabel: l.vpsStay,
      destructive: true,
    );
    if (ok && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return PopScope(
      canPop: _step != _WizardStep.progress,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: switch (_step) {
        _WizardStep.form => _formPage(l),
        _WizardStep.progress => VpsPage(
            title: l.vpsDeployTitle,
            children: [
              DeployProgressView<DeployResult>(
                start: _start,
                cancellable: true,
                onCancel: () => Navigator.of(context).pop(),
                onDone: _onDeployed,
              ),
            ],
          ),
        _WizardStep.done => _donePage(l),
      },
    );
  }

  Widget _formPage(AppLocalizations l) {
    return VpsPage(
      title: l.vpsDeployTitle,
      children: [
        Text(l.vpsDeployHint, style: vpsBodyDim(context)),
        const SizedBox(height: Space.s24),
        SshForm(controller: _ssh),
        const SizedBox(height: Space.s24),
        SniPicker(controller: _sni, errorText: _sniError),
        const SizedBox(height: Space.s32),
        ObsButton(label: l.vpsDeployStart, onPressed: _submit),
      ],
    );
  }

  Widget _donePage(AppLocalizations l) {
    final c = context.obs.colors;
    final token = _result?.adminToken ?? '';
    return VpsPage(
      title: l.vpsSuccessTitle,
      children: [
        Text(l.vpsSuccessText, style: vpsBodyDim(context)),
        const SizedBox(height: Space.s24),
        SectionLabel(l.vpsAdminToken),
        const SizedBox(height: Space.s8),
        Container(
          padding: const EdgeInsets.all(Space.s16),
          decoration: BoxDecoration(
            color: c.surfaceHi,
            borderRadius: BorderRadius.circular(Radii.row),
          ),
          child: SelectableText(
            token,
            style: context.obs.mono.copyWith(fontSize: 13, color: c.text),
          ),
        ),
        const SizedBox(height: Space.s8),
        Text(
          l.vpsAdminTokenWarning,
          style: vpsBodyDim(context).copyWith(color: c.warn, fontSize: 13),
        ),
        const SizedBox(height: Space.s12),
        ObsButton(
          label: l.vpsCopy,
          kind: ObsButtonKind.secondary,
          onPressed: () => copyText(context, token, l.vpsCopied),
        ),
        const SizedBox(height: Space.s24),
        ObsButton(label: l.vpsDone, onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }
}
