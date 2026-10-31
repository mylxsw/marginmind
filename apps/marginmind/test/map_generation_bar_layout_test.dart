import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/map_generation/map_generation_controller.dart';
import 'package:marginmind/features/map_generation/widgets/map_generation_bar.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

MapGenerationPreview preview({
  MapGenerationPhase phase = MapGenerationPhase.review,
  bool multipleDocuments = false,
  bool chapterFailure = false,
}) => MapGenerationPreview(
  request: MapGenerationRequest(
    studySetId: 'demo-1',
    mapId: 'draft-map',
    title: 'Sample chapter: The forgetting curve and spaced repetition',
    sources: [
      const MapDocumentSelection(documentId: 'c1'),
      if (multipleDocuments) const MapDocumentSelection(documentId: 'c2'),
    ],
  ),
  baseRevision: 0,
  proposalId: 'preview',
  generation: MapGeneration(
    sources: [MapSource(documentId: 'c1', fingerprint: 'fp', readThrough: 1)],
    organization: MapOrganization.chapter,
    depth: 3,
    generatedAt: testNow,
  ),
  phase: phase,
  lines: phase == MapGenerationPhase.failed
      ? []
      : [MapLine(id: 'draft-1', kind: MapLineKind.add, parentId: 'ROOT', title: '遗忘曲线')],
  skeletons: const [
    MapSkeletonItem(id: 'chapter', title: 'A long chapter title about memory and spaced repetition', isCurrent: true),
  ],
  chapterFailures: chapterFailure ? {'chapter': const ResearchFailure(ResearchFailureKind.timeout)} : {},
  failure: phase == MapGenerationPhase.failed ? const ResearchFailure(ResearchFailureKind.network) : null,
);

Future<ProviderContainer> pumpBar(
  WidgetTester tester, {
  required MapGenerationPreview state,
  required double width,
  String language = 'zh',
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: await testOverrides(),
      child: MaterialApp(
        theme: MMTheme.dark(),
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              key: const ValueKey('bar-bounds'),
              width: width,
              child: Consumer(
                builder: (context, ref, _) {
                  ref.watch(workspaceProvider('demo-1'));
                  return const MapGenerationBar(studySetId: 'demo-1');
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(tester.element(find.byType(MapGenerationBar)));
  container.read(mapGenerationControllerProvider('demo-1').notifier).state = state;
  // Reading and streaming have an ongoing progress animation.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return container;
}

void expectVisibleButtons(WidgetTester tester, List<String> names) {
  final bounds = tester.getRect(find.byKey(const ValueKey('bar-bounds')));
  for (final name in names) {
    final button = find.byKey(ValueKey('map-generation-$name-button'));
    expect(button.hitTestable(), findsOneWidget, reason: '$name must be directly clickable');
    final rect = tester.getRect(button);
    expect(rect.left, greaterThanOrEqualTo(bounds.left));
    expect(rect.right, lessThanOrEqualTo(bounds.right));
    expect(rect.top, greaterThanOrEqualTo(bounds.top));
    expect(rect.bottom, lessThanOrEqualTo(bounds.bottom));
    final label = find.descendant(
      of: find.descendant(of: button, matching: find.byType(Text)),
      matching: find.byType(RichText),
    );
    expect(tester.renderObject<RenderParagraph>(label).didExceedMaxLines, isFalse, reason: '$name label must fit');
  }
  expect(tester.takeException(), isNull);
}

void main() {
  for (final language in ['zh', 'en']) {
    for (final width in [640.0, 480.0, 320.0, 240.0]) {
      testWidgets('review buttons fit a $width pane ($language)', (tester) async {
        final state = preview();
        final container = await pumpBar(tester, state: state, width: width, language: language);
        expectVisibleButtons(tester, ['regenerate', 'adjust', 'discard', 'keep']);
        final bar = find.byType(MapGenerationBar);
        expect(find.descendant(of: bar, matching: find.text(state.request.title)), findsNothing);
        expect(find.descendant(of: bar, matching: find.byIcon(MMIcons.generateMap)), findsNothing);
        final l = AppLocalizations.of(tester.element(bar));
        expect(find.text(l.mapIdeaKeptCount(1, 1)), findsNothing);
        expect(find.descendant(of: bar, matching: find.byType(Scrollable)), findsNothing);

        await tester.tap(find.byKey(const ValueKey('map-generation-discard-button')));
        await tester.pumpAndSettle();
        expect(container.read(mapGenerationControllerProvider('demo-1')), isNull);
      });
    }
  }

  for (final phase in [
    MapGenerationPhase.reading,
    MapGenerationPhase.streaming,
    MapGenerationPhase.failed,
    MapGenerationPhase.stopped,
  ]) {
    testWidgets('$phase controls fit a narrow pane', (tester) async {
      await pumpBar(tester, state: preview(phase: phase), width: 240);
      expectVisibleButtons(tester, switch (phase) {
        MapGenerationPhase.reading || MapGenerationPhase.streaming => ['stop'],
        MapGenerationPhase.failed => ['error-details', 'failed-retry', 'failed-close'],
        _ => ['regenerate', 'adjust', 'discard', 'keep'],
      });
    });
  }

  testWidgets('chapter retry and document legend fit with review actions', (tester) async {
    await pumpBar(tester, state: preview(multipleDocuments: true, chapterFailure: true), width: 240);
    expectVisibleButtons(tester, ['retry-chapter', 'error-details', 'regenerate', 'adjust', 'discard', 'keep']);
    expect(find.text('学习的底层逻辑'), findsOneWidget);
    expect(find.text('论文：检索练习效应'), findsOneWidget);
  });
}
