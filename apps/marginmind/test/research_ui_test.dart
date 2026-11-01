import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/research/research_controller.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

const _claim = '一个明显随机的数字，竟能让估计相差将近一倍。';
const _docId = 'c1';
const _rect = PageRect(10, 100, 200, 88);
Future<({WorkspaceController workspace, ResearchPanelController panel})> _open(
  WidgetTester tester, {
  StudySetContent? content,
}) async {
  final container = await pumpApp(
    tester,
    content: InMemoryStudySetContentRepository({'demo-1': content ?? demoContent()}),
  );
  container.read(navigationProvider.notifier).openStudySet('demo-1');
  await tester.pumpAndSettle();
  return (
    workspace: container.read(workspaceProvider('demo-1').notifier),
    panel: container.read(researchPanelProvider('demo-1').notifier),
  );
}

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle();
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('each research attachment locates its own source in the main reader', (tester) async {
    final note = ResearchNote(
      id: 'multiple',
      title: 'Multiple sources',
      question: 'Why?',
      body: 'Answer',
      createdAt: testNow,
      updatedAt: testNow,
    );
    final data = demoContent().copyWith(
      researchNotes: [note],
      noteAttachments: [
        for (final (id, documentId, page) in [('first', 'c1', 2), ('second', 'c2', 3)])
          NoteAttachment(
            id: id,
            noteId: note.id,
            target: PdfTarget(
              documentId: documentId,
              pages: [
                AnnotationPage(page: page, rects: const [_rect]),
              ],
            ),
          ),
      ],
    );
    final app = await _open(tester, content: data);
    app.panel.showNote(note.id);
    await _settle(tester);
    final second = find.byKey(const ValueKey('place-second'));
    await _tap(tester, find.descendant(of: second, matching: find.widgetWithText(MMButton, 'Locate')));
    final state = ProviderScope.containerOf(tester.element(second)).read(workspaceProvider('demo-1'));
    expect(state.activeDocumentId, 'c2');
    expect(state.reveal!.page, 3);
    expect(state.reveal!.rects, [_rect]);
    expect(state.tabs.current.reference, isNull);
    await settleHud(tester);
  });

  testWidgets('PDF-only note opts into review without creating a visible card; undo restores opt-out', (tester) async {
    final app = await _open(tester);
    final now = DateTime(2026);
    await app.workspace.saveResearchNote(
      ResearchNote(
        id: 'review-note',
        title: 'Conclusion',
        question: 'Why?',
        body: 'Answer',
        createdAt: now,
        updatedAt: now,
      ),
      source: PdfTarget(
        documentId: _docId,
        pages: const [
          AnnotationPage(page: 24, rects: [_rect]),
        ],
        quote: _claim,
      ),
    );
    app.panel.showNote('review-note');
    await _settle(tester);
    final count = app.workspace.content.nodes.length;
    final toggle = find.byKey(const ValueKey('research-review-toggle'));
    expect(tester.widget<MMSwitch>(toggle).value, isFalse);
    await _tap(tester, toggle);
    await _settle(tester);
    expect(app.workspace.content.researchReviewEnabled('review-note'), isTrue);
    expect(app.workspace.content.nodes.length, count);
    await app.workspace.undo();
    await _settle(tester);
    expect(tester.widget<MMSwitch>(toggle).value, isFalse);
  });
}
