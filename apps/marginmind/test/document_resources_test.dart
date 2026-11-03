import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/document_reader.dart';
import 'package:marginmind/features/workspace/document_resources.dart';
import 'package:marginmind/features/workspace/reader_translation.dart';
import 'package:marginmind/features/workspace/reader_compare.dart';
import 'package:marginmind/features/workspace/widgets/full_translation_sheet.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/workspace/workspace_screen.dart';

import '../../../packages/mm_pdf/test/support/pdf_backend.dart';

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

class PdfResourceRepository extends InMemoryStudySetContentRepository implements DocumentResourceRepository {
  PdfResourceRepository() : super({'demo-1': demoContent()});
  final changes = StreamController<DocumentResourceAvailability>.broadcast();
  @override
  Stream<DocumentResourceAvailability> watchDocumentResources(String set, String doc) async* {
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
  testWidgets('full translation shows a download action instead of suggesting OCR for missing bytes', (tester) async {
    final repo = PdfResourceRepository();
    final container = await pumpApp(tester, content: repo);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    unawaited(
      showFullTranslationSheet(tester.element(find.byType(WorkspaceScreen)), studySetId: 'demo-1', documentId: 'c1'),
    );
    await tester.pumpAndSettle();
    final sheet = find.byType(FullTranslationSheet);
    expect(sheet, findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('Not fully downloaded')), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('Sync')), findsOneWidget);
    repo.changes.add(DocumentResourceAvailability.changed);
    await tester.pumpAndSettle();
    expect(find.descendant(of: sheet, matching: find.textContaining('Local file differs')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await repo.changes.close();
  });

  test('translation extraction waits for resource availability and rebuilds after download', () async {
    installTestPdfBackend();
    final repo = PdfResourceRepository();
    final container = ProviderContainer(overrides: await testOverrides(content: repo, renderPdf: true));
    container.listen(workspaceProvider('demo-1'), (_, _) {});
    await container.read(contentProvider('demo-1').future);
    final provider = translationParagraphsProvider(('demo-1', 'c1'));
    final subscription = container.listen(provider, (_, _) {});
    expect((await container.read(compareDocumentInfoProvider(('demo-1', 'c1')).future)).hasText, isNull);
    await expectLater(
      container.read(provider.future).timeout(const Duration(seconds: 5)),
      throwsA(isA<DocumentResourcesUnavailable>()),
    );
    repo.changes.add(DocumentResourceAvailability.ready);
    await Future<void>.delayed(Duration.zero);
    expect(await container.read(provider.future).timeout(const Duration(seconds: 5)), isNotEmpty);
    repo.changes.add(DocumentResourceAvailability.changed);
    await Future<void>.delayed(Duration.zero);
    await expectLater(
      container.read(provider.future).timeout(const Duration(seconds: 5)),
      throwsA(isA<DocumentResourcesUnavailable>()),
    );
    subscription.close();
    container.dispose();
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
