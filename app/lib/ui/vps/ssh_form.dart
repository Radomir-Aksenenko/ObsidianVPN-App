import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Durations;

import '../../l10n/app_localizations.dart';
import '../../theme/theme.dart';
import '../../vps/vps_models.dart';
import '../widgets/widgets.dart';
import 'vps_common.dart';

/// Masking sites offered as chips. Any other domain can be typed in the field.
const List<String> kSniMasks = <String>[
  'www.microsoft.com',
  'www.apple.com',
  'www.google.com',
  'www.samsung.com',
  'vk.com',
  'www.amazon.com',
];

final RegExp _hostPattern = RegExp(r'^[A-Za-z0-9.\-:]+$');
final RegExp _domainPattern = RegExp(r'^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$');

/// True when [value] looks like a domain for the REALITY mask (no scheme, no path).
bool isValidSni(String value) => _domainPattern.hasMatch(value);

enum SshAuthMode { password, key }

/// Validation messages of [SshFormController]. Null means the field is fine.
class SshFormErrors {
  const SshFormErrors({this.host, this.port, this.user, this.password, this.key});

  final String? host;
  final String? port;
  final String? user;
  final String? password;
  final String? key;

  bool get any =>
      host != null || port != null || user != null || password != null || key != null;
}

/// State of [SshForm]: text fields, auth mode and validation. Call [dispose] when done.
class SshFormController {
  SshFormController({VpsCredentials? initial})
      : host = TextEditingController(text: initial?.host ?? ''),
        port = TextEditingController(text: '${initial?.port ?? 22}'),
        user = TextEditingController(text: initial?.user ?? 'root'),
        password = TextEditingController(text: initial?.password ?? ''),
        keyPem = TextEditingController(text: initial?.privateKeyPem ?? ''),
        passphrase = TextEditingController(text: initial?.passphrase ?? ''),
        auth = ValueNotifier<SshAuthMode>(
          initial?.usesKey == true ? SshAuthMode.key : SshAuthMode.password,
        );

  final TextEditingController host;
  final TextEditingController port;
  final TextEditingController user;
  final TextEditingController password;
  final TextEditingController keyPem;
  final TextEditingController passphrase;
  final ValueNotifier<SshAuthMode> auth;
  final ValueNotifier<bool> showPassword = ValueNotifier<bool>(false);
  final ValueNotifier<String?> pickedKeyName = ValueNotifier<String?>(null);
  final ValueNotifier<SshFormErrors> errors = ValueNotifier<SshFormErrors>(const SshFormErrors());

  void dispose() {
    for (final c in <TextEditingController>[host, port, user, password, keyPem, passphrase]) {
      c.dispose();
    }
    auth.dispose();
    showPassword.dispose();
    pickedKeyName.dispose();
    errors.dispose();
  }

  /// Validates the form and sets [errors]. Returns the credentials, or null when invalid.
  VpsCredentials? build(AppLocalizations l) {
    final h = host.text.trim();
    final p = int.tryParse(port.text.trim());
    final u = user.text.trim();
    final isKey = auth.value == SshAuthMode.key;
    final pem = keyPem.text.trim();

    String? eHost;
    if (h.isEmpty) {
      eHost = l.vpsHostRequired;
    } else if (!_hostPattern.hasMatch(h)) {
      eHost = l.vpsHostInvalid;
    }
    final ePort = p == null || p < 1 || p > 65535 ? l.vpsPortInvalid : null;
    final eUser = u.isEmpty || u.contains(RegExp(r'\s')) ? l.vpsUserRequired : null;
    String? ePass;
    String? eKey;
    if (isKey) {
      if (pem.isEmpty) {
        eKey = l.vpsKeyRequired;
      } else if (!pem.contains('PRIVATE KEY')) {
        eKey = l.vpsKeyInvalid;
      }
    } else if (password.text.isEmpty) {
      ePass = l.vpsPasswordRequired;
    }
    final result = SshFormErrors(
      host: eHost,
      port: ePort,
      user: eUser,
      password: ePass,
      key: eKey,
    );
    errors.value = result;
    if (result.any || p == null) return null;

    final passphraseText = passphrase.text;
    return VpsCredentials(
      host: h,
      port: p,
      user: u,
      password: isKey ? null : password.text,
      privateKeyPem: isKey ? pem : null,
      passphrase: isKey && passphraseText.isNotEmpty ? passphraseText : null,
    );
  }
}

/// Host, port, user, auth mode, password or key. Used by the deploy wizard and by SSH
/// access editing on the manage screen.
class SshForm extends StatelessWidget {
  const SshForm({super.key, required this.controller});

