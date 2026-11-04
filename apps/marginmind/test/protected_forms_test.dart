import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/reader_margin.dart';
import 'package:marginmind/features/workspace/widgets/notices.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/shared/l10n.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import 'content_input_test.dart' show InputRepository;
import 'helpers.dart';

class FormRepository extends InputRepository {
  Completer<void>? writing, entered;
  @override
  Future<StudySetContent> update(String id, StudySetContent Function(StudySetContent) change) async {
    if (entered != null && !entered!.isCompleted) entered!.complete();
    await writing?.future;
    return super.update(id, change);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<ProviderContainer> host(WidgetTester tester, InputRepository repository) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: await testOverrides(content: repository),
        child: MaterialApp(
          theme: MMTheme.light(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Row(
                children: [
                  TextButton(
                    onPressed: () => showCardTagsSheet(context, ref, 'demo-1', 'c3'),
                    child: const Text('Tags'),
                  ),
                  TextButton(
                    onPressed: () => showMapRenameSheet(context, ref, 'demo-1', MindMap.defaultId),
                    child: const Text('Map'),
                  ),
                  TextButton(
                    onPressed: () => showContentRenameSheet(
                      context,
                      ref,
                      'demo-1',
                      title: 'Rename document',
                      paths: [
                        ['documents', 'c1'],
                      ],
                      read: (c) => c.document('c1')?.title,
                      save: (value) => ref.read(workspaceProvider('demo-1').notifier).renameDocument('c1', value),
                    ),
                    child: const Text('Rename'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    container.listen(workspaceProvider('demo-1'), (_, _) {});
    await container.read(contentProvider('demo-1').future);
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('rename waits for repository barrier, reads latest title, and keeps failed input', (tester) async {
    final repository = InputRepository(), barrier = Completer<void>();
    await host(tester, repository);
    repository.barrier = barrier.future;
    await tester.tap(find.text('Rename'));
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    await repository.update(
      'demo-1',
      (c) => c.copyWith(documents: [for (final d in c.documents) d.id == 'c1' ? d.copyWith(title: 'Latest title') : d]),
    );
    barrier.complete();
    await tester.pumpAndSettle();
    expect(find.text('Latest title'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'My title');
    repository.failNextWrite = true;
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('My title'), findsOneWidget);
    expect(repository.leases.single.releases, 0);
    expect((await repository.load('demo-1')).document('c1')!.title, 'Latest title');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((await repository.load('demo-1')).document('c1')!.title, 'My title');
    expect(repository.leases.single.releases, 1);
  });

  testWidgets('map rename retains the localized default and protects the observed map', (tester) async {
    final repository = InputRepository();
    await repository.update('demo-1', (c) => c.copyWith(maps: [MindMap.main]));
    await host(tester, repository);
    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();
    final expected = AppLocalizations.of(tester.element(find.byType(TextField))).mainMap;
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, expected);
    expect(repository.leases.single.paths, [
      ['maps', MindMap.defaultId],
    ]);
    await tester.enterText(find.byType(TextField), 'My map');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((await repository.load('demo-1')).map(MindMap.defaultId)!.title, 'My map');
    expect(repository.leases.single.releases, 1);
  });

  testWidgets('a document deleted during opening never gets a stale rename form', (tester) async {
    final repository = InputRepository(), barrier = Completer<void>();
    await host(tester, repository);
    repository.barrier = barrier.future;
    await tester.tap(find.text('Rename'));
    await tester.pump();
    await repository.update(
      'demo-1',
      (c) => c.copyWith(
        documents: [
          for (final d in c.documents)
            if (d.id != 'c1') d,
        ],
      ),
    );
    barrier.complete();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(repository.leases.single.releases, 1);
    expect((await repository.load('demo-1')).document('c1'), isNull);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('tags retain failed edits, retry once, and cancel without persistence', (tester) async {
    final repository = InputRepository();
    await host(tester, repository);
    await tester.tap(find.text('Tags'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'new-tag');
    repository.failNextWrite = true;
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('new-tag'), findsOneWidget);
    expect((await repository.load('demo-1')).card('c3')!.tags, isNot(contains('new-tag')));
    expect(repository.leases.single.releases, 0);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((await repository.load('demo-1')).card('c3')!.tags, contains('new-tag'));
    expect(repository.leases.single.releases, 1);
    await tester.tap(find.text('Tags'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'cancelled-tag');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect((await repository.load('demo-1')).card('c3')!.tags, isNot(contains('cancelled-tag')));
    expect(repository.leases.last.releases, 1);
  });

  testWidgets('dismissal while saving retains lease until the outstanding write finishes', (tester) async {
    final repository = FormRepository();
    await host(tester, repository);
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Saved after dismissal');
    repository.writing = Completer<void>();
    repository.entered = Completer<void>();
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(repository.entered!.isCompleted, true);
    Navigator.of(tester.element(find.byType(TextField))).pop();
    await tester.pumpAndSettle();
    expect(repository.leases.single.releases, 0);
    repository.writing!.complete();
    await tester.pumpAndSettle();
    expect(repository.leases.single.releases, 1);
    expect((await repository.load('demo-1')).document('c1')!.title, 'Saved after dismissal');
    expect(tester.takeException(), isNull);
  });

  test('margin deletion and focus completion share the same protected write', () async {
    final repository = FormRepository();
    final note = MarginNote(
      id: 'margin',
      documentId: 'c1',
      page: 1,
      lineY: 500,
      text: 'Before',
      colorIndex: 0,
      createdAt: testNow,
      updatedAt: testNow,
    );
    await repository.update('demo-1', (c) => c.copyWith(marginNotes: [note]));
    final container = ProviderContainer(overrides: await testOverrides(content: repository));
    addTearDown(container.dispose);
    container.listen(workspaceProvider('demo-1'), (_, _) {});
    container.listen(readerMarginProvider('demo-1'), (_, _) {});
    await container.read(contentProvider('demo-1').future);
    final margin = container.read(readerMarginProvider('demo-1').notifier);
    await margin.start('c1', existing: note);
    repository.writing = Completer<void>();
    repository.entered = Completer<void>();
    final deleting = margin.delete(note);
    await repository.entered!.future;
    final finishing = margin.finish();
    expect(repository.leases.single.releases, 0);
    repository.writing!.complete();
    await deleting;
    expect(await finishing, true);
    expect((await repository.load('demo-1')).marginNotes, isEmpty);
    expect(repository.leases.single.releases, 1);
    expect(container.read(readerMarginProvider('demo-1')).draft, isNull);
  });

  test('margin starts only once, rereads after barrier, and retains lease on failed save', () async {
    final repository = InputRepository();
    await repository.update(
      'demo-1',
      (c) => c.copyWith(
        marginNotes: [
          MarginNote(
            id: 'margin',
            documentId: 'c1',
            page: 1,
            lineY: 500,
            text: 'Before',
            colorIndex: 0,
            createdAt: testNow,
            updatedAt: testNow,
          ),
        ],
      ),
    );
    final container = ProviderContainer(overrides: await testOverrides(content: repository));
    addTearDown(container.dispose);
    container.listen(workspaceProvider('demo-1'), (_, _) {});
    container.listen(readerMarginProvider('demo-1'), (_, _) {});
    await container.read(contentProvider('demo-1').future);
    final margin = container.read(readerMarginProvider('demo-1').notifier);
    final old = (await repository.load('demo-1')).marginNotes.single;
    final barrier = Completer<void>();
    repository.barrier = barrier.future;
    final start = margin.start('c1', existing: old);
    await Future<void>.delayed(Duration.zero);
    await margin.start('c1', page: 1, lineY: 400);
    await repository.update('demo-1', (c) => c.copyWith(marginNotes: [old.copyWith(text: 'Latest')]));
    barrier.complete();
    await start;
    expect(container.read(readerMarginProvider('demo-1')).draft!.text, 'Latest');
    expect(repository.leases, hasLength(1));
    margin.text('Local');
    repository.failNextWrite = true;
    expect(await margin.finish(), false);
    expect(repository.leases.single.releases, 0);
    expect(container.read(readerMarginProvider('demo-1')).draft!.text, 'Local');
    expect(await margin.finish(), true);
    expect(repository.leases.single.releases, 1);
  });
}
