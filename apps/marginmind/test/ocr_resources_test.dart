import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/document_resources.dart';
import 'package:marginmind/features/workspace/reader_ocr.dart';
import 'package:marginmind/features/workspace/widgets/reader_ocr_controls.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/shared/l10n.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import 'helpers.dart';
import 'reader_ocr_test.dart' show FakeOcr;

class OcrResources extends InMemoryStudySetContentRepository implements DocumentResourceRepository {
  OcrResources() : super({'demo-1': demoContent()});
  final changes = StreamController<DocumentResourceAvailability>.broadcast();
  int activeStreams = 0;
  DocumentResourceAvailability availability = DocumentResourceAvailability.missing;
  void change(DocumentResourceAvailability value) {
    availability = value;
    changes.add(value);
  }

  @override
  Stream<DocumentResourceAvailability> watchDocumentResources(String set, String doc) async* {
    activeStreams++;
    try {
      yield availability;
      yield* changes.stream;
    } finally {
      activeStreams--;
    }
  }
}

class GatedOcr extends FakeOcr {
  Completer<PdfOcrDocument>? inspection;
  @override
  Future<PdfOcrDocument> inspect(String source) {
    if (inspection case final gate?) {
      inspections++;
      return gate.future;
    }
    return super.inspect(source);
  }
}

