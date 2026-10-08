import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/theme.dart';

/// Text input: surfaceHi fill, no border until focus, then a 1 px ember border.
/// Set [mono] for keys and hosts. Border styling comes from the theme.
class ObsTextField extends StatelessWidget {
  const ObsTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.hint,
    this.label,
    this.errorText,
    this.mono = false,
    this.obscure = false,
    this.autofocus = false,
    this.minLines,
    this.maxLines = 1,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hint;
  final String? label;
  final String? errorText;
  final bool mono;
  final bool obscure;
  final bool autofocus;
  final int? minLines;
  final int? maxLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.obs.colors;
    final style = mono
        ? obsidianMono(c, size: 13)
        : Theme.of(context).textTheme.bodyLarge!.copyWith(fontSize: 15);
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      enabled: enabled,
      obscureText: obscure,
      minLines: obscure ? 1 : minLines,
      maxLines: obscure ? 1 : maxLines,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: style,
      cursorColor: c.ember,
      cursorWidth: 1.5,
      autocorrect: !mono,
      enableSuggestions: !mono,
      decoration: InputDecoration(
        hintText: hint,
        labelText: label,
        errorText: errorText,
        suffixIcon: suffix,
        hintStyle: style.copyWith(color: c.textFaint),
        errorStyle: Theme.of(
          context,
        ).textTheme.bodySmall!.copyWith(color: c.danger),
      ),
    );
  }
}
