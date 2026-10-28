import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/assistant/assistant_controller.dart';
import 'package:marginmind/features/assistant/assistant_entry.dart';
import 'package:marginmind/features/assistant/assistant_scope.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import 'assistant_support.dart';

const _quote = '这条先陡后平的曲线，被称为遗忘曲线。';

Future<AssistantApp> _open(WidgetTester tester, {ScriptClient? client, bool dark = false}) async {
  final app = await openAssistantApp(
    tester,
    client: client,
    size: const Size(1000, 760),
    prefs: {if (dark) 'settings.appearance': 'dark'},
  );
  await app.workspace.onSelectionCommitted(
    'c1',
    MMPdfSelection(
      page: 24,
      rects: const [PageRect(10, 100, 200, 88)],
      text: _quote,
      viewportRect: const Rect.fromLTWH(100, 200, 200, 20),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('selection-assistant')));
  await pumpFor(tester);
  return app;
}

ProviderContainer _scope(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byKey(const ValueKey('assistant-input'))));

void main() {
  testWidgets('one row of shortcuts; typing hides them while keeping the reference summary', (tester) async {
    await _open(tester);
    final summary = find.byKey(const ValueKey('assistant-context-summary'));
    final more = find.byKey(const ValueKey('quick-more'));
    expect(find.text('引用 2 项'), findsOneWidget);
    expect(find.byKey(const ValueKey('assistant-context-list')), findsNothing);
    expect(find.byKey(const ValueKey('quick-translate')), findsNothing);
    final explain = tester.getRect(find.byKey(const ValueKey('quick-explain')));
    final summarize = tester.getRect(find.byKey(const ValueKey('quick-summarize')));
    expect(explain.top, summarize.top);
    expect(explain.top, tester.getRect(more).top);
    expect(tester.getSize(summary).height, MMSizes.field);
    final before = tester.getTopLeft(summary).dy;

    await tester.enterText(find.byKey(const ValueKey('assistant-input')), '我的追问');
    await tester.pumpAndSettle();
    expect(more, findsNothing);
    expect(find.byKey(const ValueKey('quick-explain')), findsNothing);
    expect(find.text('引用 2 项'), findsOneWidget);
    expect(tester.getTopLeft(summary).dy, before); // Editing keeps the input and its references in place.
    await tester.enterText(find.byKey(const ValueKey('assistant-input')), '');
    await tester.pumpAndSettle();
    expect(more, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('more can be cancelled with Esc; choosing Translate sends the attached selection once', (tester) async {
    final client = ScriptClient([answer('翻译结果')]);
    await _open(tester, client: client);
    await tester.tap(find.byKey(const ValueKey('quick-more')));
    await tester.pumpAndSettle();
    for (final label in ['翻译', '查证', '出复习题', '整理进脑图']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(DefaultTextStyle.of(tester.element(find.text('翻译'))).style.decoration, isNot(TextDecoration.underline));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(client.calls, 0);
    expect(find.text('翻译'), findsNothing);
    expect(find.text('引用 2 项'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quick-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('翻译'));
    await pumpFor(tester, 20);
    expect(client.calls, 1);
    final question = conversationOf(tester).messages.first;
    expect(question.skill, 'translate');
    expect(question.contexts.first.displayText, _quote);
    expect(find.byKey(const ValueKey('assistant-context-list')), findsNothing);
  });

  testWidgets('expanded references restore automatic items and remove manual items without changing the draft', (
    tester,
  ) async {
    await _open(tester);
    final scope = _scope(tester);
    final auto = scope.read(assistantAutoContextsProvider('demo-1')).single;
    final manual = scope.read(assistantUiProvider('demo-1')).contexts.single;
    await tester.enterText(find.byKey(const ValueKey('assistant-input')), '保留这份草稿');
    await tester.tap(find.byKey(const ValueKey('assistant-context-summary')));
    await tester.pumpAndSettle();
    final toggle = find.byKey(ValueKey('context-remove-${auto.id}'));
    final checkbox = find.descendant(of: toggle, matching: find.byType(MMCheckbox));
    expect(tester.widget<MMCheckbox>(checkbox).value, isTrue);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('引用 1 项'), findsOneWidget);
    expect(tester.widget<MMCheckbox>(checkbox).value, isFalse);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('引用 2 项'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('context-remove-${manual.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('context-chip-${manual.id}')), findsNothing);
    expect(find.text('引用 1 项'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('assistant-input'))).controller!.text, '保留这份草稿');
    await tester.tap(find.byKey(const ValueKey('assistant-send')));
    await pumpFor(tester, 20);
    expect(conversationOf(tester).messages.first.contexts.single.id, auto.id);
    expect(find.byKey(const ValueKey('assistant-context-list')), findsNothing);
  });

  for (final dark in [false, true]) {
    testWidgets('many long references stay bounded in a narrow ${dark ? 'dark' : 'light'} panel', (tester) async {
      await _open(tester, dark: dark);
      final scope = _scope(tester);
      for (var i = 0; i < 8; i++) {
        scope
            .read(assistantUiProvider('demo-1').notifier)
            .addContext(
              ContextItem(id: 'doc-$i', kind: ContextKind.document, documentId: 'doc-$i', displayText: '很长的文档标题' * 20),
            );
      }
      await tester.pumpAndSettle();
      final summary = find.byKey(const ValueKey('assistant-context-summary'));
      expect(tester.getSize(summary).height, MMSizes.field);
      await tester.tap(summary);
      await tester.pumpAndSettle();
      final list = find.byKey(const ValueKey('assistant-context-list'));
      expect(tester.getSize(list).height, lessThanOrEqualTo(MMSizes.field * 4));
      await tester.drag(list, const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('assistant-input')).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
