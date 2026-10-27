import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../app/app_commands.dart';
import 'l10n.dart';

/// Weight of bold note text.
const noteBoldWeight = FontWeight.w600;

/// A note as shown (P2-C07): Markdown is parsed by the shared [NoteDocument]
/// parser, plain text is shown as is. The map measures the same span it
/// shows, so both lay out alike.
TextSpan noteSpan(String text, TextFormat format, TextStyle style) {
  if (format == TextFormat.plain) return TextSpan(text: text, style: style);
  final blocks = NoteDocument.parse(text, format).blocks;
  return TextSpan(
    style: style,
    children: [
      for (var i = 0; i < blocks.length; i++) ...[
        if (i > 0) const TextSpan(text: '\n'),
        if (blocks[i].prefix.isNotEmpty) TextSpan(text: blocks[i].prefix),
        for (final s in blocks[i].spans)
          TextSpan(
            text: s.text,
            style: TextStyle(fontWeight: s.bold ? noteBoldWeight : null, fontStyle: s.italic ? FontStyle.italic : null),
          ),
      ],
    ],
  );
}

/// A note's source while it is edited: Markdown text in its style with the
/// markup in [markerColor]; plain text as is. The input method's composing
/// range is underlined, as in a plain field.
TextSpan noteSourceSpan(String text, TextFormat format, TextStyle style, {Color? markerColor, TextRange? composing}) {
  final pieces = <(int, int, TextStyle?)>[];
  if (format == TextFormat.plain) {
    pieces.add((0, text.length, null));
  } else {
    var at = 0;
    for (final run in noteSourceRuns(text)) {
      if (run.start > at) pieces.add((at, run.start, null));
      pieces.add((
        run.start,
        run.end,
        run.marker
            ? TextStyle(color: markerColor)
            : TextStyle(fontWeight: run.bold ? noteBoldWeight : null, fontStyle: run.italic ? FontStyle.italic : null),
      ));
      at = run.end;
    }
    if (at < text.length) pieces.add((at, text.length, null));
  }
  final underline = composing != null && composing.isValid && !composing.isCollapsed ? composing : null;
  const composingStyle = TextStyle(decoration: TextDecoration.underline);
  final children = <TextSpan>[];
  for (final (start, end, piece) in pieces) {
    // Split each piece at the composing range's ends.
    final cuts = {
      start,
      end,
      if (underline != null) ...[underline.start.clamp(start, end), underline.end.clamp(start, end)],
    }.toList()..sort();
    for (var i = 0; i + 1 < cuts.length; i++) {
      final (a, b) = (cuts[i], cuts[i + 1]);
      final composed = underline != null && a >= underline.start && b <= underline.end;
      children.add(
        TextSpan(
          text: text.substring(a, b),
          style: composed ? (piece ?? const TextStyle()).merge(composingStyle) : piece,
        ),
      );
    }
  }
  return TextSpan(style: style, children: children);
}

/// A note shown with its formatting.
class NoteText extends StatelessWidget {
  const NoteText(this.text, this.format, {super.key, required this.style, this.selectable = false});

  final String text;
  final TextFormat format;
  final TextStyle style;

  /// Review lets the reader select and copy the text.
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final span = noteSpan(text, format, style);
    return selectable ? SelectableText.rich(span) : Text.rich(span);
  }
}

/// A note open for editing. Its text stays the stored source: Markdown
/// shows its markup, dimmed. The first formatting command turns a plain note
/// into Markdown (escaping what it already says), as does typing `- ` or
/// `1. ` at the start of a line; a line break in a list item continues the
/// list. Nothing changes while an input method is composing.
class NoteFormatController extends TextEditingController {
  NoteFormatController({super.text, this.format = TextFormat.plain, this.markerColor});

  TextFormat format;

  /// Color of the markup; set from the theme by the field.
  Color? markerColor;

  bool get _composing => value.composing.isValid && !value.composing.isCollapsed;

