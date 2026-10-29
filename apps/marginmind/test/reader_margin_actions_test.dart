import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/reader_margin.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../../packages/mm_pdf/test/support/pdf_backend.dart';
import 'helpers.dart';
import 'reader_crop_test.dart' show drain;

class DelayedRepository extends InMemoryStudySetContentRepository {
  DelayedRepository() : super({'demo-1': demoContent()});
  bool fail = false;
  Completer<void>? gate;
  @override
  Future<StudySetContent> update(String id, StudySetContent Function(StudySetContent) change) async {
    if (fail) throw StateError('Disk unavailable');
    await gate?.future;
    return super.update(id, change);
  }
}

void main() {
  setUp(installTestPdfBackend);
  testWidgets('highlight anchor reopens one note; card controls add, copy, recolor, locate and delete', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final repository = DelayedRepository();
    final container = await pumpApp(tester, renderPdf: true, content: repository, size: const Size(1800, 1000));
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await drain(tester);
    final workspace = container.read(workspaceProvider('demo-1').notifier);
    final session = container.read(readerMarginProvider('demo-1').notifier);
    workspace.setLayout(MMSplitMode.primary);
    await drain(tester);
    const selection = MMPdfSelection(text: 'Source quote', page: 1, rects: [PageRect(40, 700, 200, 680)]);
    await workspace.highlight('c1', selection, MMAnnotationColor.blue);
    final annotation = workspace.content.annotations.last;
    workspace.tapHighlight(annotation.id, const Rect.fromLTWH(100, 200, 160, 20));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('selection-margin-note')));
    await drain(tester);
    final draft = container.read(readerMarginProvider('demo-1')).draft!;
    expect(draft.colorIndex, MMAnnotationColor.blue.index);
    await tester.enterText(find.byKey(ValueKey('margin-editor-${draft.id}')), 'My comment');
    await session.finish();
    await drain(tester);
    await session.start('c1', pages: selection.pages, quote: selection.text);
    expect(container.read(readerMarginProvider('demo-1')).draft!.id, draft.id);
    await session.finish();
    await drain(tester);
    final card = find.byKey(ValueKey('margin-card-${draft.id}'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(card));
    await mouse.moveTo(tester.getCenter(card));
    await tester.pumpAndSettle();
    Finder within(Finder child) => find.descendant(of: card, matching: child);
    repository.fail = true;
    await tester.tap(within(find.byTooltip('Add to Map')));
    await drain(tester);
    expect(workspace.content.marginNotes.single.nodeId, isNull);
    repository.fail = false;
    await tester.tap(within(find.byTooltip('Add to Map')));
    await drain(tester);
    final linked = workspace.content.marginNotes.single;
    final linkedCard = workspace.content.card(linked.nodeId!)!;
    expect(linkedCard.kind, CardKind.excerpt);
    expect(linkedCard.body, 'Source quote');
    expect(container.read(workspaceProvider('demo-1')).layout, MMSplitMode.primary);
    await tester.tap(within(find.byType(PopupMenuButton<Object>)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy').last);
    await tester.pumpAndSettle();
    expect(copied, 'My comment');
    await tester.tap(within(find.byType(PopupMenuButton<Object>)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Orange').last);
    await drain(tester);
    expect(workspace.content.marginNotes.single.colorIndex, MMAnnotationColor.orange.index);
    await tester.tap(within(find.byType(PopupMenuButton<Object>)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await drain(tester);
    expect(workspace.content.marginNotes, isEmpty);
    expect(workspace.content.card(linkedCard.id), isNotNull);
    await workspace.undo();
    await drain(tester);
    await workspace.locateMarginNote(draft.id, showMap: false);
    expect(container.read(workspaceProvider('demo-1')).layout, MMSplitMode.primary);
    await mouse.removePointer();
    await settleHud(tester);
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed writes retain draft, concurrent finish coalesces and typing during persistence survives', (
    tester,
  ) async {
    final repository = DelayedRepository();
    final container = await pumpApp(tester, content: repository);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final workspace = container.read(workspaceProvider('demo-1').notifier);
    final session = container.read(readerMarginProvider('demo-1').notifier);
    await session.start('c1', page: 1, lineY: 500);
    session.text('First');
    repository.fail = true;
    expect(await session.finish(), false);
    expect(container.read(readerMarginProvider('demo-1')).draft!.text, 'First');
    expect(workspace.content.marginNotes, isEmpty);
    repository.fail = false;
    repository.gate = Completer<void>();
    final saving = session.finish();
    expect(identical(saving, session.finish()), true);
    session.text('Typed during save');
    repository.gate!.complete();
    expect(await saving, true);
    expect(workspace.content.marginNotes.single.text, 'Typed during save');
    await session.start('c1', existing: workspace.content.marginNotes.single);
    repository.fail = true;
    await session.delete(workspace.content.marginNotes.single);
    expect(container.read(readerMarginProvider('demo-1')).draft, isNotNull);
    expect(workspace.content.marginNotes, hasLength(1));
    await session.recolor(workspace.content.marginNotes.single, 3);
    repository.fail = false;
    await session.recolor(workspace.content.marginNotes.single, 3);
    await session.finish();
    expect(workspace.content.marginNotes.single.colorIndex, 3);
    await session.start('c1', existing: workspace.content.marginNotes.single);
    session.text('Before switch');
    workspace.openDocument(workspace.content.documents.last.id);
    await tester.pumpAndSettle();
    expect(workspace.content.marginNotes.single.text, 'Before switch');
    session.show(workspace.content.marginNotes);
    await session.close();
    expect(container.read(readerMarginProvider('demo-1')).popup, isEmpty);
    session.text('Ignored without draft');
    await session.start('c1', page: 1, lineY: 300);
    await session.delete(container.read(readerMarginProvider('demo-1')).draft!);
    expect(container.read(readerMarginProvider('demo-1')).draft, isNull);
    await settleHud(tester);
  });
}
