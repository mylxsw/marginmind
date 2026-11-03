import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/reflow_session.dart';
import 'package:marginmind/features/workspace/widgets/reading_continuations.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';
import 'reflow_fixtures.dart';

class ReadingRepository extends InMemoryStudySetContentRepository implements ReadingContinuationRepository {
  ReadingRepository() : super({'demo-1': demoContent()});
  ReadingContinuations status = ReadingContinuations();
  Object? loadError, actionError;
  Completer<void>? gate;
  final calls = <(String, String, String, String)>[];
  int observedPage = 0;
  @override
  Future<ReadingContinuations> readingContinuations(String id) async => status;
  @override
  Stream<ReadingContinuations> watchReadingContinuations(String id) async* {
    if (loadError != null) throw loadError!;
    yield status;
  }

  @override
  Future<ReadingPosition> prepareReadingContinuation(
    String id,
    String device,
    String document, {
    required String remoteRevision,
    required String localToken,
  }) async {
    calls.add((device, document, remoteRevision, localToken));
    observedPage = (await load(id)).document(document)?.lastPage ?? 0;
    if (gate != null) await gate!.future;
    if (actionError != null) throw actionError!;
    return status.items.firstWhere((c) => c.documentId == document).position;
  }
}

ReadingContinuation choice({
  String document = 'c1',
  ReadingPosition? position,
  ReadingContinuationAvailability availability = ReadingContinuationAvailability.ready,
}) => ReadingContinuation(
  deviceId: 'private-device-id',
  documentId: document,
  title: 'Reading book',
  remoteRevision: 'observed-remote',
  localToken: 'observed-local',
  position: position ?? PdfPosition(12),
  readAt: DateTime.utc(2026),
  availability: availability,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ReadingRepository repo;
  setUp(() {
    repo = ReadingRepository();
    repo.status = ReadingContinuations(enabled: true, items: [choice()]);
  });

  Future<ProviderContainer> controllerContainer() async {
    final container = ProviderContainer(overrides: await testOverrides(content: repo));
    addTearDown(container.dispose);
    container.listen(workspaceProvider('demo-1'), (_, _) {});
    await container.read(contentProvider('demo-1').future);
    return container;
  }

  test('explicit PDF continuation navigates only after validation and does not pretend to have read', () async {
    final container = await controllerContainer();
    final controller = container.read(workspaceProvider('demo-1').notifier);
    final before = (await repo.load('demo-1')).document('c1')!.lastPage;
    repo.gate = Completer<void>();
    final action = controller.continueReading(choice());
    await Future<void>.delayed(Duration.zero);
    expect(container.read(workspaceProvider('demo-1')).reveal, isNull);
    repo.gate!.complete();
    await action;
    final state = container.read(workspaceProvider('demo-1'));
    expect(state.activeDocumentId, 'c1');
    expect(state.reveal!.page, 12);
    expect((await repo.load('demo-1')).document('c1')!.lastPage, before);
    expect(repo.calls.single, ('private-device-id', 'c1', 'observed-remote', 'observed-local'));
  });

  test('pending local PDF progress is flushed before validating an observed continuation', () async {
    final container = await controllerContainer();
    final controller = container.read(workspaceProvider('demo-1').notifier);
    controller.recordPage('c1', 7);
    repo.actionError = const ContentSyncActionException(ContentSyncActionFailure.stale);
    await expectLater(controller.continueReading(choice()), throwsA(isA<ContentSyncActionException>()));
    expect(repo.observedPage, 7);
    expect(container.read(workspaceProvider('demo-1')).reveal, isNull);
  });

  test('new navigation or visible page during validation cannot be overwritten by completion', () async {
    final container = await controllerContainer();
    final controller = container.read(workspaceProvider('demo-1').notifier);
    for (final changePage in [false, true]) {
      repo.gate = Completer<void>();
      final action = controller.continueReading(choice());
      final assertion = expectLater(action, throwsA(isA<ContentSyncActionException>()));
      await Future<void>.delayed(Duration.zero);
      if (changePage) {
        controller.recordPage('c1', 8);
      } else {
        controller.openDocument('c2');
      }
      repo.gate!.complete();
      await assertion;
    }
    expect(container.read(workspaceProvider('demo-1')).reveal, isNull);
  });

  test('invalid reflow anchors fail before preparing a navigation', () async {
    final doc = await storeBook(repo);
    final container = await controllerContainer();
    final controller = container.read(workspaceProvider('demo-1').notifier);
    for (final position in [
      TextReadingPosition(revision: doc.revision!, chapterId: 'absent', offset: 0),
      TextReadingPosition(revision: 'old', chapterId: 'main', offset: 0),
      TextReadingPosition(revision: doc.revision!, chapterId: 'main', offset: 999999),
    ]) {
      await expectLater(
        controller.continueReading(choice(document: doc.id, position: position)),
        throwsA(isA<ContentSyncActionException>()),
      );
    }
    expect(repo.calls, isEmpty);
  });

  test('closing the selector cancels late navigation without disposing the workspace', () async {
    final container = await controllerContainer();
    final controller = container.read(workspaceProvider('demo-1').notifier);
    repo.gate = Completer<void>();
    var closed = false;
    final action = controller.continueReading(choice(), cancelled: () => closed);
    await Future<void>.delayed(Duration.zero);
    closed = true;
    repo.gate!.complete();
    await action;
    expect(container.read(workspaceProvider('demo-1')).reveal, isNull);
  });

  test('text scrolling queued during validation wins over the delayed continuation', () async {
    final doc = await storeBook(repo);
    final container = await controllerContainer();
    final controller = container.read(workspaceProvider('demo-1').notifier);
    final remote = TextReadingPosition(revision: doc.revision!, chapterId: 'main', offset: 100);
    repo.status = ReadingContinuations(
      enabled: true,
      items: [choice(document: doc.id, position: remote)],
    );
    repo.gate = Completer<void>();
    final action = controller.continueReading(repo.status.items.single);
    final assertion = expectLater(action, throwsA(isA<ContentSyncActionException>()));
    await Future<void>.delayed(Duration.zero);
    final local = TextReadingPosition(revision: doc.revision!, chapterId: 'main', offset: 300);
    final saving = controller.setReadingPosition(doc.id, local);
    repo.gate!.complete();
    await assertion;
    await saving;
    expect(container.read(workspaceProvider('demo-1')).reveal, isNull);
    expect((await repo.load('demo-1')).document(doc.id)!.readingPosition!.toJson(), local.toJson());
  });

  testWidgets('reflow continuation reaches its canonical position and then records local reading', (tester) async {
    final doc = await storeBook(repo);
    final position = TextReadingPosition(revision: doc.revision!, chapterId: 'main', offset: 200);
    final c = choice(document: doc.id, position: position);
    repo.status = ReadingContinuations(enabled: true, items: [c]);
    final container = await pumpApp(tester, content: repo);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final controller = container.read(workspaceProvider('demo-1').notifier);
    await controller.continueReading(c);
    await tester.pumpAndSettle();
    final session = container.read(reflowSessionProvider(('demo-1', doc.id)));
    expect(session.position!.toJson(), position.toJson());
    expect((await repo.load('demo-1')).document(doc.id)!.readingPosition!.toJson(), position.toJson());
    expect(tester.takeException(), isNull);
  });

  Future<void> pump(WidgetTester tester, {String locale = 'en', bool optional = true}) async {
    tester.view.physicalSize = const Size(360, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: await testOverrides(content: optional ? repo : InMemoryStudySetContentRepository()),
        child: MaterialApp(
          locale: Locale(locale),
          theme: MMTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const SingleChildScrollView(child: ReadingContinuationsSection(studySetId: 'demo-1')),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  final button = find.byKey(const ValueKey('reading-continue-private-device-id-c1'));

  testWidgets('human reading summary exposes no identities and successful choice closes the sheet', (tester) async {
    await pump(tester);
    expect(find.text('Reading book'), findsOneWidget);
    expect(find.text('Page 12'), findsOneWidget);
    expect(find.textContaining('private-device-id'), findsNothing);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(repo.calls, hasLength(1));
    expect(find.byType(ReadingContinuationsSection), findsNothing);
  });

  for (final failure in [
    ContentSyncActionFailure.stale,
    ContentSyncActionFailure.editing,
    ContentSyncActionFailure.invalidCandidate,
    null,
  ]) {
    testWidgets('failed continuation $failure retains the sheet and retries', (tester) async {
      repo.actionError = failure == null ? StateError('disk') : ContentSyncActionException(failure);
      await pump(tester);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reading-continuation-error')), findsOneWidget);
      repo.actionError = null;
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(repo.calls, hasLength(2));
      expect(find.byType(ReadingContinuationsSection), findsNothing);
    });
  }

  testWidgets('editing and unavailable or changed documents disable continuation in narrow Chinese UI', (tester) async {
    for (final availability in ReadingContinuationAvailability.values) {
      repo.status = ReadingContinuations(
        enabled: true,
        editing: availability == ReadingContinuationAvailability.ready,
        items: [choice(availability: availability)],
      );
      await pump(tester, locale: 'zh');
      expect(tester.widget<MMButton>(button).onPressed, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('loading failures retry and optional local repositories stay quiet', (tester) async {
    repo.loadError = StateError('load');
    await pump(tester);
    expect(find.text('Retry'), findsOneWidget);
    repo.loadError = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(button, findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await pump(tester, optional: false);
    expect(button, findsNothing);
  });

  testWidgets('busy action is not duplicated and completing after closing is safe', (tester) async {
    repo.gate = Completer<void>();
    await pump(tester);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(tester.widget<MMButton>(button).onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
    repo.gate!.complete();
    await tester.pumpAndSettle();
    expect(repo.calls, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