  NoteEditValue get _edit {
    final s = selection.isValid ? selection : TextSelection.collapsed(offset: text.length);
    return NoteEditValue(text, s.start, s.end, format);
  }

  void _set(NoteEditValue v) {
    format = v.format;
    super.value = TextEditingValue(
      text: v.text,
      selection: v.start == v.end
          ? TextSelection.collapsed(offset: v.start)
          : TextSelection(baseOffset: v.start, extentOffset: v.end),
    );
  }

  /// Applies a toolbar or keyboard command.
  void apply(NoteFormatCommand command) {
    if (_composing) return;
    _set(switch (command) {
      NoteFormatCommand.bold => NoteFormatting.toggleBold(_edit),
      NoteFormatCommand.italic => NoteFormatting.toggleItalic(_edit),
      NoteFormatCommand.bullets => NoteFormatting.toggleBullets(_edit),
      NoteFormatCommand.numbers => NoteFormatting.toggleNumbers(_edit),
    });
  }

  @override
  set value(TextEditingValue next) {
    final composing = next.composing.isValid && !next.composing.isCollapsed;
    final before = _edit;
    if (!composing && next.selection.isValid && next.selection.isCollapsed) {
      final after = NoteEditValue.collapsed(next.text, next.selection.baseOffset, format);
      final converted = NoteFormatting.autoList(before, after) ?? NoteFormatting.continueList(before, after);
      if (converted != null) {
        _set(converted);
        return;
      }
    }
    super.value = next;
  }

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) =>
      noteSourceSpan(
        text,
        format,
        style ?? const TextStyle(),
        markerColor: markerColor,
        composing: withComposing ? value.composing : null,
      );
}

/// Gives a note field the formatting keys (⌘B / ⌘I) and lets menus and the
/// toolbar reach its controller through [NoteFormatIntent].
class NoteFormatScope extends StatelessWidget {
  const NoteFormatScope({super.key, required this.controller, required this.child});

  final NoteFormatController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    controller.markerColor = context.mmColors.secondaryLabel;
    return Actions(
      actions: {NoteFormatIntent: CallbackAction<NoteFormatIntent>(onInvoke: (i) => controller.apply(i.command))},
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, event) {
          if (event is KeyUpEvent) return KeyEventResult.ignored;
          for (final entry in noteFormatShortcuts.entries) {
            if (entry.key.accepts(event, HardwareKeyboard.instance)) {
              controller.apply(entry.value);
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: child,
      ),
    );
  }
}

/// Bold, italic and the two lists, above a note being edited. Pressing a
/// button leaves the keyboard in the note.
class NoteFormatBar extends StatelessWidget {
  const NoteFormatBar({super.key, required this.controller});

  final NoteFormatController controller;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    Widget button(IconData icon, String label, NoteFormatCommand command, [SingleActivator? shortcut]) => MMIconButton(
      icon: icon,
      tooltip: shortcut == null ? label : AppShortcuts.tip(label, shortcut),
      size: 26,
      iconSize: 13,
      color: c.label,
      onPressed: () => controller.apply(command),
    );
    final shortcuts = {for (final e in noteFormatShortcuts.entries) e.value: e.key};
    // Part of the field's tap region: a click here does not end the edit.
    return TextFieldTapRegion(
      child: MMGlass(
        key: const ValueKey('note-format-bar'),
        borderRadius: BorderRadius.circular(MMRadii.card),
        padding: const EdgeInsets.all(MMSpacing.xxs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            button(MMIcons.bold, l.formatBold, NoteFormatCommand.bold, shortcuts[NoteFormatCommand.bold]),
            button(MMIcons.italic, l.formatItalic, NoteFormatCommand.italic, shortcuts[NoteFormatCommand.italic]),
            button(MMIcons.bulletList, l.formatBulletList, NoteFormatCommand.bullets),
            button(MMIcons.numberList, l.formatNumberList, NoteFormatCommand.numbers),
          ],
        ),
      ),
    );
  }
}
