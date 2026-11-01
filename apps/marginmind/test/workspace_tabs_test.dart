import 'dart:async';

import 'package:marginmind/features/workspace/widgets/card_details.dart';
import 'package:marginmind/features/assistant/assistant_entry.dart';
import 'package:flutter/services.dart';

import 'reader_navigation_test.dart' show pressWithControl;

import 'package:marginmind/app/app.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/study_notes/note_view.dart';
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';
import 'package:marginmind/features/workspace/widgets/reference_content.dart';
import 'package:marginmind/features/workspace/widgets/tag_content_pane.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';

import 'helpers.dart';
import 'study_notes_ui_test.dart' show noteFixture;

Future<ProviderContainer> openTabs(
  WidgetTester tester, {
  StudySetContent? content,
  InMemoryStudySetContentRepository? repository,
  Size size = const Size(1536, 1092),
  bool touch = false,
}) async {
  var data = content ?? noteFixture();
  data = data.copyWith(
    studyNotes: [
      data.studyNotes.first,
      StudyNote.fromJson({...data.studyNotes.first.toJson(), 'id': 'second', 'title': 'Second note'}),
    ],
  );
  final container = await pumpApp(
    tester,
    size: size,
    content: repository ?? InMemoryStudySetContentRepository({'demo-1': data}),
    overrides: [
      if (touch) touchPlatformProvider.overrideWithValue(true),
      if (touch) phoneProvider.overrideWithValue(size.width < 600),
    ],
  );
  container.read(navigationProvider.notifier).openStudySet('demo-1');
  await tester.pumpAndSettle();
  return container;
}

class _DelayedRepository extends InMemoryStudySetContentRepository {
  _DelayedRepository(super.initial);
  Future<void>? gate;
  @override
  Future<StudySetContent> update(String id, StudySetContent Function(StudySetContent) change) async {
    final waiting = gate;
    gate = null;
    if (waiting != null) await waiting;
    return super.update(id, change);
  }
}

