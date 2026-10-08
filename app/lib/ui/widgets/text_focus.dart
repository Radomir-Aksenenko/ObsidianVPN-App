import 'package:flutter/widgets.dart';

/// True when the focused widget is a text field. Desktop shortcuts stay out of its way.
bool editingText() {
  final focus = FocusManager.instance.primaryFocus?.context;
  if (focus == null) return false;
  return focus.widget is EditableText ||
      focus.findAncestorWidgetOfExactType<EditableText>() != null;
}
