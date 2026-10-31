import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/map_generation/map_generation_controller.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

void main() {
  for (final language in ['zh', 'en']) {
    testWidgets('blocked map edits explain the current generation stage ($language)', (tester) async {
      final container = await pumpApp(tester, prefs: {'settings.language': language});
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      final controller = container.read(mapGenerationControllerProvider('demo-1').notifier);
      final workspace = container.read(workspaceProvider('demo-1').notifier);
      final before = workspace.content;
      final running = language == 'zh'
          ? '正在生成内容，请等待完成，或点击“停止”'
          : 'Content is being generated. Wait for it to finish or click Stop.';
      final review = language == 'zh' ? '请先保留或放弃生成的脑图，再继续操作' : 'Keep or discard the generated map before continuing';
      final update = language == 'zh' ? '请先应用或放弃脑图更新，再继续操作' : 'Apply or discard the map update before continuing';

      for (final (phase, destination, message) in [
        (MapGenerationPhase.reading, MapGenerationDestination.branch, running),
        (MapGenerationPhase.streaming, MapGenerationDestination.branch, running),
        (MapGenerationPhase.review, MapGenerationDestination.branch, review),
        (MapGenerationPhase.stopped, MapGenerationDestination.branch, review),
        (MapGenerationPhase.diff, MapGenerationDestination.update, update),
        (MapGenerationPhase.stopped, MapGenerationDestination.update, update),
      ]) {
        controller.state = MapGenerationPreview(
          request: MapGenerationRequest(
            studySetId: 'demo-1',
            mapId: MindMap.defaultId,
            title: 'Draft map',
            sources: const [MapDocumentSelection(documentId: 'c1')],
            destination: destination,
            parentId: 'c3',
          ),
          baseRevision: 0,
          proposalId: 'preview',
          generation: MapGeneration(
            sources: [MapSource(documentId: 'c1', chapters: const [], fingerprint: 'fp', readThrough: 1)],
            organization: MapOrganization.chapter,
            depth: 3,
            generatedAt: testNow,
          ),
          phase: phase,
          lines: [MapLine(id: 'draft-1', kind: MapLineKind.add, parentId: 'ROOT', title: 'Draft topic')],
        );
        await tester.pump();
        tester.widget<MindMapCanvas>(find.byType(MindMapCanvas)).focusNode.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text(message), findsOneWidget, reason: '$phase / $destination');
        expect(find.byIcon(MMIcons.info), findsWidgets);
        expect(workspace.content.nodes.length, before.nodes.length);

        // Toolbar/controller actions must use the same state-specific message.
        workspace.beginEditing('c3');
        await tester.pump();
        expect(find.text(message), findsOneWidget);
        expect(container.read(workspaceProvider('demo-1')).editingCardId, isNull);
      }
      controller.discard();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
