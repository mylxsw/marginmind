// Manual timing probe: flutter test --no-pub test/probes/response_latency_probe.dart --reporter expanded
// These measurements advance Flutter's controlled clock, not wall-clock time.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/assistant/widgets/expansion_widgets.dart';
import 'package:marginmind/features/study_notes/note_view.dart';
import 'package:marginmind/features/workspace/reflow_session.dart';
import 'package:marginmind/features/workspace/reader_margin.dart';

import 'package:marginmind/features/workspace/widgets/reflow_reader.dart';
import 'package:marginmind/features/workspace/widgets/map_source_chip.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_book/mm_book.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import '../../../../packages/mm_pdf/test/support/pdf_backend.dart';
import '../reader_crop_test.dart' show drain;
import '../helpers.dart';
import '../reflow_fixtures.dart';
import '../workspace_test.dart' show openFirstSet;

Future<int> measure(WidgetTester tester, String name, Future<void> Function() tap, bool Function() happened) async {
  await tap();
  await tester.pump();
  var elapsed = 0;
  while (!happened() && elapsed < 400) {
    elapsed++;
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(happened(), isTrue, reason: '$name must activate within the observation window');
  debugPrint('LATENCY $name = ${elapsed}ms');
  await tester.pump(const Duration(milliseconds: 400));
  return elapsed;
}

Future<void> bare(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: MMTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  for (final source in [false, true]) {
    testWidgets('measure AI draft ${source ? 'child source button' : 'keep toggle'}', (tester) async {
      var calls = 0;
      await bare(
        tester,
        MapGhostNode(
          draft: const ExpansionDraft(id: 'd', parentRef: 'root', title: 'Draft title', page: 1),
          focused: false,
          generating: false,
          onToggle: () => calls++,
          onEdit: (_) {},
          onMore: null,
          sourceChip: MapSourceChip(page: 1, onTap: () => calls++),
        ),
      );
      await tester.pumpAndSettle();
      await measure(
        tester,
        source ? 'draft-source-button' : 'draft-keep-toggle',
        () => tester.tap(source ? find.byType(MapSourceChip) : find.text('Draft title'), kind: PointerDeviceKind.mouse),
        () => calls != 0,
      );
      expect(calls, 1);
    });
  }
  testWidgets('measure study-note cross-reference', (tester) async {
    var calls = 0;
    await bare(
      tester,
      NoteEditableText(
        text: 'Read reference',
        style: const TextStyle(fontSize: 14),
        onSave: (_) async {},
        onReadTap: () => calls++,
      ),
    );
    await tester.pumpAndSettle();
    await measure(
      tester,
      'study-note-xref',
      () => tester.tap(find.text('Read reference'), kind: PointerDeviceKind.mouse),
      () => calls != 0,
    );
    expect(calls, 1);
  });
  for (final link in [false, true]) {
    for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
      testWidgets('measure reflow ${link ? 'footnote' : 'saved mark'} $kind', (tester) async {
        final repository = InMemoryStudySetContentRepository();
        final chapter = const EpubParser().parseHtml(
          'main',
          '<p>Marked<a href="#target">1</a> text</p><p>${'body ' * 100}</p>'
              '<h2 id="target">Footnote</h2><p>${'note ' * 100}</p>',
        );
        final doc = await storeBook(repository, book: Book('Probe', [chapter], {}, []));
        final container = await pumpApp(tester, content: repository);
        container.read(navigationProvider.notifier).openStudySet('demo-1');
        await tester.pumpAndSettle();
        final provider = workspaceProvider('demo-1');
        final workspace = container.read(provider.notifier);
        workspace.openDocument(doc.id);
        await tester.pumpAndSettle();
        final session = container.read(reflowSessionProvider(('demo-1', doc.id)));
        final anchor = session.book!.chapters.first.anchor(0, 6, revision: doc.revision!);
        if (!link) {
          await workspace.highlightSource(doc.id, SourceSelection.text([anchor]), MMAnnotationColor.yellow);
          await tester.pumpAndSettle();
        }
        final surface = find.byKey(const ValueKey('reflow-surface'));
        final layout = (tester.widget<CustomPaint>(surface).painter as ReflowReaderPainter).layout;
        final rect = layout.boxes(link ? layout.links.single.anchor : anchor).first.rect;
        final point = tester.getTopLeft(surface) + rect.center;
        await measure(
          tester,
          'reflow-${link ? 'footnote' : 'saved-mark'}-${kind.name}',
          () => tester.tapAt(point, kind: kind),
          () => link
              ? session.position!.offset == chapter.elementOffsets['target']
              : container.read(provider).pending != null,
        );
        await tester.pumpWidget(const SizedBox());
        await settleHud(tester);
      });
    }
  }
  testWidgets('measure attached-note text selection', (tester) async {
    final container = await openFirstSet(tester);
    final provider = workspaceProvider('demo-1');
    final workspace = container.read(provider.notifier);
    workspace.selectCard('c3');
    final note = await workspace.addNote('Attached note timing');
    workspace.selectCard('c3');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('map-notes-toggle-c3')));
    await tester.pumpAndSettle();
    workspace.selectCard(null);
    await tester.pumpAndSettle();
    await measure(
      tester,
      'attached-note-text-owner-selection',
      () => tester.tap(find.text(note.title, findRichText: true), kind: PointerDeviceKind.mouse),
      () => container.read(provider).selectedCardId != null,
    );
    await settleHud(tester);
  });
  testWidgets('measure margin-note More menu appearance', (tester) async {
    installTestPdfBackend();
    final container = await pumpApp(tester, renderPdf: true, size: const Size(1800, 1000));
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await drain(tester);
    final workspace = container.read(workspaceProvider('demo-1').notifier);
    workspace.setLayout(MMSplitMode.primary);
    await drain(tester);
    final session = container.read(readerMarginProvider('demo-1').notifier);
    await session.start(
      'c1',
      pages: const [
        AnnotationPage(page: 1, rects: [PageRect(40, 700, 200, 680)]),
      ],
    );
    session.text('Saved margin note');
    await session.finish();
    await drain(tester);
    final card = find.byKey(ValueKey('margin-card-${workspace.content.marginNotes.single.id}'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(card));
    await mouse.moveTo(tester.getCenter(card));
    await tester.pumpAndSettle();
    final menu = find.descendant(of: card, matching: find.byType(PopupMenuButton<Object>));
    await tester.tap(menu);
    await tester.pump();
    final route = ModalRoute.of(tester.element(find.text('Delete').last))!;
    debugPrint(
      'ANIMATION margin-note-more initial=${route.animation!.value}, duration=${(route as TransitionRoute).transitionDuration.inMilliseconds}ms',
    );
    await tester.pump(const Duration(milliseconds: 299));
    debugPrint('ANIMATION margin-note-more at299=${route.animation!.value}');
    await tester.pump(const Duration(milliseconds: 1));
    debugPrint('ANIMATION margin-note-more at300=${route.animation!.value}');
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
    await drain(tester);
  });
}
