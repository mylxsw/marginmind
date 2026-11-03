import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/document_reader.dart';
import 'package:marginmind/features/workspace/document_resources.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';

import 'helpers.dart';

class ResourceRepository extends InMemoryStudySetContentRepository implements DocumentResourceRepository {
  ResourceRepository()
    : super({
        'demo-1': demoContent().copyWith(
          documents: [
            Document(
              id: 'c1',
              title: 'Cloud book',
              fileName: 'books/c1/v/manifest.json',
              contentManifest: 'books/c1/v/manifest.json',
              revision: 'v',
              layout: DocumentLayout.reflow,
              pageCount: 0,
              importedAt: testNow,
            ),
          ],
        ),
      });
  final changes = StreamController<DocumentResourceAvailability>.broadcast();
  int subscriptions = 0;
  @override
  Stream<DocumentResourceAvailability> watchDocumentResources(String set, String doc) async* {
    subscriptions++;
    yield DocumentResourceAvailability.missing;
    yield* changes.stream;
  }
}

void main() {
  testWidgets('reader waits for verified files and updates after an explicit download', (tester) async {
    final repo = ResourceRepository();
    final container = await pumpApp(
      tester,
      content: repo,
      overrides: [
        documentReaderBuilderProvider.overrideWithValue(
          (context, ref, set, doc) => const Text('Verified source reader'),
        ),
      ],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    expect(find.text('Not fully downloaded'), findsOneWidget);
    expect(find.text('Verified source reader'), findsNothing);
    expect(repo.subscriptions, 1);
    repo.changes.add(DocumentResourceAvailability.changed);
    await tester.pumpAndSettle();
    expect(find.textContaining('Local file differs'), findsOneWidget);
    repo.changes.add(DocumentResourceAvailability.ready);
    await tester.pumpAndSettle();
    expect(find.text('Verified source reader'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await repo.changes.close();
  });
  test('repositories without the optional port preserve existing reader behavior', () async {
    final container = ProviderContainer(overrides: await testOverrides());
    addTearDown(container.dispose);
    final provider = documentResourcesProvider(('demo-1', 'c1', null, 'demo.pdf', null, null));
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    expect(await container.read(provider.future), DocumentResourceAvailability.ready);
  });
}