Future<void> settleEvents() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late OcrResources repo;
  late GatedOcr service;
  late ProviderContainer container;
  late ReaderOcrSource source;
  setUp(() async {
    repo = OcrResources();
    service = GatedOcr();
    container = ProviderContainer(
      overrides: [
        ...await testOverrides(content: repo),
        pdfOcrServiceProvider.overrideWithValue(service),
      ],
    );
    source = documentOcrSource('demo-1', (await repo.load('demo-1')).document('c1')!, '/a.pdf');
    container.listen(readerOcrProvider(source), (_, _) {});
  });
  tearDown(() async {
    container.dispose();
    await repo.changes.close();
  });

  test('missing and changed bytes never reach inspection or recognition; download permits retry', () async {
    final controller = container.read(readerOcrProvider(source).notifier);
    await controller.inspect();
    expect(service.inspections, 0);
    expect(container.read(readerOcrProvider(source)).unavailable, DocumentResourceAvailability.missing);
    await expectLater(controller.requireAvailable(), throwsA(isA<DocumentResourcesUnavailable>()));
    await controller.recognize(1, 1, PdfOcrLanguage.english);
    expect(service.starts, 0);
    repo.change(DocumentResourceAvailability.ready);
    await settleEvents();
    await controller.inspect();
    expect(service.inspections, 1);
    expect(container.read(readerOcrProvider(source)).document, service.document);
    repo.change(DocumentResourceAvailability.changed);
    await settleEvents();
    await controller.inspect();
    expect(service.inspections, 1);
    expect(container.read(readerOcrProvider(source)).document, isNull);
  });

  test('same-path document replacement drops an in-flight inspection and isolates the next version', () async {
    repo.availability = DocumentResourceAvailability.ready;
    service.inspection = Completer();
    final controller = container.read(readerOcrProvider(source).notifier);
    final task = controller.inspect();
    await settleEvents();
    expect(service.inspections, 1);
    await repo.update(
      'demo-1',
      (c) =>
          c.copyWith(documents: [for (final d in c.documents) d.id == 'c1' ? d.copyWith(revision: 'replacement') : d]),
    );
    await settleEvents();
    service.inspection!.complete(service.document);
    await task;
    expect(container.read(readerOcrProvider(source)).document, isNull);
    await expectLater(controller.requireAvailable(), throwsA(isA<DocumentResourcesUnavailable>()));
    final next = documentOcrSource('demo-1', (await repo.load('demo-1')).document('c1')!, '/a.pdf');
    service.inspection = null;
    await container.read(readerOcrProvider(next).notifier).inspect();
    expect(container.read(readerOcrProvider(next)).document, service.document);
  });

  test('resource invalidation cancels and ignores late results without clearing a newer job', () async {
    repo.availability = DocumentResourceAvailability.ready;
    final provider = readerOcrProvider(source);
    final controller = container.read(provider.notifier);
    await controller.inspect();
    final oldResult = service.result;
    final old = controller.recognize(1, 1, PdfOcrLanguage.english);
    await settleEvents();
    final oldProgress = service.progress!;
    service.failCancel = true;
    repo.change(DocumentResourceAvailability.changed);
    await settleEvents();
    oldProgress(1, 1);
    expect(container.read(provider).document, isNull);
    expect(container.read(provider).running, isFalse);
    repo.change(DocumentResourceAvailability.ready);
    await settleEvents();
    await controller.inspect();
    service.result = Completer();
    service.failCancel = false;
    final next = controller.recognize(1, 1, PdfOcrLanguage.english);
    await settleEvents();
    oldResult.completeError(StateError('late obsolete failure'));
    await old;
    service.progress!(1, 1);
    expect(container.read(provider).done, 1);
    await controller.cancel();
    expect(service.cancelledId, isNotNull);
    service.result.complete((document: service.document, cancelled: true));
    await next;
    expect(container.read(provider).cancelled, isTrue);
    expect(container.read(provider).failed, isFalse);
  });

  test('late successful recognition cannot republish unavailable resources', () async {
    repo.availability = DocumentResourceAvailability.ready;
    final provider = readerOcrProvider(source);
    final controller = container.read(provider.notifier);
    await controller.inspect();
    final task = controller.recognize(1, 1, PdfOcrLanguage.english);
    await settleEvents();
    repo.change(DocumentResourceAvailability.missing);
    await settleEvents();
    expect(service.cancelledId, isNotNull);
    service.result.complete((document: service.document, cancelled: false));
    await task;
    expect(container.read(provider).unavailable, DocumentResourceAvailability.missing);
    expect(container.read(provider).document, isNull);
  });

  test('resource watcher errors discard cached OCR and disposal releases the subscription', () async {
    repo.availability = DocumentResourceAvailability.ready;
    final provider = readerOcrProvider(source);
    final controller = container.read(provider.notifier);
    await controller.inspect();
    expect(repo.changes.hasListener, isTrue);
    repo.changes.addError(StateError('resource unavailable'));
    await settleEvents();
    expect(container.read(provider).document, isNull);
    await expectLater(controller.requireAvailable(), throwsA(isA<DocumentResourcesUnavailable>()));
    container.dispose();
    await settleEvents();
    expect(repo.changes.hasListener, isFalse);
  });

  test('an unobserved operation stays guarded until completion then releases its watchers', () async {
    repo.change(DocumentResourceAvailability.ready);
    await settleEvents();
    final baseline = repo.activeStreams;
    service.inspection = Completer();
    final background = readerOcrProvider(('/another-source.pdf', source.$2));
    final task = container.read(background.notifier).inspect();
    await settleEvents();
    expect(service.inspections, 1);
    expect(repo.activeStreams, baseline + 1);
    service.inspection!.complete(service.document);
    await task;
    await settleEvents();
    expect(repo.activeStreams, baseline);
  });

  testWidgets('direct OCR entry explains missing resources without starting the service', (tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: MMTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () => showReaderOcrOptions(context, ref, 'demo-1', documentId: 'c1'),
                child: const Text('OCR'),
              ),
            ),
          ),
        ),
      ),
    );
    container.listen(workspaceProvider('demo-1'), (_, _) {});
    await container.read(contentProvider('demo-1').future);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OCR'));
    await tester.pumpAndSettle();
    expect(find.text('Download incomplete'), findsOneWidget);
    expect(find.text('Sync'), findsOneWidget);
    expect(service.inspections, 0);
    expect(service.starts, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
}
