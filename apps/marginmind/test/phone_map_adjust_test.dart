import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart' show touchPlatformProvider, phoneProvider;
import 'package:marginmind/features/map_generation/map_generation_controller.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_core/testing.dart' show FakeMapGenerator;

import 'map_generation_ui_test.dart' show openWorkspace, runGeneration;

void main() {
  testWidgets('phone adjustment uses the shared sheet and cancellation does not regenerate', (tester) async {
    final fake = FakeMapGenerator(
      chapters: {
        'c1-all': ['{"k":"point","id":"p1","title":"Point"}'],
      },
      generation: ['{"ref":"t1","parent":"ROOT","title":"Topic"}'],
    );
    final container = await openWorkspace(
      tester,
      overrides: [
        touchPlatformProvider.overrideWithValue(true),
        phoneProvider.overrideWithValue(true),
        mapGeneratorProvider.overrideWithValue(() async => fake),
      ],
    );
    tester.view.physicalSize = const Size(390, 844);
    container.read(workspaceProvider('demo-1').notifier).setLayout(MMSplitMode.secondary);
    await tester.pumpAndSettle();
    final owner = container.read(mapGenerationControllerProvider('demo-1').notifier);
    await runGeneration(
      tester,
      () => owner.start(
        const MapGenerationRequest(
          studySetId: 'demo-1',
          mapId: 'adjust-phone',
          title: 'Adjustment',
          sources: [MapDocumentSelection(documentId: 'c1')],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('map-generation-adjust-button')));
    await tester.pumpAndSettle();
    expect(container.read(mapGenerationControllerProvider('demo-1'))?.phase, MapGenerationPhase.review);
    final sheet = find.byKey(const ValueKey('mm-bottom-sheet'));
    expect(sheet, findsOneWidget);
    expect(tester.getRect(sheet).left, greaterThan(0));
    await tester.enterText(find.byKey(const ValueKey('map-adjust-instructions')), 'Keep as a draft');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    expect(container.read(mapGenerationControllerProvider('demo-1'))?.round, 0);
    await tester.tap(find.byKey(const ValueKey('map-generation-adjust-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('map-adjust-instructions')), 'Regenerate with more detail');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    final submit = find.byKey(const ValueKey('map-adjust-regenerate-button'));
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    expect(submit.hitTestable(), findsOneWidget);
    expect(tester.getRect(submit).bottom, lessThanOrEqualTo(544));
    fake.generation
      ..clear()
      ..add('{"ref":"t2","parent":"ROOT","title":"Updated"}');
    await tester.tap(submit);
    for (
      var i = 0;
      i < 100 && container.read(mapGenerationControllerProvider('demo-1'))?.phase != MapGenerationPhase.review;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    expect(container.read(mapGenerationControllerProvider('demo-1'))?.round, 1);
    expect(find.text('Updated'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android}));
}
