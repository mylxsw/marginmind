import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app_commands.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/shared/note_text.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import 'card_edit_test.dart' show key;
import 'helpers.dart';

const _md = TextFormat.markdown;
const _plain = TextFormat.plain;

List<TextSpan> _leaves(InlineSpan span) {
  final out = <TextSpan>[];
  span.visitChildren((s) {
    if (s is TextSpan && s.text != null) out.add(s);
    return true;
  });
  return out;
}

EditableText _field(WidgetTester tester) => tester.widget<EditableText>(
  find.descendant(of: find.byType(NoteFormatScope), matching: find.byType(EditableText)).first,
);

void main() {
  group('spans', () {
    const style = TextStyle(fontSize: 13);

    test('a plain note is one span; Markdown is drawn with styles and list marks', () {
      expect(noteSpan('**x**', _plain, style).text, '**x**');
      final leaves = _leaves(noteSpan('**b** *i*\n- item\n2. two', _md, style));
      expect(leaves.map((s) => s.text).join(), 'b i\n• item\n2. two');
      expect(leaves.firstWhere((s) => s.text == 'b').style!.fontWeight, noteBoldWeight);
      expect(leaves.firstWhere((s) => s.text == 'i').style!.fontStyle, FontStyle.italic);
    });

    test('the source keeps every character, dims the markup and underlines composing text', () {
      const marker = Color(0xFF888888);
      final span = noteSourceSpan(
        '**ab** c',
        _md,
        style,
        markerColor: marker,
        composing: const TextRange(start: 3, end: 7),
      );
      final leaves = _leaves(span);
      expect(leaves.map((s) => s.text).join(), '**ab** c');
      expect(leaves.first.style!.color, marker);
      final composed = leaves.where((s) => s.style?.decoration == TextDecoration.underline).map((s) => s.text).join();
      expect(composed, 'b** ');
      // Plain text is not styled; a collapsed composing range underlines nothing.
      final plain = _leaves(noteSourceSpan('*a*', _plain, style, composing: const TextRange.collapsed(1)));
      expect(plain.single.text, '*a*');
      expect(plain.single.style, isNull);
      expect(_leaves(noteSourceSpan('a\nb', _md, style)).map((s) => s.text).join(), 'a\nb');
    });
  });

  group('controller', () {
    test('commands format the selection and turn a plain note into Markdown', () {
      final c = NoteFormatController(text: 'a*b')..selection = const TextSelection(baseOffset: 0, extentOffset: 3);
      c.apply(NoteFormatCommand.bold);
      expect(c.format, _md);
      expect(c.text, r'**a\*b**');
      c.apply(NoteFormatCommand.italic);
      expect(c.text, r'***a\*b***');
      c.selection = const TextSelection.collapsed(offset: 0);
      c.apply(NoteFormatCommand.bullets);
      expect(c.text, startsWith('- '));
      c.apply(NoteFormatCommand.numbers);
      expect(c.text, startsWith('1. '));
      c.dispose();
    });

    test('typing "- " starts a list, a line break continues it; not while composing', () {
      final c = NoteFormatController(text: '*')..selection = const TextSelection.collapsed(offset: 1);
      c.value = const TextEditingValue(text: '*\n', selection: TextSelection.collapsed(offset: 2));
      c.value = const TextEditingValue(text: '*\n-', selection: TextSelection.collapsed(offset: 3));
      c.value = const TextEditingValue(text: '*\n- ', selection: TextSelection.collapsed(offset: 4));
      expect(c.format, _md);
      expect(c.text, '\\*\n- ');
      c.value = TextEditingValue(
        text: '${c.text}a',
        selection: TextSelection.collapsed(offset: c.text.length + 1),
      );
      c.value = TextEditingValue(
        text: '${c.text}\n',
        selection: TextSelection.collapsed(offset: c.text.length + 1),
      );
      expect(c.text, '\\*\n- a\n- ');
      // An input method composing a line break-like change is left alone.
      const composing = TextEditingValue(
        text: '\\*\n- a\n- 你',
        selection: TextSelection.collapsed(offset: 10),
        composing: TextRange(start: 9, end: 10),
      );
      c.value = composing;
      expect(c.value, composing);
      c.apply(NoteFormatCommand.bold);
      expect(c.value, composing);
      c.dispose();
    });
  });

  group('workspace', () {
    Future<WorkspaceController> open(WidgetTester tester) async {
      final container = await pumpApp(tester);
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      return container.read(workspaceProvider('demo-1').notifier);
    }

    testWidgets('editing a note on the map shows the format bar; the format is saved with the text', (tester) async {
      final controller = await open(tester);
      final note = await controller.addNote('plain *star*');
      await tester.pumpAndSettle();
      controller.beginEditing(note.id);
      await tester.pumpAndSettle();
      final bar = find.byKey(const ValueKey('note-format-bar'));
      expect(bar, findsOneWidget);

      // The bar keeps the field open: bold the whole text.
      await tester.tap(find.descendant(of: bar, matching: find.byIcon(MMIcons.bold)));
      await tester.pumpAndSettle();
      expect(_field(tester).controller.text, r'**plain \*star\***');
      // ⌘I in the field: italic.
      await key(tester, LogicalKeyboardKey.keyI, primary: true);
      expect(_field(tester).controller.text, r'***plain \*star\****');
      await key(tester, LogicalKeyboardKey.keyI, primary: true);
      await key(tester, LogicalKeyboardKey.keyB, primary: true);
      expect(_field(tester).controller.text, r'plain \*star\*');
      await tester.tap(find.descendant(of: bar, matching: find.byIcon(MMIcons.bulletList)));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(bar, findsNothing);
      final saved = controller.content.card(note.id)!;
      expect(saved.textFormat, _md);
      expect(saved.title, r'- plain \*star\*');
      // The map shows it formatted: the stars are text, the dash a bullet.
      expect(find.text('• plain *star*', findRichText: true), findsOneWidget);

      // One undo step restores the plain note.
      await controller.undo();
      expect(controller.content.card(note.id)!.textFormat, _plain);
      expect(controller.content.card(note.id)!.title, 'plain *star*');
      await settleHud(tester);
    });

    testWidgets('an old plain note stays plain when edited without formatting', (tester) async {
      final controller = await open(tester);
      final note = await controller.addNote('**literal**');
      await tester.pumpAndSettle();
      expect(find.text('**literal**', findRichText: true), findsOneWidget);
      controller.beginEditing(note.id);
      await tester.pumpAndSettle();
      _field(tester).controller.text = '**literal** more';
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(controller.content.card(note.id)!.textFormat, _plain);
      expect(find.text('**literal** more', findRichText: true), findsOneWidget);
      await settleHud(tester);
    });

    testWidgets('the details panel formats a note with its own bar', (tester) async {
      final controller = await open(tester);
      final note = await controller.addNote('detail');
      await tester.pumpAndSettle();
      controller.showDetails(note.id);
      await tester.pumpAndSettle();
      final field = find.descendant(of: find.byType(NoteFormatScope), matching: find.byType(EditableText));
      expect(field, findsOneWidget);
      await tester.tap(field);
      await tester.pumpAndSettle();
      final bar = find.byKey(const ValueKey('note-format-bar'));
      expect(bar, findsOneWidget);
      tester.widget<EditableText>(field).controller.selection = const TextSelection(baseOffset: 0, extentOffset: 6);
      await tester.tap(find.descendant(of: bar, matching: find.byIcon(MMIcons.italic)));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: bar, matching: find.byIcon(MMIcons.numberList)));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final saved = controller.content.card(note.id)!;
      expect(saved.title, '1. *detail*');
      expect(saved.textFormat, _md);
      // Esc after a format change puts the stored text and format back.
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: bar, matching: find.byIcon(MMIcons.bulletList)));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(field).controller.text, '1. *detail*');
      expect(controller.content.card(note.id)!.title, '1. *detail*');
      await settleHud(tester);
    });

    testWidgets('menu bar format commands work only in a note field', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final controller = await open(tester);
        final note = await controller.addNote('menu');
        await tester.pumpAndSettle();
        PlatformMenuItem item(String label) => tester
            .widget<PlatformMenuBar>(find.byType(PlatformMenuBar))
            .menus
            .whereType<PlatformMenu>()
            .expand((m) => m.menus)
            .whereType<PlatformMenuItem>()
            .firstWhere((i) => i.label == label);
        expect(item('Bold').onSelected, isNull);
        controller.beginEditing(note.id);
        await tester.pumpAndSettle();
        expect(item('Bold').onSelected, isNotNull);
        item('Numbered List').onSelected!();
        await tester.pumpAndSettle();
        expect(_field(tester).controller.text, '1. menu');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(controller.content.card(note.id)!.title, '1. menu');
        await settleHud(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  testWidgets('review shows a formatted note formatted and a plain one as written', (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: MMTheme.light(),
        home: Scaffold(
          body: Column(
            children: [
              NoteText('**Key** idea', _md, style: const TextStyle(), selectable: true),
              NoteText('**raw**', _plain, style: const TextStyle()),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Key idea', findRichText: true), findsOneWidget);
    expect(find.text('**raw**', findRichText: true), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
  });
}
