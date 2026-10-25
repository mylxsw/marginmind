import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

/// A card's text open for editing. [ended] is set as soon as the edit is
/// confirmed or cancelled; the field stays on screen until the caller
/// clears the editing card, so the saved text replaces it without a flash
/// of the old one.
class CardField {
  CardField(this.id, this.controller, this.focus);

  final String id;
  final TextEditingController controller;
  final FocusNode focus;
  bool ended = false;

  /// The card has been shown; until then the content may lag behind the
  /// write that created it.
  bool seen = false;

  void dispose() {
    controller.dispose();
    focus.dispose();
  }
}

/// Printable text without ⌘ / Ctrl / ⌥; excludes the private-use range
/// macOS reports for function and arrow keys.
bool isTypingKey(KeyEvent event) {
  final character = event.character;
  if (character == null || character.isEmpty) return false;
  final keyboard = HardwareKeyboard.instance;
  if (keyboard.isMetaPressed || keyboard.isControlPressed || keyboard.isAltPressed) return false;
  return character.runes.every((r) => r >= 0x20 && r != 0x7f && (r < 0xf700 || r > 0xf8ff));
}

/// Opens and closes the in-place field of the map and the outline: one
/// field at a time, following the caller's editing card id.
mixin CardFieldHost<T extends StatefulWidget> on State<T> {
  CardField? field;

  /// Text typed on a selected card; it replaces the text in the field the
  /// caller opens next.
  String? typed;

  String? get editingCardId;
  StudySetContent get fieldContent;

  /// Takes keyboard focus back after Enter / Esc.
  FocusNode get hostFocus;
  ValueChanged<String>? get onFieldDone;
  VoidCallback? get onFieldCancel;

  /// The field for [id] has just been focused.
  void fieldOpened(String id) {}

  /// Opens or closes the text field to match [editingCardId].
  void syncField() {
    final id = editingCardId;
    if (id == field?.id) return;
    // Each field gets its own focus node: one that is already focused would
    // not open a text input connection for the next field.
    final old = field;
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    field = null;
    final replacement = typed;
    typed = null;
    if (id == null) return;
    final text = replacement ?? fieldContent.card(id)?.title ?? '';
    final controller = TextEditingController(text: text)
      ..selection = replacement == null
          ? TextSelection(baseOffset: 0, extentOffset: text.length)
          : TextSelection.collapsed(offset: text.length);
    controller.addListener(() {
      if (mounted) setState(() {});
    });
    final next = CardField(id, controller, FocusNode(debugLabel: 'CardField'));
    next.focus.addListener(() => _onFocus(next));
    field = next;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || field != next) return;
      next.focus.requestFocus();
      fieldOpened(id);
    });
  }

  /// Focus left the field (a click elsewhere, another pane): confirm. Not
  /// when the app goes to the background; focus comes back on return.
  void _onFocus(CardField f) {
    if (f.focus.hasFocus) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    endField(f, commit: true, refocus: false);
  }

  void endField(CardField? f, {required bool commit, required bool refocus}) {
    if (f == null || f != field || f.ended) return;
    f.ended = true;
    if (refocus) hostFocus.requestFocus();
    if (commit) {
      onFieldDone?.call(f.controller.text);
    } else {
      onFieldCancel?.call();
    }
  }

  /// Marks the field as shown, or cancels it when its card went away
  /// (deleted, folded away) after it had been shown.
  void trackField({required bool shown}) {
    final f = field;
    if (f == null) return;
    if (shown) {
      f.seen = true;
    } else if (f.seen && !f.ended) {
      WidgetsBinding.instance.addPostFrameCallback((_) => endField(f, commit: false, refocus: false));
    }
  }

  /// Closing the view confirms the edit, like clicking elsewhere.
  void disposeField() {
    final f = field;
    if (f != null && !f.ended) {
      final done = onFieldDone;
      final text = f.controller.text;
      if (done != null) Future.microtask(() => done(text));
    }
    f?.dispose();
  }

  /// The text field for [f], styled like the text it replaces. Notes take
  /// ⇧Enter as a line break.
  Widget fieldEditor(CardField f, {required TextStyle style, required CardKind kind, String? label, int? maxLines}) =>
      MMInlineTextField(
        controller: f.controller,
        focusNode: f.focus,
        style: style,
        multiline: kind == CardKind.note,
        maxLines: maxLines,
        semanticLabel: label,
        onSubmitted: () => endField(f, commit: true, refocus: true),
        onCancel: () => endField(f, commit: false, refocus: true),
        onTapOutside: () => endField(f, commit: true, refocus: false),
      );
}
