import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';
import 'study_notes_ui_test.dart' show noteFixture;

void main() {
  late ProviderContainer container;
  late WorkspaceController owner;
  WorkspaceState state() => container.read(workspaceProvider('demo-1'));

  setUp(() async {
    container = ProviderContainer(
      overrides: await testOverrides(content: InMemoryStudySetContentRepository({'demo-1': noteFixture()})),
    );
    container.listen(workspaceProvider('demo-1'), (_, _) {});
    await container.read(contentProvider('demo-1').future);
    owner = container.read(workspaceProvider('demo-1').notifier);
  });
  tearDown(() => container.dispose());

  for (final tab in [
    WorkspaceTab.documents,
    WorkspaceTab.vocabulary,
    WorkspaceTab.review,
    WorkspaceTab.statistics,
    const WorkspaceTab(WorkspaceTabKind.note, noteId: 'written'),
  ]) {
    for (final kind in ['pdf', 'text', 'node']) {
      test('$kind source jump from ${tab.id} activates the main content without opening a companion', () async {
        owner.activateTab(tab);
        owner.setLayout(kind == 'node' ? MMSplitMode.primary : MMSplitMode.secondary);
        final card = owner.content.cards.first;
        final anchor = SourceAnchor(
          target: switch (kind) {
            'pdf' => PdfTarget(
              documentId: 'c1',
              pages: const [AnnotationPage(page: 24, rects: [])],
            ),
            'text' => TextTarget(
              documentId: 'c1',
              textAnchors: const [TextAnchor('main', 0, 4, 'text', revision: 'test')],
            ),
            _ => CardTarget(cardId: card.id),
          },
        );
        expect(await owner.revealAnchor(anchor), isTrue);
        expect(state().tabs.active, WorkspaceTab.documents);
        expect(state().tabs.current.reference, isNull);
        expect(state().activeNoteId, isNull);
        if (kind == 'node') {
          expect(state().selectedCardId, card.id);
          expect(state().layout, isNot(MMSplitMode.primary));
          expect(state().locateCardTick, greaterThan(0));
        } else {
          expect(state().activeDocumentId, 'c1');
          expect(state().reveal!.documentId, 'c1');
          expect(state().layout, isNot(MMSplitMode.secondary));
        }
      });
    }
  }

  test('research card links restore their owning map from another tab and map', () async {
    await owner.addMap('Research map');
    final mapId = state().activeMapId;
    final notice = await owner.saveResearchNote(
      ResearchNote(
        id: 'research-jump',
        title: 'Finding',
        question: 'Why?',
        body: 'Answer',
        createdAt: testNow,
        updatedAt: testNow,
      ),
      toMap: true,
    );
    await owner.selectMap(MindMap.defaultId);
    owner.openStudyNote('written');
    await owner.locateNoteCard('research-jump');
    expect(state().tabs.active, WorkspaceTab.documents);
    expect(state().activeMapId, mapId);
    expect(state().selectedCardId, notice!.cardId);
    expect(state().tabs.current.reference, isNull);
    expect(state().layout, isNot(MMSplitMode.primary));
  });

  test('explicit companion links retain the owning note and main reader', () async {
    owner.openDocument('c2');
    owner.openStudyNote('written');
    final anchor = SourceAnchor(
      target: PdfTarget(
        documentId: 'c1',
        pages: const [AnnotationPage(page: 24, rects: [])],
      ),
    );
    expect(await owner.openAnchorReference(anchor), isTrue);
    expect(state().activeNoteId, 'written');
    expect(state().activeDocumentId, 'c2');
    expect(state().tabs.current.reference!.anchor, same(anchor));
    expect(state().reveal, isNull);
  });

  test('missing jump targets leave the current tab and companion untouched', () async {
    owner.openStudyNote('written');
    owner.openDocumentReference('c2');
    final before = state();
    for (final target in [
      const CardTarget(cardId: 'missing'),
      PdfTarget(
        documentId: 'missing',
        pages: const [AnnotationPage(page: 1, rects: [])],
      ),
      TextTarget(
        documentId: 'missing',
        textAnchors: const [TextAnchor('main', 0, 4, 'text', revision: 'test')],
      ),
    ]) {
      expect(await owner.revealAnchor(SourceAnchor(target: target)), isFalse);
      expect(state(), same(before));
    }
  });
}
