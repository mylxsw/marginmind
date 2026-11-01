import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/study_notes/note_view.dart';
import 'package:marginmind/features/workspace/widgets/map_pane.dart';
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/workspace/workspace_browser.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';
import 'study_notes_ui_test.dart' show noteFixture, openNote;

void main() {
  testWidgets('note owns the page; one More keeps note and workspace commands', (tester) async {
    await openNote(tester);
    final noteSidebar = tester.widget<MMSidebarItem>(find.byKey(const ValueKey('sidebar-note-written')));
    expect(noteSidebar.selected, isTrue);
    for (final item in tester.widgetList<MMSidebarItem>(
      find.descendant(of: find.byKey(const ValueKey('document-row-c1')), matching: find.byType(MMSidebarItem)),
    )) {
      expect(item.selected, isFalse);
    }
    expect(find.byType(StudyNoteView), findsOneWidget);
    expect(find.byType(ReaderPane), findsNothing);
    expect(find.byType(MapPane), findsNothing);
    expect(
      find.descendant(of: find.byType(MMToolbar), matching: find.byIcon(MMIcons.more)).hitTestable(),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('note-workspace-more')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('note-more')));
    await tester.pumpAndSettle();
    expect(find.text('Export Note…'), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace-command-organize-note')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settleHud(tester);
  });

  testWidgets('sidebar document and map choices supplement the pinned note', (tester) async {
    final container = await openNote(tester);
    final owner = container.read(workspaceProvider('demo-1').notifier);
    await tester.tap(find.byKey(ValueKey('sidebar-map-${MindMap.defaultId}')));
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider('demo-1')).activeNoteId, 'written');
    expect(container.read(workspaceProvider('demo-1')).noteReference, NoteReference.map);
    expect(find.byType(MapPane), findsOneWidget);
    final documentId = owner.content.documents.last.id;
    await tester.tap(find.byKey(ValueKey('document-row-$documentId')));
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider('demo-1')).activeNoteId, 'written');
    expect(container.read(workspaceProvider('demo-1')).noteReference, NoteReference.document);
    expect(container.read(workspaceProvider('demo-1')).activeDocumentId, documentId);
    expect(find.byType(ReaderPane), findsOneWidget);
    owner.closeNoteReference();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-back')));
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider('demo-1')).activeNoteId, isNull);
    expect(find.byType(StudyNoteView), findsNothing);
    await settleHud(tester);
  });

  testWidgets('source opens to the right; resizing and closing retain the note editor', (tester) async {
    final container = await openNote(tester);
    final owner = container.read(workspaceProvider('demo-1').notifier);
    final noteState = tester.state(find.byType(StudyNoteView));
    container.read(workspaceBrowserProvider('demo-1').notifier).show();
    await tester.tap(find.byKey(const ValueKey('note-source-quote')));
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider('demo-1')).activeNoteId, 'written');
    expect(container.read(workspaceProvider('demo-1')).noteReference, NoteReference.document);
    final noteRect = tester.getRect(find.byType(StudyNoteView));
    final sourceRect = tester.getRect(find.byType(ReaderPane));
    expect(sourceRect.left, greaterThanOrEqualTo(noteRect.right));
    expect(container.read(workspaceProvider('demo-1')).reveal?.page, 24);
    await tester.drag(find.byKey(const ValueKey('note-reference-divider')), const Offset(-70, 0));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(StudyNoteView)).width, lessThan(noteRect.width));
    await tester.tap(find.byKey(const ValueKey('note-reference-close')).hitTestable());
    await tester.pumpAndSettle();
    expect(find.byType(ReaderPane), findsNothing);
    expect(identical(tester.state(find.byType(StudyNoteView)), noteState), isTrue);
    await tester.tap(find.byKey(const ValueKey('note-title-written')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Still editing');
    owner.showNoteReference(NoteReference.map);
    await tester.pumpAndSettle();
    expect(find.byType(MapPane), findsOneWidget);
    expect(find.text('Still editing'), findsOneWidget);
    owner.closeNoteReference();
    await tester.pumpAndSettle();
    expect(find.text('Still editing'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(owner.content.studyNote('written')!.title, 'Still editing');
    await settleHud(tester);
  });

  testWidgets('map note source locates its owning map without replacing the note', (tester) async {
    final original = noteFixture();
    var n = 0;
    final editor = StudySetEditor(newId: () => 'linked-${n++}', now: () => testNow);
    final (withMap, map) = editor.addMap(original, title: 'Another map');
    final (content, card) = StudySetEditor(
      newId: () => 'linked-${n++}',
      now: () => testNow,
      mapId: map.id,
    ).addNote(withMap, text: 'Map source');
    final note = content.studyNotes.single;
    final container = await openNote(
      tester,
      content: content.copyWith(
        studyNotes: [
          note.copyWith(
            sections: [
              note.sections.single.copyWith(
                blocks: [
                  ...note.sections.single.blocks,
                  OwnBlock(id: 'linked-map', sourceId: card.id, source: OwnSource.card),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    await tester.tap(find.byKey(const ValueKey('note-own-source-link-linked-map')));
    await tester.pumpAndSettle();
    final state = container.read(workspaceProvider('demo-1'));
    expect(state.activeNoteId, 'written');
    expect(state.activeMapId, map.id);
    expect(state.selectedCardId, card.id);
    expect(state.noteReference, NoteReference.map);
    expect(find.byType(MapPane), findsOneWidget);
    expect(tester.getRect(find.byType(MapPane)).left, greaterThan(tester.getRect(find.byType(StudyNoteView)).left));
    await settleHud(tester);
  });

  for (final size in [const Size(393, 852), const Size(852, 393), const Size(820, 1180), const Size(1180, 820)]) {
    testWidgets('note source closes back to retained note at $size', (tester) async {
      final container = await openNote(tester, size: size, language: 'zh', touch: true, phone: size.shortestSide < 600);
      final owner = container.read(workspaceProvider('demo-1').notifier);
      final noteState = tester.state(find.byType(StudyNoteView));
      expect(find.byKey(const ValueKey('workspace-pane-switch')), findsNothing);
      expect(
        find.descendant(of: find.byType(MMToolbar), matching: find.byIcon(MMIcons.more)).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('note-source-quote')));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderPane), findsOneWidget);
      expect(find.byKey(const ValueKey('note-reference-close')).hitTestable(), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('note-reference-close')).hitTestable());
      await tester.pumpAndSettle();
      expect(identical(tester.state(find.byType(StudyNoteView)), noteState), isTrue);
      expect(container.read(workspaceProvider('demo-1')).activeNoteId, 'written');
      owner.showNoteReference(NoteReference.map);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('note-reference-close')).hitTestable(), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('note-reference-close')).hitTestable());
      await tester.pumpAndSettle();
      expect(find.byType(MapPane), findsNothing);
      expect(tester.takeException(), isNull);
      await settleHud(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  }
}
