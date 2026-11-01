import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/assistant/assistant_scope.dart';
import 'package:marginmind/features/map_generation/map_updates.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

void main() {
  testWidgets('sidebar update dot stays clear when revisiting pages and still detects changed material', (
    tester,
  ) async {
    final base = demoContent();
    final before = base.copyWith(
      documents: [
        for (final d in base.documents)
          d.id == 'c1'
              ? Document(
                  id: d.id,
                  title: d.title,
                  fileName: d.fileName,
                  pageCount: 2,
                  lastPage: 2,
                  importedAt: d.importedAt,
                )
              : d,
      ],
    );
    final repo = InMemoryStudySetContentRepository({'demo-1': before});
    // The sidebar update dot is a Beta map generation feature.
    final container = await pumpApp(
      tester,
      content: repo,
      prefs: const {'settings.betaFeaturesEnabled': true},
      overrides: [assistantPageTextProvider.overrideWithValue((path, page) async => 'Page $page text')],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    // Use the real digest provider so reading-state invalidation is covered too.
    final sourceProvider = currentMapSourceProvider(('demo-1', 'c1'));
    final subscription = container.listen(sourceProvider, (_, _) {});
    addTearDown(subscription.close);
    await tester.pumpAndSettle();
    final source = container.read(sourceProvider).value;
    expect(source!.readThrough, 2);
    await repo.update(
      'demo-1',
      (c) => c.copyWith(
        maps: [
          for (final m in c.maps)
            m.copyWith(
              generation: MapGeneration(
                sources: [source],
                organization: MapOrganization.chapter,
                depth: 3,
                generatedAt: testNow,
              ),
            ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final updates = mapHasUpdatesProvider(('demo-1', before.maps.first.id));
    final row = find.byKey(ValueKey('sidebar-map-${before.maps.first.id}'));
    expect(container.read(updates), isFalse);
    expect(tester.widget<MMSidebarItem>(row).trailing, isNull);
    for (final page in [1, 2, 1]) {
      await repo.update(
        'demo-1',
        (c) => c.copyWith(documents: [for (final d in c.documents) d.id == 'c1' ? d.copyWith(lastPage: page) : d]),
      );
      await tester.pumpAndSettle();
      expect(container.read(updates), isFalse, reason: 'Revisiting page $page introduces no new material');
      expect(tester.widget<MMSidebarItem>(row).trailing, isNull);
    }
    await repo.update('demo-1', (c) => c.copyWith(annotations: const []));
    await tester.pumpAndSettle();
    expect(container.read(updates), isTrue);
    expect(tester.widget<MMSidebarItem>(row).trailing, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
