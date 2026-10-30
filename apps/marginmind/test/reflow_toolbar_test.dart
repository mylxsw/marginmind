import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/assistant/widgets/assistant_quick_actions.dart';
import 'package:marginmind/features/workspace/reader_translation.dart';
import 'package:marginmind/features/workspace/reflow_session.dart';
import 'package:marginmind/features/workspace/widgets/selection_translation.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';
import 'reader_translation_test.dart' show model;
import 'reflow_fixtures.dart';
import 'selection_translation_test.dart' show SelectionTestTranslator;

void main() {
  testWidgets('text toolbar copies, translates and passes source anchors to assistant', (tester) async {
    final repo = InMemoryStudySetContentRepository();
    final doc = await storeBook(repo);
    final translator = SelectionTestTranslator();
    final container = await pumpApp(
      tester,
      content: repo,
      overrides: [
        assistantDefaultModelProvider.overrideWithValue(model),
        paragraphTranslatorProvider.overrideWithValue((_) async => translator),
      ],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final workspace = container.read(workspaceProvider('demo-1').notifier);
    workspace.openDocument(doc.id);
    await tester.pumpAndSettle();
    final session = container.read(reflowSessionProvider(('demo-1', doc.id)));
    final chapter = session.book!.chapters.first;
    final start = chapter.canonicalText.indexOf('Source anchors');
    final anchor = chapter.anchor(start, start + 14, revision: doc.revision!);
    final selection = SourceSelection.text([anchor], viewportRect: const Rect.fromLTWH(60, 90, 120, 20));
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      },
    );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await workspace.onSourceSelectionCommitted(doc.id, selection);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Copy'));
    await tester.pumpAndSettle();
    expect(copied, anchor.quote);
    expect(container.read(workspaceProvider('demo-1')).pending, isNull);
    await workspace.onSourceSelectionCommitted(doc.id, selection);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('selection-translate')));
    await tester.pump(const Duration(milliseconds: 200));
    final popup = tester.widget<SelectionTranslation>(find.byType(SelectionTranslation));
    expect(popup.paragraph.textAnchor!.toJson(), anchor.toJson());
    expect(translator.source, anchor.quote);
    translator.pending.complete(const ParagraphTranslation('Stable source'));
    await tester.pumpAndSettle();
    expect(find.text('Stable source'), findsOneWidget);
    await tester.tapAt(const Offset(10, 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('selection-assistant')));
    await tester.pumpAndSettle();
    final assistant = tester.widget<AssistantQuickActions>(find.byType(AssistantQuickActions));
    expect(assistant.source!.target, isA<TextTarget>());
    expect((assistant.source!.target as TextTarget).textAnchors.single.toJson(), anchor.toJson());
    await tester.tapAt(const Offset(10, 300));
    await tester.pumpAndSettle();
    await settleHud(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('annotation hit targets and review grouping agree for every chapter anchor', (tester) async {
    final repo = InMemoryStudySetContentRepository();
    final doc = await storeBook(repo);
    final container = await pumpApp(tester, content: repo);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final workspace = container.read(workspaceProvider('demo-1').notifier);
    workspace.openDocument(doc.id);
    await tester.pumpAndSettle();
    final s = container.read(reflowSessionProvider(('demo-1', doc.id)));
    final c = s.book!.chapters.first;
    final start = c.canonicalText.indexOf('Source anchors');
    final anchor = c.anchor(start, start + 14, revision: doc.revision!);
    await workspace.highlightSource(doc.id, SourceSelection.text([anchor]), MMAnnotationColor.blue);
    final mark = workspace.content.annotations.single;
    // A previous revision can relocate its quote to a different UTF-16 offset.
    final relocated = Annotation(
      id: mark.id,
      documentId: doc.id,
      quote: mark.quote,
      textAnchors: [TextAnchor('main', 0, anchor.quote.length, anchor.quote, revision: 'previous')],
      colorIndex: mark.colorIndex,
      createdAt: mark.createdAt,
    );
    await repo.update('demo-1', (content) => content.copyWith(annotations: [relocated]));
    await tester.pumpAndSettle();
    final rect = s.layout!.boxes(anchor).first.rect;
    await tester.tapAt(tester.getTopLeft(find.byKey(const ValueKey('reflow-surface'))) + rect.center);
    await tester.pumpAndSettle();
    final pending = container.read(workspaceProvider('demo-1')).pending as PendingHighlight;
    expect(pending.annotationId, mark.id);
    expect(pending.viewportRect.size, rect.size, reason: 'Toolbar uses relocated geometry, not obsolete offsets');
    workspace.dismissPending();
    final broken = Annotation(
      id: 'broken',
      documentId: doc.id,
      quote: 'Unresolved cross-chapter quote',
      textAnchors: [
        anchor,
        const TextAnchor('removed', 0, 7, 'missing', revision: 'old'),
      ],
      colorIndex: 0,
      createdAt: DateTime(2026),
    );
    await repo.update('demo-1', (content) => content.copyWith(annotations: [...content.annotations, broken]));
    await tester.pumpAndSettle();
    workspace.showReaderPanel(ReaderPanelMode.annotations);
    await tester.pumpAndSettle();
    expect(find.textContaining('Needs Review'), findsWidgets);
    await tester.tap(find.text(broken.quote));
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider('demo-1')).pending, isNull);
    await tester.drag(find.byKey(const ValueKey('reflow-sidebar-resize')), const Offset(30, 0));
    await tester.pumpAndSettle();
    await workspace.deleteHighlight(broken.id);
    await tester.pumpAndSettle();
    expect(find.textContaining('Needs Review'), findsNothing);
    await settleHud(tester);
    expect(tester.takeException(), isNull);
  });
}