  final SshFormController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.obs.colors;
    final ctl = controller;
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        ctl.auth,
        ctl.showPassword,
        ctl.pickedKeyName,
        ctl.errors,
      ]),
      builder: (context, _) {
        final e = ctl.errors.value;
        final isKey = ctl.auth.value == SshAuthMode.key;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ObsTextField(
              controller: ctl.host,
              label: l.vpsHostLabel,
              hint: '203.0.113.10',
              mono: true,
              errorText: e.host,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: Space.s12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ObsTextField(
                    controller: ctl.user,
                    label: l.vpsUserLabel,
                    mono: true,
                    errorText: e.user,
                    textInputAction: TextInputAction.next,
                  ),
                ),
                const SizedBox(width: Space.s12),
                SizedBox(
                  width: 112,
                  child: ObsTextField(
                    controller: ctl.port,
                    label: l.vpsPortLabel,
                    mono: true,
                    errorText: e.port,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.s20),
            SectionLabel(l.vpsAuthLabel),
            const SizedBox(height: Space.s8),
            ObsSegmented<SshAuthMode>(
              options: <ObsSegment<SshAuthMode>>[
                ObsSegment(value: SshAuthMode.password, label: l.vpsAuthPassword),
                ObsSegment(value: SshAuthMode.key, label: l.vpsAuthKey),
              ],
              value: ctl.auth.value,
              onChanged: (value) => ctl.auth.value = value,
            ),
            const SizedBox(height: Space.s12),
            if (!isKey)
              ObsTextField(
                controller: ctl.password,
                label: l.vpsPasswordLabel,
                mono: true,
                obscure: !ctl.showPassword.value,
                errorText: e.password,
                suffix: IconButton(
                  tooltip: ctl.showPassword.value ? l.vpsPasswordHide : l.vpsPasswordShow,
                  icon: Icon(
                    ctl.showPassword.value
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    size: 22,
                    color: c.textDim,
                  ),
                  onPressed: () => ctl.showPassword.value = !ctl.showPassword.value,
                ),
              )
            else ...[
              ObsButton(
                label: ctl.pickedKeyName.value == null
                    ? l.vpsKeyFile
                    : l.vpsKeyFilePicked(ctl.pickedKeyName.value!),
                kind: ObsButtonKind.secondary,
                icon: Icons.key_rounded,
                onPressed: () => _pickKeyFile(context, ctl),
              ),
              const SizedBox(height: Space.s12),
              ObsTextField(
                controller: ctl.keyPem,
                label: l.vpsKeyPasteLabel,
                hint: '-----BEGIN OPENSSH PRIVATE KEY-----',
                mono: true,
                minLines: 3,
                maxLines: 6,
                errorText: e.key,
              ),
              const SizedBox(height: Space.s12),
              ObsTextField(
                controller: ctl.passphrase,
                label: l.vpsPassphraseLabel,
                mono: true,
                obscure: true,
              ),
            ],
          ],
        );
      },
    );
  }
}

Future<void> _pickKeyFile(BuildContext context, SshFormController ctl) async {
  final l = AppLocalizations.of(context);
  try {
    final file = await FilePicker.pickFile(dialogTitle: l.vpsKeyFile);
    if (file == null) return;
    final text = utf8.decode(await file.readAsBytes());
    ctl.keyPem.text = text.trim();
    ctl.pickedKeyName.value = file.name;
  } catch (_) {
    if (context.mounted) showObsToast(context, l.vpsKeyInvalid, kind: ObsToastKind.error);
  }
}

/// Masking site (REALITY SNI): preset chips and a free field.
class SniPicker extends StatelessWidget {
  const SniPicker({super.key, required this.controller, this.errorText});

  final TextEditingController controller;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final current = value.text.trim();
            return Wrap(
              spacing: Space.s8,
              runSpacing: Space.s8,
              children: <Widget>[
                for (final mask in kSniMasks)
                  _MaskChip(
                    label: mask,
                    selected: current == mask,
                    onTap: () => controller.text = mask,
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: Space.s12),
        ObsTextField(
          controller: controller,
          label: l.vpsSniLabel,
          hint: l.vpsSniHint,
          mono: true,
          errorText: errorText,
        ),
        const SizedBox(height: Space.s8),
        Text(l.vpsSniCaption, style: vpsBodyDim(context).copyWith(fontSize: 12)),
      ],
    );
  }
}

class _MaskChip extends StatelessWidget {
  const _MaskChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.obs.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.chip),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.s12, vertical: Space.s8),
        decoration: BoxDecoration(
          color: selected ? c.emberSoft : c.surfaceHi,
          borderRadius: BorderRadius.circular(Radii.chip),
          border: Border.all(color: selected ? c.ember : Colors.transparent),
        ),
        child: Text(
          label,
          style: context.obs.mono.copyWith(fontSize: 12, color: selected ? c.ember : c.text),
        ),
      ),
    );
  }
}
