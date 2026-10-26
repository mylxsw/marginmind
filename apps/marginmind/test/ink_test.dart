import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app_commands.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/widgets/reader_ink_toolbar.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../../packages/mm_pdf/test/support/pdf_backend.dart';
import 'helpers.dart';

MMPdfInkDraft _draft({int page = 3, double x = 10}) => MMPdfInkDraft(
  page: page,
  tool: InkTool.pen,
  colorIndex: MMInkColor.blue.index,
  width: MMInkWidth.thin.points,
  points: [InkPoint(x, 100), InkPoint(x + 50, 120)],
);

void main() {
  test('the pen is per window and session; shape, color and width are its own', () async {
    final overrides = await testOverrides(prefs: {'settings.annotationTool': 'highlight'});
    var container = ProviderContainer(overrides: overrides);
    final provider = workspaceProvider('demo-1');
    var controller = container.read(provider.notifier);
    expect(container.read(provider).ink, isNull);
    await controller.toggleInkTool();
    expect(container.read(provider).tool, AnnotationTool.ink);
    expect(container.read(sharedPreferencesProvider).getString('settings.annotationTool'), 'highlight');
    expect(
      container.read(provider).ink,
      MMPdfInk(tool: MMPdfInkTool.freehand, colorIndex: MMInkColor.red.index, width: MMInkWidth.medium.points),
    );

    controller.setInkTool(MMPdfInkTool.eraser);
    expect(container.read(provider).ink!.tool, MMPdfInkTool.eraser);
    controller.setInkColor(MMInkColor.blue);
    expect(container.read(provider).ink!.tool, MMPdfInkTool.freehand, reason: 'a color means drawing again');
    expect(container.read(provider).ink!.colorIndex, MMInkColor.blue.index);
    controller.setInkTool(MMPdfInkTool.eraser);
    controller.setInkWidth(MMInkWidth.bold);
    expect(container.read(provider).ink!.tool, MMPdfInkTool.freehand);
    expect(container.read(provider).ink!.width, MMInkWidth.bold.points);
    controller.setInkTool(MMPdfInkTool.arrow);
    controller.setInkWidth(MMInkWidth.thin);
    expect(container.read(provider).ink!.tool, MMPdfInkTool.arrow);

    await controller.exitInk();
    expect(container.read(provider).tool, AnnotationTool.select);
    await controller.exitInk();
    expect(container.read(provider).tool, AnnotationTool.select);
    await controller.toggleInkTool();
    await controller.toggleInkTool();
    expect(container.read(provider).tool, AnnotationTool.select);

    // A pen left out never comes back armed.
    await controller.toggleInkTool();
    container.dispose();
    container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    controller = container.read(provider.notifier);
    expect(container.read(provider).tool, AnnotationTool.select);
    await container.read(sharedPreferencesProvider).setString('settings.annotationTool', 'ink');
    final restarted = ProviderContainer(overrides: overrides);
    addTearDown(restarted.dispose);
    expect(restarted.read(provider).tool, AnnotationTool.select);
  });

  test('each stroke and each erase is one undo step', () async {
    final repo = InMemoryStudySetContentRepository({'demo-1': demoContent()});
    final container = ProviderContainer(overrides: await testOverrides(content: repo));
    addTearDown(container.dispose);
    final provider = workspaceProvider('demo-1');
    container.listen(provider, (_, _) {});
    await container.read(contentProvider('demo-1').future);
    final controller = container.read(provider.notifier);

    await controller.addInkStroke('c1', _draft());
    final first = controller.content.inkStrokes.single;
    expect(first.documentId, 'c1');
    expect(first.page, 3);
    expect(first.colorIndex, MMInkColor.blue.index);
    expect(first.width, MMInkWidth.thin.points);
    expect(first.points, hasLength(2));
    expect(container.read(provider).canUndo, isTrue);
    await controller.undo();
    expect(controller.content.inkStrokes, isEmpty);
    await controller.redo();
    expect(controller.content.inkStrokes.single.id, first.id);

    await controller.addInkStroke('c1', _draft(x: 200));
    expect(controller.content.inkStrokes, hasLength(2));
    await controller.eraseInkStrokes({for (final s in controller.content.inkStrokes) s.id});
    expect(controller.content.inkStrokes, isEmpty);
    await controller.undo();
    expect(controller.content.inkStrokes, hasLength(2), reason: 'one gesture, one step');
    await controller.undo();
    expect(controller.content.inkStrokes, hasLength(1));

    // Nothing to do, a vanished document and a page it does not have.
    final before = controller.content;
    await controller.eraseInkStrokes({});
    await controller.addInkStroke('gone', _draft());
    await controller.addInkStroke('c1', _draft(page: 999));
    expect(controller.content.inkStrokes, before.inkStrokes);
  });

  testWidgets('⇧⌘M, the pen bar, drawing, undo and Esc on the reader', (tester) async {
    installTestPdfBackend();
    final repo = InMemoryStudySetContentRepository({
      'demo-1': StudySetContent(documents: [demoContent().documents.first]),
    });
    final container = await pumpApp(tester, content: repo, renderPdf: true);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final provider = workspaceProvider('demo-1');
    final controller = container.read(provider.notifier);
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      if (find.byType(MMPdfView).evaluate().isNotEmpty &&
          tester.widget<MMPdfView>(find.byType(MMPdfView)).controller.isReady) {
        break;
      }
    }
    final l = AppLocalizations.of(tester.element(find.byType(MMPdfView)));
    final shortcut = AppShortcuts.toggleInkTool;
    expect(shortcut.trigger, LogicalKeyboardKey.keyM);
    expect(shortcut.shift, isTrue);
    expect(find.byTooltip(AppShortcuts.tip(l.toolPen, shortcut)), findsOneWidget);
    expect(find.byType(ReaderInkToolbar), findsNothing);

    // The reader has the keyboard once clicked.
    await tester.tap(find.byType(MMPdfView), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    final modifier = shortcut.meta ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(modifier);
    await tester.pumpAndSettle();
    expect(container.read(provider).tool, AnnotationTool.ink);
    expect(find.byType(ReaderInkToolbar), findsOneWidget);
    expect(tester.widget<MMPdfView>(find.byType(MMPdfView)).ink, isNotNull);

    await tester.tap(find.byTooltip(l.inkEraser));
    await tester.pump();
    expect(container.read(provider).inkTool, MMPdfInkTool.eraser);
    await tester.tap(find.byTooltip(l.inkEllipse));
    await tester.tap(find.byTooltip(l.colorBlack));
    await tester.tap(find.byTooltip(l.inkBold));
    await tester.pump();
    expect(container.read(provider).ink, MMPdfInk(tool: MMPdfInkTool.ellipse, colorIndex: 5, width: 4));
    await tester.tap(find.byTooltip(l.inkFreehand));
    await tester.pump();

    // A real drag near the top of page 1 becomes a stroke of this document.
    final start = tester.getTopLeft(find.byType(MMPdfView)) + const Offset(100, 100);
    final gesture = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
    await gesture.moveTo(start + const Offset(50, 30));
    await tester.pump();
    await gesture.moveTo(start + const Offset(150, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    final stroke = controller.content.inkStrokes.single;
    expect(stroke.documentId, controller.content.documents.first.id);
    expect(stroke.page, 1);
    expect(stroke.colorIndex, 5);
    expect(stroke.points, hasLength(3));
    expect(tester.widget<MMPdfView>(find.byType(MMPdfView)).inkStrokes.single.id, stroke.id);

    // A click with the eraser removes the whole stroke; the bar's undo
    // brings it back, and undoes the stroke itself next.
    await tester.tap(find.byTooltip(l.inkEraser));
    await tester.pump();
    await tester.tapAt(start);
    await tester.pumpAndSettle();
    expect(controller.content.inkStrokes, isEmpty);
    final undo = find.byTooltip(AppShortcuts.tip(l.undo, AppShortcuts.undo));
    await tester.tap(undo);
    await tester.pumpAndSettle();
    expect(controller.content.inkStrokes.single.id, stroke.id);
    expect(find.text(l.undoneHud), findsOneWidget);
    await tester.tap(undo);
    await tester.pumpAndSettle();
    expect(controller.content.inkStrokes, isEmpty);

    // Esc puts the pen down; Select works as before.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(container.read(provider).tool, AnnotationTool.select);
    expect(find.byType(ReaderInkToolbar), findsNothing);
    expect(tester.widget<MMPdfView>(find.byType(MMPdfView)).ink, isNull);

    await tester.tap(find.byTooltip(AppShortcuts.tip(l.toolPen, shortcut)));
    await tester.pumpAndSettle();
    expect(container.read(provider).tool, AnnotationTool.ink);
    await tester.tap(find.text(l.done));
    await tester.pumpAndSettle();
    expect(container.read(provider).tool, AnnotationTool.select);

    await settleHud(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
  });
}
