import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/reflow_session.dart';
import 'package:marginmind/features/workspace/widgets/reflow_reader.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_book/mm_book.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'assistant_quick_actions_test.dart' show screenshot;
import 'helpers.dart';
import 'reflow_fixtures.dart';
import 'vocabulary_screenshots.dart' show loadVocabularyScreenshotFonts;

void main() {
  setUpAll(loadVocabularyScreenshotFonts);
  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    testWidgets('exact footnote link beside a saved mark wins over nearby matching with $kind', (tester) async {
      final repo = InMemoryStudySetContentRepository();
      final chapter = const EpubParser().parseHtml(
        'main',
        '<p>Marked<a href="#target">1</a> text</p>'
            '<p>${'body ' * 100}</p><h2 id="target">Footnote</h2><p>${'note ' * 100}</p>',
      );
      final doc = await storeBook(repo, book: Book('Footnote links', [chapter], {}, []));
      final container = await pumpApp(tester, content: repo);
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      final provider = workspaceProvider('demo-1');
      final workspace = container.read(provider.notifier);
      workspace.openDocument(doc.id);
      await tester.pumpAndSettle();
      final session = container.read(reflowSessionProvider(('demo-1', doc.id)));
      final anchor = session.book!.chapters.first.anchor(0, 6, revision: doc.revision!);
      await workspace.highlightSource(doc.id, SourceSelection.text([anchor]), MMAnnotationColor.yellow);
      await tester.pumpAndSettle();
      final surface = find.byKey(const ValueKey('reflow-surface'));
      final layout = (tester.widget<CustomPaint>(surface).painter as ReflowReaderPainter).layout;
      final linkBox = layout.boxes(layout.links.single.anchor).first.rect;
      final markBox = layout.boxes(anchor).first.rect;
      final point = linkBox.centerLeft + const Offset(1, 0);
      expect(linkBox.contains(point), isTrue);
      expect(markBox.contains(point), isFalse);
      expect(point.dx - markBox.right, lessThan(3));
      await tester.tapAt(tester.getTopLeft(surface) + point, kind: kind);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(container.read(provider).pending, isNull);
      expect(session.position!.offset, chapter.elementOffsets['target']);
      expect(workspace.content.annotations, hasLength(1));
      await settleHud(tester);
      expect(tester.takeException(), isNull);
    });
  }
  for (final appearance in ['light', 'dark']) {
    testWidgets('iPad edits saved marks with tap tolerance and persistent feedback in $appearance', (tester) async {
      final repo = InMemoryStudySetContentRepository();
      final doc = await storeBook(repo);
      final container = await pumpApp(
        tester,
        content: repo,
        size: const Size(1194, 834),
        prefs: {'settings.appearance': appearance, 'settings.language': 'zh'},
        overrides: [touchPlatformProvider.overrideWithValue(true)],
      );
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      final provider = workspaceProvider('demo-1');
      final workspace = container.read(provider.notifier);
      workspace.openDocument(doc.id);
      await tester.pumpAndSettle();
      final session = container.read(reflowSessionProvider(('demo-1', doc.id)));
      final chapter = session.book!.chapters.first;
      final start = chapter.canonicalText.indexOf('Source anchors');
      final anchor = chapter.anchor(start, start + 'Source anchors'.length, revision: doc.revision!);
      workspace.toggleSyncToMap(); // Standalone marks must have editing feedback too.
      await workspace.onSourceSelectionCommitted(doc.id, SourceSelection.text([anchor]));
      await workspace.applyPendingTextAnnotation(AnnotationTool.highlight);
      workspace.dismissPending();
      await tester.pumpAndSettle();
      final id = workspace.content.annotations.single.id;
      final surface = find.byKey(const ValueKey('reflow-surface'));
      final box = (tester.widget<CustomPaint>(surface).painter as ReflowReaderPainter).layout.boxes(anchor).first.rect;
      final nearby = tester.getTopLeft(surface) + box.centerRight + const Offset(8, 0);
      await tester.tapAt(nearby);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect((container.read(provider).pending as PendingHighlight).annotationId, id);
      expect(find.bySemanticsLabel('Selection start'), findsNothing);
      final highlight = find.byKey(const ValueKey('selection-highlight'));
      final underline = find.byKey(const ValueKey('selection-underline'));
      expect(tester.widget<MMToolbarButton>(highlight).selected, isTrue);
      expect(tester.widget<MMToolbarButton>(underline).selected, isFalse);
      final painter = tester.widget<CustomPaint>(surface).painter as ReflowReaderPainter;
      expect(painter.editing, id);
      await settleHud(tester);
      expect((tester.widget<CustomPaint>(surface).painter as ReflowReaderPainter).editing, id);
      await screenshot(tester, 'ipad-edit-highlight-$appearance', target: find.byType(MarginMindApp));
      await tester.tap(underline);
      await tester.pumpAndSettle();
      expect(workspace.content.annotations.single.kind, AnnotationKind.underline);
      expect(workspace.content.cards, isEmpty);
      expect(container.read(provider).pending, isNull);
      // Long-press edits an old mark rather than selecting a new word.
      await tester.longPressAt(nearby);
      await tester.pumpAndSettle();
      expect((container.read(provider).pending as PendingHighlight).annotationId, id);
      expect(tester.widget<MMToolbarButton>(underline).selected, isTrue);
      expect(tester.widget<MMToolbarButton>(highlight).selected, isFalse);
      expect(find.bySemanticsLabel('Selection start'), findsNothing);
      await screenshot(tester, 'ipad-edit-underline-$appearance', target: find.byType(MarginMindApp));
      workspace.dismissPending();
      await tester.pumpAndSettle();
      expect((tester.widget<CustomPaint>(surface).painter as ReflowReaderPainter).editing, isNull);
      // Mouse precision stays tighter than touch precision.
      await tester.tapAt(nearby, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(container.read(provider).pending, isNull);
      expect(workspace.content.annotations, hasLength(1));
      await settleHud(tester);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  }
}
