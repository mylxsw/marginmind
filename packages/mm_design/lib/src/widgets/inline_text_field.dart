import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/mm_theme.dart';

/// Borderless text field that edits text where it is shown (a mind map
/// node, a list row). Wraps like the text it replaces; the owner sizes it.
///
/// Enter submits and Esc cancels, except while an input method is
/// composing (pinyin not yet committed): then both keys belong to the
/// input method, to pick a candidate or drop the composition. Tab does not
/// move focus out of the field.
class MMInlineTextField extends StatelessWidget {
  const MMInlineTextField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.style,
    required this.onSubmitted,
    required this.onCancel,
    this.onTapOutside,
    this.semanticLabel,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final TextStyle style;
  final VoidCallback onSubmitted;
  final VoidCallback onCancel;

  /// A pointer went down outside the field while it had focus.
  final VoidCallback? onTapOutside;
  final String? semanticLabel;

  /// Whether the input method is composing text that is not committed yet.
  static bool isComposing(TextEditingValue value) => value.composing.isValid && !value.composing.isCollapsed;

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent || isComposing(controller.value)) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      onSubmitted();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      onCancel();
      return KeyEventResult.handled;
    }
    return key == LogicalKeyboardKey.tab ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: Semantics(
        label: semanticLabel,
        textField: true,
        child: Material(
          type: MaterialType.transparency,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            style: style,
            maxLines: null,
            cursorWidth: 1.5,
            cursorColor: c.accent,
            onTapOutside: onTapOutside == null ? null : (_) => onTapOutside!(),
            decoration: const InputDecoration.collapsed(hintText: null),
          ),
        ),
      ),
    );
  }
}
