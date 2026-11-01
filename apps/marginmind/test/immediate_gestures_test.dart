import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/assistant/widgets/expansion_widgets.dart';
import 'package:marginmind/features/study_notes/note_view.dart';
import 'package:marginmind/features/workspace/reflow_session.dart';
import 'package:marginmind/features/workspace/widgets/reflow_reader.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';
import 'reflow_fixtures.dart';

Future<void> bare(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    locale: const Locale('en'),
    theme: MMTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Center(child: SizedBox(width: 400, child: child)),
    ),
  ),
);

void main() => immediateGestureTests();

void immediateGestureTests({bool native = false}) {
  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets('draft $kind double edit restores the first click toggle and can still save text', (tester) async {
      var draft = const ExpansionDraft(id: 'draft', parentRef: 'root', title: 'Original');
      var toggles = 0;
      await bare(
        tester,
        StatefulBuilder(
          builder: (context, rebuild) => MapGhostNode(
            draft: draft,
            focused: true,
            generating: false,
            onMore: null,
            onToggle: () {
              toggles++;
              rebuild(() => draft = draft.copyWith(kept: !draft.kept));
            },
            onEdit: (text) => rebuild(() => draft = draft.copyWith(title: text)),
          ),
        ),
      );
      await tester.tap(find.text('Original'), kind: kind);
      expect(draft.kept, isFalse);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.text('Original'), kind: kind);
      await tester.pumpAndSettle();
      expect(toggles, 2);
      expect(draft.kept, isTrue, reason: 'double-click editing must retain the original keep state');
      final field = find.byType(TextField);
      expect(field, findsOneWidget);
      await tester.enterText(field, 'Edited draft');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(draft.title, 'Edited draft');
      expect(draft.kept, isTrue);
      await tester.pump(const Duration(milliseconds: 400));
      expect(toggles, 2);
    }, semanticsEnabled: !native);
  }
  testWidgets('reference jump and explicit edit remain separate; edit saves without a second jump', (tester) async {
    var jumps = 0;
    String? saved;
    await bare(
      tester,
      NoteEditableText(
        text: 'Jump to chapter',
        style: const TextStyle(fontSize: 14),
        onReadTap: () => jumps++,
        onSave: (text) async => saved = text,
      ),
    );
    await tester.tap(find.text('Jump to chapter'), kind: PointerDeviceKind.mouse);
    expect(jumps, 1);
    await tester.pump();
    await tester.tap(find.byTooltip('Edit Note'), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(jumps, 1);
    await tester.enterText(find.byType(TextField), 'Updated reference');
    await tester.tapAt(const Offset(10, 10), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(saved, 'Updated reference');
    expect(jumps, 1);
  }, semanticsEnabled: !native);
  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets('reflow $kind double tap still selects one word and dragging extends selection', (tester) async {
      final repo = InMemoryStudySetContentRepository();
      final doc = await storeBook(repo);
      final container = await pumpApp(tester, content: repo);
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      final provider = workspaceProvider('demo-1');
      final workspace = container.read(provider.notifier);
      workspace.openDocument(doc.id);
      await tester.pumpAndSettle();
      final session = container.read(reflowSessionProvider(('demo-1', doc.id)));
      final chapter = session.book!.chapters.first;
      final start = chapter.canonicalText.indexOf('Source anchors');
      final anchor = chapter.anchor(start, start + 6, revision: doc.revision!);
      final surface = find.byKey(const ValueKey('reflow-surface'));
      final layout = (tester.widget<CustomPaint>(surface).painter as ReflowReaderPainter).layout;
      final box = layout.boxes(anchor).first.rect;
      final point = tester.getTopLeft(surface) + box.center;
      await tester.tapAt(point, kind: kind);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(point, kind: kind);
      await tester.pumpAndSettle();
      final pending = container.read(provider).pending as PendingSelection;
      expect(pending.selection.text.trim(), 'Source');
      workspace.dismissPending();
      await tester.pump(const Duration(milliseconds: 400));
      if (kind == PointerDeviceKind.mouse) {
        final drag = await tester.startGesture(point - const Offset(12, 0), kind: kind);
        await drag.moveBy(const Offset(20, 0));
        await tester.pump();
        await drag.moveBy(const Offset(100, 0));
        await drag.up();
        await tester.pumpAndSettle();
        expect((container.read(provider).pending as PendingSelection).selection.text.length, greaterThan(6));
      }
      await tester.pumpWidget(const SizedBox());
      await settleHud(tester);
    }, semanticsEnabled: !native);
  }
}