void main() {
  testWidgets('sidebar opens per-note tabs and reusable document, vocabulary, review tabs', (tester) async {
    final c = await openTabs(tester);
    final owner = c.read(workspaceProvider('demo-1').notifier);
    await tester.tap(find.byKey(const ValueKey('sidebar-note-written')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sidebar-note-second')));
    await tester.pumpAndSettle();
    owner.activateTab(WorkspaceTab.vocabulary);
    owner.activateTab(WorkspaceTab.review);
    owner.activateTab(WorkspaceTab.vocabulary);
    owner.activateTab(WorkspaceTab.review);
    await tester.pumpAndSettle();
    expect(c.read(workspaceProvider('demo-1')).tabs.open.map((t) => t.id), [
      'documentMap',
      'note:written',
      'note:second',
      'vocabulary',
      'review',
    ]);
    expect(c.read(navigationProvider), isA<WorkspaceRoute>());
    owner.openDocument('c2');
    await tester.pumpAndSettle();
    expect(c.read(workspaceProvider('demo-1')).tabs.activeId, 'documentMap');
    owner.openStudyNote('written');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('document-row-c1')));
    await tester.pumpAndSettle();
    expect(c.read(workspaceProvider('demo-1')).tabs.activeId, 'documentMap');
    expect(c.read(workspaceProvider('demo-1')).tabs.open.length, 5);
    expect(tester.takeException(), isNull);
  });
  testWidgets('reference reader is isolated and retained across owner and tag switches', (tester) async {
    final c = await openTabs(tester);
    final owner = c.read(workspaceProvider('demo-1').notifier);
    owner.openDocument('c2');
    owner.openStudyNote('written');
    await tester.pumpAndSettle();
    final noteState = tester.state(find.byType(StudyNoteView));
    await tester.tap(find.byKey(const ValueKey('note-source-quote')));
    await tester.pumpAndSettle();
    expect(identical(c.read(workspaceProvider('demo-1').notifier), owner), isTrue);
    expect(c.read(workspaceProvider('demo-1')).activeDocumentId, 'c2');
    expect(c.read(workspaceProvider('demo-1')).activeNoteId, 'written');
    expect(c.read(workspaceProvider('demo-1')).panel, RightPanel.reference);
    final reference = tester.state(find.byType(ReferenceContent));
    final reader = find.descendant(of: find.byType(ReferenceContent), matching: find.byType(ReaderPane));
    final nested = ProviderScope.containerOf(tester.element(reader));
    expect(nested.read(workspaceProvider('demo-1')).activeDocumentId, 'c1');
    expect(nested.read(workspaceProvider('demo-1')).reveal?.page, 24);
    expect(identical(nested.read(readerPdfProvider('demo-1')), c.read(readerPdfProvider('demo-1'))), isFalse);
    owner.openStudyNote('second');
    await tester.pumpAndSettle();
    expect(find.byType(ReferenceContent), findsNothing);
    owner.openStudyNote('written');
    await tester.pumpAndSettle();
    expect(identical(tester.state(find.byType(ReferenceContent)), reference), isTrue);
    expect(identical(tester.state(find.byType(StudyNoteView)), noteState), isTrue);
    owner.openPanel(RightPanel.assistant);
    await tester.pumpAndSettle();
    owner.closePanel();
    await tester.pumpAndSettle();
    expect(identical(tester.state(find.byType(ReferenceContent)), reference), isTrue);
    owner.showTags();
    await tester.pumpAndSettle();
    owner.closePanel();
    await tester.pumpAndSettle();
    expect(identical(tester.state(find.byType(ReferenceContent)), reference), isTrue);
    owner.closeTab('note:written');
    await tester.pumpAndSettle();
    expect(c.read(workspaceProvider('demo-1')).tabs.contexts.containsKey('note:written'), isFalse);
    expect(find.byType(ReferenceContent, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('replacing shared subject closes only that subjects reference', (tester) async {
    final c = await openTabs(tester);
    final owner = c.read(workspaceProvider('demo-1').notifier);
    owner.openStudyNote('written');
    owner.openDocumentReference('c1');
    owner.activateTab(WorkspaceTab.documents);
    owner.openStudyNoteReference('second');
    await tester.pumpAndSettle();
    owner.openDocument('c2');
    await tester.pumpAndSettle();
    final state = c.read(workspaceProvider('demo-1'));
    expect(state.tabs.current.reference, isNull);
    expect(state.panel, isNull);
    expect(state.tabs.contexts['note:written']!.reference!.id, 'c1');
    expect(tester.takeException(), isNull);
  });
  testWidgets('tag drawer finds another map and focuses correct shared document/map', (tester) async {
    var n = 0;
    final editor = StudySetEditor(newId: () => 'cross-${n++}', now: () => testNow);
    final (withMap, map) = editor.addMap(noteFixture(), title: 'Other map');
    final scoped = StudySetEditor(newId: () => 'cross-${n++}', now: () => testNow, mapId: map.id);
    final (data, excerpt) = scoped.createExcerpt(
      withMap,
      documentId: 'c2',
      page: 3,
      rects: const [PageRect(1, 2, 30, 40)],
      quote: 'Cross-map topic',
      colorIndex: 0,
    );
    final c = await openTabs(tester, content: scoped.setTags(data, excerpt.id, ['Focus']));
    final owner = c.read(workspaceProvider('demo-1').notifier);
    owner.openStudyNote('written');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sidebar-tags')));
    await tester.pumpAndSettle();
    owner.filterTag('Focus');
    await tester.pumpAndSettle();
    expect(c.read(workspaceProvider('demo-1')).activeNoteId, 'written');
    expect(find.byType(TagContentPane), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('tag-result-${map.id}-${excerpt.id}')));
    await tester.pumpAndSettle();
    final state = c.read(workspaceProvider('demo-1'));
    expect(state.tabs.activeId, 'documentMap');
    expect(state.activeDocumentId, 'c2');
    expect(state.activeMapId, map.id);
    expect(state.selectedCardId, excerpt.id);
    expect(state.panel, isNull);
    expect(state.tagFilter, isNull);
    expect(state.tabs.open.length, 2);
    expect(tester.takeException(), isNull);
    await settleHud(tester);
  });
  testWidgets('choosing a tag closes its origin drawer and retains references when the subject is unchanged', (
    tester,
  ) async {
    final c = await openTabs(tester);
    final owner = c.read(workspaceProvider('demo-1').notifier);
    owner.openDocument('c1');
    owner.openStudyNoteReference('written');
    final sharedReference = c.read(workspaceProvider('demo-1')).tabs.current.reference;
    owner.openStudyNote('second');
    owner.openDocumentReference('c2');
    final noteReference = c.read(workspaceProvider('demo-1')).tabs.current.reference;
    owner.showTags();
    final node = owner.content.nodes.first;
    await owner.revealTagTopic(node.mapId, node.cardId);
    await tester.pumpAndSettle();
    final state = c.read(workspaceProvider('demo-1'));
    expect(state.tabs.activeId, WorkspaceTab.documents.id);
    expect(state.tabs.current.reference, same(sharedReference));
    expect(state.panel, RightPanel.reference);
    expect(state.tabs.contexts['note:second']?.panel, RightPanel.reference);
    expect(state.tabs.contexts['note:second']?.reference, same(noteReference));
    expect(tester.takeException(), isNull);
    await settleHud(tester);
  });
  testWidgets('opening and closing overflowing tabs keeps the active tab visible', (tester) async {
    final c = await openTabs(tester, size: const Size(900, 820));
    final owner = c.read(workspaceProvider('demo-1').notifier);
    final original = owner.content.studyNotes.first;
    await c
        .read(contentRepositoryProvider)
        .update(
          'demo-1',
          (content) => content.copyWith(
            studyNotes: [
              ...content.studyNotes,
              for (var i = 0; i < 8; i++)
                StudyNote.fromJson({...original.toJson(), 'id': 'long-$i', 'title': 'Long reading note number $i'}),
            ],
          ),
        );
    await tester.pumpAndSettle();
    for (var i = 0; i < 8; i++) {
      owner.openStudyNote('long-$i');
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workspace-tab-note:long-7')).hitTestable(), findsOneWidget);
    owner.closeTab('note:long-7');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workspace-tab-note:long-6')).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('reference edits share chronological undo with main edits', (tester) async {
    final c = await openTabs(tester);
    final owner = c.read(workspaceProvider('demo-1').notifier);
    final original = owner.content.nodes.first.cardId;
    final added = await owner.addTopic('Main edit');
    owner.openReference(WorkspaceReference.map(MindMap.defaultId));
    await tester.pumpAndSettle();
    final child = referenceWorkspace(tester);
    await child.setTags(original, ['Reference edit']);
    await tester.pumpAndSettle();
    await owner.undo();
    await tester.pumpAndSettle();
    expect(
      owner.content.card(added.id),
      isNotNull,
      reason: 'undo the latest reference edit before the older main edit',
    );
    expect(owner.content.card(original)!.tags, isNot(contains('Reference edit')));
    expect(referenceState(tester).canRedo, isTrue);
    await child.redo();
    await tester.pumpAndSettle();
    owner.closePanel();
    await tester.pumpAndSettle();
    await owner.undo();
    expect(owner.content.card(added.id), isNotNull);
    expect(owner.content.card(original)!.tags, isNot(contains('Reference edit')));
    await settleHud(tester);
    expect(tester.takeException(), isNull);
  });
  for (final leaveWorkspace in [false, true]) {
    testWidgets('closing a reference finishes its queued transaction; leave workspace: $leaveWorkspace', (
      tester,
    ) async {
      final repo = _DelayedRepository({'demo-1': noteFixture()});
      final c = await openTabs(tester, repository: repo);
      final owner = c.read(workspaceProvider('demo-1').notifier);
      final cardId = owner.content.nodes.first.cardId;
      owner.openReference(WorkspaceReference.map(MindMap.defaultId));
      await tester.pumpAndSettle();
      final child = referenceWorkspace(tester);
      var modelDisposed = false;
      final lifetime = Provider<void>((ref) {
        ref.watch(workspaceProvider('demo-1').notifier);
        ref.onDispose(() => modelDisposed = true);
      }, dependencies: [workspaceProvider]);
      referenceContainer(tester).read(lifetime);
      await child.beginTransaction();
      final gate = Completer<void>();
      repo.gate = gate.future;
      final saving = child.setTags(cardId, ['Saved before closing']);
      await tester.pump();
      if (leaveWorkspace) {
        c.read(navigationProvider.notifier).showLibrary();
      } else {
        owner.closeTab(WorkspaceTab.documents.id);
      }
      await tester.pumpAndSettle();
      expect(find.byType(ReferenceContent), findsNothing);
      expect(modelDisposed, isFalse, reason: 'the hidden editor stays alive only until its save completes');
      gate.complete();
      await saving;
      await tester.pumpAndSettle();
      expect((await repo.load('demo-1')).card(cardId)!.tags, contains('Saved before closing'));
      expect(modelDisposed, isTrue);
      expect(c.read(workspaceProvider('demo-1')).canUndo, isTrue);
      await owner.undo();
      expect(owner.content.card(cardId)!.tags, isNot(contains('Saved before closing')));
      await settleHud(tester);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('a reference map opens its own card details and its close button closes only the reference', (
    tester,
  ) async {
    final c = await openTabs(tester);
    final owner = c.read(workspaceProvider('demo-1').notifier);
    final node = owner.content.nodes.first;
    owner.openStudyNote('written');
    owner.openReference(WorkspaceReference.map(node.mapId));
    await tester.pumpAndSettle();
    referenceWorkspace(tester).showDetails(node.cardId);
    await tester.pumpAndSettle();
    expect(c.read(workspaceProvider('demo-1')).tabs.current.reference?.kind, WorkspaceReferenceKind.card);
    expect(c.read(workspaceProvider('demo-1')).activeNoteId, 'written');
    expect(find.byType(CardDetails), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(CardDetails), matching: find.byTooltip('Close')));
    await tester.pumpAndSettle();
    expect(c.read(workspaceProvider('demo-1')).panel, isNull);
    expect(c.read(workspaceProvider('demo-1')).activeNoteId, 'written');
    expect(tester.takeException(), isNull);
  });
  testWidgets('reference document switching and closing keep the main note intact', (tester) async {
    final c = await openTabs(tester);
    final owner = c.read(workspaceProvider('demo-1').notifier);
    owner.openStudyNote('written');
    owner.openDocumentReference('c1');
    await tester.pumpAndSettle();
    await openReaderDocumentMenu(tester);
    final other = owner.content.document('c2')!.title;
    await tester.tap(find.text(other).last);
    await tester.pumpAndSettle();
    expect(c.read(workspaceProvider('demo-1')).tabs.current.reference?.id, 'c2');
    expect(c.read(workspaceProvider('demo-1')).activeDocumentId, 'c1');
    expect(referenceState(tester).activeDocumentId, 'c2');
    await openReaderDocumentMenu(tester);
    await tester.tap(find.text('Close Current Document'));
    await tester.pumpAndSettle();
    expect(c.read(workspaceProvider('demo-1')).activeNoteId, 'written');
    expect(c.read(workspaceProvider('demo-1')).panel, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('background documents do not become automatic AI context on other tabs', (tester) async {
    final c = await openTabs(tester);
    final owner = c.read(workspaceProvider('demo-1').notifier);
    expect(c.read(assistantAutoContextsProvider('demo-1')), isNotEmpty);
    for (final tab in [
      const WorkspaceTab(WorkspaceTabKind.note, noteId: 'written'),
      WorkspaceTab.vocabulary,
      WorkspaceTab.review,
    ]) {
      owner.activateTab(tab);
      expect(c.read(assistantAutoContextsProvider('demo-1')), isEmpty);
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('removing a shared subject closes only the shared tab reference', (tester) async {
    final c = await openTabs(tester);
    final owner = c.read(workspaceProvider('demo-1').notifier);
    owner.openStudyNote('second');
    owner.openDocumentReference('c2');
    final retained = c.read(workspaceProvider('demo-1')).tabs.current.reference;
    owner.openDocument('c1');
    owner.openStudyNoteReference('written');
    await tester.pumpAndSettle();
    await owner.removeDocument('c1');
    await tester.pumpAndSettle();
    final tabs = c.read(workspaceProvider('demo-1')).tabs;
    expect(tabs.contexts[WorkspaceTab.documents.id]?.reference, isNull);
    expect(tabs.contexts['note:second']?.reference, same(retained));
    expect(c.read(workspaceProvider('demo-1')).panel, isNull);
    expect(tester.takeException(), isNull);
    await settleHud(tester);
  });
  testWidgets('the same document has independent live page indicators in the reference reader', (tester) async {
    final c = await openTabs(tester);
    final owner = c.read(workspaceProvider('demo-1').notifier);
    owner.recordPage('c1', 3);
    owner.openDocumentReference('c1');
    await tester.pumpAndSettle();
    final nested = ProviderScope.containerOf(tester.element(find.byType(ReaderPane).last));
    final reference = nested.read(workspaceProvider('demo-1').notifier);
    reference.recordPage('c1', 9);
    await tester.pump();
    expect(c.read(readingPagesProvider('demo-1'))['c1'], 3);
    expect(nested.read(readingPagesProvider('demo-1'))['c1'], 9);
    expect(owner.activePage, 3);
    expect(reference.activePage, 9);
    expect(identical(c.read(workspaceProvider('demo-1').notifier), owner), isTrue);
    owner.closePanel();
    await settleHud(tester);
    expect(tester.takeException(), isNull);
  });
  testWidgets('reference links and keyboard commands stay in the right surface; closing owner disposes it', (
    tester,
  ) async {
    final c = await openTabs(tester);
    final owner = c.read(workspaceProvider('demo-1').notifier);
    owner.openDocument('c2');
    owner.openStudyNoteReference('written');
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(ReferenceContent), matching: find.byKey(const ValueKey('note-source-quote'))),
    );
    await tester.pumpAndSettle();
    expect(c.read(workspaceProvider('demo-1')).activeDocumentId, 'c2');
    expect(c.read(workspaceProvider('demo-1')).tabs.open.length, 1);
    expect(c.read(workspaceProvider('demo-1')).tabs.current.reference!.id, 'c1');
    final reader = find.descendant(of: find.byType(ReferenceContent), matching: find.byType(ReaderPane));
    final nested = ProviderScope.containerOf(tester.element(reader));
    await tester.tapAt(tester.getTopLeft(reader) + const Offset(30, 160));
    await tester.pumpAndSettle();
    await pressWithControl(tester, LogicalKeyboardKey.keyF);
    expect(nested.read(workspaceProvider('demo-1')).findVisible, isTrue);
    expect(c.read(workspaceProvider('demo-1')).findVisible, isFalse);
    await pressWithControl(tester, LogicalKeyboardKey.keyW);
    expect(c.read(workspaceProvider('demo-1')).tabs.open, isEmpty);
    await tester.pumpAndSettle();
    expect(find.byType(ReferenceContent, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI entry is in tab row and redundant document title is removed', (tester) async {
    await openTabs(tester);
    final tabs = tester.getRect(find.byKey(const ValueKey('workspace-main-tabs')));
    final ai = tester.getRect(find.byKey(const ValueKey('toolbar-assistant')));
    expect(ai.center.dy, closeTo(tabs.center.dy, 1));
    expect(find.byKey(const ValueKey('workspace-tab-documentMap')), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-documents')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final size in [const Size(820, 1180), const Size(393, 852)]) {
    testWidgets('tab references close back to content at $size', (tester) async {
      final c = await openTabs(tester, size: size, touch: true);
      final owner = c.read(workspaceProvider('demo-1').notifier);
      owner.openStudyNote('written');
      await tester.pumpAndSettle();
      owner.revealNoteAnnotation(owner.content.annotations.first.id);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      owner.closePanel();
      await tester.pumpAndSettle();
      expect(find.byType(StudyNoteView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
