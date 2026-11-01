import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/review/review_screen.dart';
import 'package:marginmind/features/workspace/widgets/selection_toolbar.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/shared/l10n.dart';
import 'package:mm_core/mm_core.dart' hide Card;
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../../packages/mm_pdf/test/support/pdf_backend.dart';
import 'helpers.dart';

const _selection = MMPdfSelection(
  pages: [
    AnnotationPage(page: 1, rects: [PageRect(30, 700, 90, 680)]),
    AnnotationPage(page: 2, rects: [PageRect(30, 700, 110, 680)]),
  ],
  text: 'End of first page\nStart of second page',
  viewportRect: Rect.fromLTWH(120, 200, 180, 100),
);

void main() {
  testWidgets('cross-page excerpt: toolbar, persistence, undo, export, review and first-page navigation', (
    tester,
  ) async {
    final repo = InMemoryStudySetContentRepository({
      'demo-1': StudySetContent(documents: [demoContent().documents.first]),
    });
    final container = await pumpApp(tester, content: repo);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final provider = workspaceProvider('demo-1');
    final controller = container.read(provider.notifier);
    await controller.onSelectionCommitted('c1', _selection);
    await tester.pumpAndSettle();
    expect(find.byType(SelectionToolbar), findsOneWidget);
    expect(
      tester.widget<MMFloatingToolbarLayout>(find.byType(MMFloatingToolbarLayout)).anchor,
      _selection.viewportRect,
    );
    await tester.tap(find.byTooltip('Add to Map'));
    await tester.pumpAndSettle();
    final saved = await repo.load('demo-1');
    final annotation = saved.annotations.single;
    final card = saved.cards.single;
    expect(annotation.pages.map((p) => p.page), [1, 2]);
    expect(annotation.pages.last.rects.single.right, 110);
    expect(annotation.quote, _selection.text);
    expect(find.text(_selection.text), findsOneWidget);
    // The format-2 representation retains the complete location after reopening.
    final decoded = StudySetContent.fromJson(saved.toJson());
    expect(decoded.annotations.single.toJson(), annotation.toJson());
    controller.revealCard(card.id);
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider('demo-1')).reveal!.page, 1);
    expect(container.read(workspaceProvider('demo-1')).reveal!.rects, _selection.pages.first.rects);
    final markdown = controller.export(opml: false, rootTitle: 'Book', source: (doc, page) => '${doc.title}:$page');
    final opml = controller.export(opml: true, rootTitle: 'Book', source: (doc, page) => '${doc.title}:$page');
    expect(markdown, contains('End of first page Start of second page'));
    expect(opml, contains('End of first page&#10;Start of second page'));
    expect(markdown, contains('${saved.documents.first.title}:1'));
    await controller.undo();
    expect((await repo.load('demo-1')).annotations, isEmpty);
    await controller.redo();
    expect((await repo.load('demo-1')).annotations.single.pages, hasLength(2));
    await settleHud(tester);
    container.read(navigationProvider.notifier).startReview('demo-1');
    await tester.pumpAndSettle();
    final l = tester.element(find.byType(ReviewScreen)).l10n;
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text(_selection.text), findsOneWidget);
    await tester.tap(find.text(l.revealSource));
    await tester.pumpAndSettle();
    expect(container.read(navigationProvider), isA<WorkspaceRoute>());
    expect(container.read(workspaceProvider('demo-1')).reveal!.page, 1);
    await settleHud(tester);
  });

  testWidgets('highlight-only and pen mode preserve all pages; reader renders one shared annotation', (tester) async {
    installTestPdfBackend();
    final repo = InMemoryStudySetContentRepository({
      'demo-1': StudySetContent(documents: [demoContent().documents.first]),
    });
    final container = await pumpApp(tester, content: repo, renderPdf: true);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final provider = workspaceProvider('demo-1');
    final controller = container.read(provider.notifier);
    await controller.highlight('c1', _selection, MMAnnotationColor.yellow);
    expect(controller.content.cards, isEmpty);
    final id = controller.content.annotations.single.id;
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      if (find.byType(MMPdfView).evaluate().isNotEmpty &&
          tester.widget<MMPdfView>(find.byType(MMPdfView)).controller.isReady) {
        break;
      }
    }
    var view = tester.widget<MMPdfView>(find.byType(MMPdfView));
    expect(view.controller.isReady, isTrue);
    expect(view.highlights.map((h) => h.page), [1, 2]);
    expect(view.highlights.map((h) => h.id).toSet(), {id});
    // Clicking the second page selects the same annotation and emphasizes both pages.
    view.onHighlightTap!(view.highlights.last.id, const Rect.fromLTWH(120, 200, 100, 20));
    await tester.pumpAndSettle();
    expect((container.read(provider).pending as PendingHighlight).annotationId, id);
    view = tester.widget<MMPdfView>(find.byType(MMPdfView));
    expect(view.highlights.every((h) => h.emphasized), isTrue);
    await controller.recolor(id, MMAnnotationColor.blue);
    await tester.pumpAndSettle();
    view = tester.widget<MMPdfView>(find.byType(MMPdfView));
    expect(view.highlights.every((h) => h.color == MMAnnotationColor.blue.color.withValues(alpha: 0.32)), isTrue);
    await controller.deleteHighlight(id);
    await tester.pumpAndSettle();
    expect(tester.widget<MMPdfView>(find.byType(MMPdfView)).highlights, isEmpty);
    await controller.setTool(AnnotationTool.highlight);
    await controller.onSelectionCommitted('c1', _selection);
    expect(controller.content.annotations.single.pages, hasLength(2));
    expect(controller.content.cards, hasLength(1));
    await settleHud(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
  });
}
