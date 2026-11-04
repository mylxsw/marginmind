import 'dart:async';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/research/widgets/research_note_view.dart';
import 'package:marginmind/features/study_notes/note_view.dart';
import 'package:marginmind/shared/content_input.dart';
import 'package:marginmind/shared/note_text.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/app_commands.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';

import 'helpers.dart';
import 'immediate_gestures_test.dart' show bare;
import 'study_notes_ui_test.dart' show noteFixture;

class InputRepository extends InMemoryStudySetContentRepository implements ContentEditRepository {
  InputRepository() : super({'demo-1': demoContent()});
  final leases = <InputLease>[];
  Future<void> barrier = Future.value();
  bool failNextWrite = false;
  @override
  Future<StudySetContent> update(String id, StudySetContent Function(StudySetContent) change) {
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('disk full');
    }
    return super.update(id, change);
  }

  @override
  ContentEditLease protectContent(String id, List<List<String>> paths) {
    final lease = InputLease(barrier, paths);
    leases.add(lease);
    return lease;
  }

  @override
  Future<void> beginContentTransaction(String id) async {}
  @override
  Future<void> endContentTransaction(String id) async {}
}

class InputLease implements ContentEditLease {
  InputLease(this.ready, this.paths);
  @override
  final Future<void> ready;
  final List<List<String>> paths;
  int releases = 0;
  @override
  Future<void> release() async {
    releases++;
  }
}

ContentInput<String> titleInput(StudySetContentRepository repo) => ContentInput(
  repository: repo,
  studySetId: 'demo-1',
  paths: [
    ['cards', 'c3'],
  ],
  read: (c) => c.card('c3')?.title,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('input waits for in-flight writes and protects latest source references', () async {
    final repo = InputRepository(), barrier = Completer<void>();
    repo.barrier = barrier.future;
    var opened = false;
    final pending =
        ContentInput(
          repository: repo,
          studySetId: 'demo-1',
          paths: [
            ['cards', 'c3'],
          ],
          relatedPaths: (c) => [
            ['source', c.card('c3')!.title],
          ],
          read: (c) => c.card('c3')?.title,
        ).open().then((s) {
          opened = true;
          return s;
        });
    expect(repo.leases, hasLength(1));
    await repo.update(
      'demo-1',
      (c) => c.copyWith(cards: [for (final card in c.cards) card.id == 'c3' ? card.copyWith(title: 'Latest') : card]),
    );
    expect(opened, isFalse);
    barrier.complete();
    final session = await pending;
    expect(session.value, 'Latest');
    expect(repo.leases.last.paths, [
      ['source', 'Latest'],
    ]);
    await session.close();
    await session.close();
    expect(repo.leases.map((l) => l.releases), [1, 1]);
  });

  test('failed opening releases protection; missing content never opens an empty input', () async {
    final repo = InputRepository();
    repo.barrier = Future.error(StateError('read failure'));
    await expectLater(titleInput(repo).open(), throwsStateError);
    expect(repo.leases.single.releases, 1);
    repo.barrier = Future.value();
    await repo.update('demo-1', (_) => StudySetContent.empty);
    await expectLater(titleInput(repo).open(), throwsStateError);
    expect(repo.leases.last.releases, 1);
    final memory = InMemoryStudySetContentRepository({'demo-1': demoContent()});
    expect(titleInput(memory).requiresProtection, isFalse);
    final unprotected = await titleInput(memory).open();
    await unprotected.save(() async {});
    await unprotected.close();
  });

  test('save failure remains retryable; disposal waits for save and releases exactly once', () async {
    final repo = InputRepository();
    final session = await titleInput(repo).open();
    await expectLater(session.save(() => throw StateError('disk full')), throwsStateError);
    expect(repo.leases.single.releases, 0);
    final write = Completer<void>();
    final save = session.save(() => write.future);
    expect(() => session.save(() async {}), throwsStateError);
    final close = session.close();
    expect(() => session.save(() async {}), throwsStateError);
    expect(repo.leases.single.releases, 0);
    write.complete();
    await save;
    await close;
    expect(repo.leases.single.releases, 1);
  });

  test('disposing a failed in-flight save still releases protection', () async {
    final repo = InputRepository(), write = Completer<void>();
    final session = await titleInput(repo).open();
    final save = expectLater(session.save(() => write.future), throwsStateError);
    final close = session.close();
    write.completeError(StateError('disk full'));
    await save;
    await close;
    expect(repo.leases.single.releases, 1);
  });

  for (final research in [false, true]) {
    testWidgets(
      '${research ? 'research' : 'study'} input waits, reads latest, saves once and protects until completion',
      (tester) async {
        final repo = InputRepository(), barrier = Completer<void>(), write = Completer<void>();
        repo.barrier = barrier.future;
        var writes = 0;
        String? saved;
        Future<void> save(String text) async {
          writes++;
          saved = text;
          await write.future;
        }

        await bare(
          tester,
          research
              ? NoteTextField(
                  text: 'Old frame',
                  style: const TextStyle(fontSize: 14),
                  onCommit: save,
                  semanticLabel: 'Title',
                  input: titleInput(repo),
                )
              : NoteEditableText(
                  text: 'Old frame',
                  style: const TextStyle(fontSize: 14),
                  onSave: save,
                  input: titleInput(repo),
                ),
        );
        await tester.tap(research ? find.byType(TextField) : find.text('Old frame'));
        await tester.pump();
        expect(repo.leases, hasLength(1));
        if (research) {
          expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
        } else {
          expect(find.byType(TextField), findsNothing);
        }
        barrier.complete();
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '遗忘的规律');
        await tester.enterText(find.byType(TextField), 'Typed');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(writes, 1);
        expect(saved, 'Typed');
        expect(repo.leases.single.releases, 0);
        await tester.pumpWidget(const SizedBox());
        expect(repo.leases.single.releases, 0);
        write.complete();
        await tester.pumpAndSettle();
        expect(repo.leases.single.releases, 1);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('${research ? 'research' : 'study'} failed save retains input and escape cancels without writing', (
      tester,
    ) async {
      final repo = InputRepository();
      var writes = 0;
      Future<void> save(String text) async {
        writes++;
        throw StateError('disk full');
      }

      await bare(
        tester,
        research
            ? NoteTextField(
                text: 'Old frame',
                style: const TextStyle(fontSize: 14),
                onCommit: save,
                semanticLabel: 'Title',
                input: titleInput(repo),
              )
            : NoteEditableText(
                text: 'Old frame',
                style: const TextStyle(fontSize: 14),
                onSave: save,
                input: titleInput(repo),
              ),
      );
      await tester.tap(research ? find.byType(TextField) : find.text('Old frame'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Unsaved');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(repo.leases.single.releases, 0);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Unsaved');
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(repo.leases.single.releases, 1);
    });

    testWidgets('${research ? 'research' : 'study'} disposal during opening releases after barrier', (tester) async {
      final repo = InputRepository(), barrier = Completer<void>();
      repo.barrier = barrier.future;
      await bare(
        tester,
        research
            ? NoteTextField(
                text: 'Old frame',
                style: const TextStyle(fontSize: 14),
                onCommit: (_) async {},
                semanticLabel: 'Title',
                input: titleInput(repo),
              )
            : NoteEditableText(
                text: 'Old frame',
                style: const TextStyle(fontSize: 14),
                onSave: (_) async {},
                input: titleInput(repo),
              ),
      );
      await tester.tap(research ? find.byType(TextField) : find.text('Old frame'));
      await tester.pumpWidget(const SizedBox());
      barrier.complete();
      await tester.pumpAndSettle();
      expect(repo.leases.single.releases, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('card details protect body, preserve failed text, and release after closing save', (tester) async {
    final repo = InputRepository();
    await repo.update(
      'demo-1',
      (c) => c.copyWith(cards: [for (final card in c.cards) card.id == 'c3' ? card.copyWith(body: 'Answer') : card]),
    );
    final app = await pumpApp(tester, content: repo);
    app.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final owner = app.read(workspaceProvider('demo-1').notifier);
    owner.showDetails('c3');
    await tester.pumpAndSettle();
    final field = find.descendant(of: find.byKey(const ValueKey('details-body-c3')), matching: find.byType(TextField));
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(repo.leases.single.paths, [
      ['cards', 'c3'],
    ]);
    repo.failNextWrite = true;
    await tester.enterText(field, 'Keep after failure');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(repo.leases.single.releases, 0);
    expect(tester.widget<TextField>(field).controller!.text, 'Keep after failure');
    await tester.tap(field);
    await tester.pump();
    await tester.enterText(field, 'Saved on close');
    owner.closePanel();
    await tester.pumpAndSettle();
    expect((await repo.load('demo-1')).card('c3')!.body, 'Saved on close');
    expect(repo.leases.single.releases, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('research input focused during a save becomes editable again when it completes', (tester) async {
    final repo = InputRepository(), gate = Completer<void>();
    await bare(
      tester,
      NoteTextField(
        text: 'Old',
        style: const TextStyle(fontSize: 14),
        semanticLabel: 'Title',
        input: titleInput(repo),
        onCommit: (_) => gate.future,
      ),
    );
    final field = find.byType(TextField);
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, 'New');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.tap(field);
    await tester.pump();
    expect(tester.widget<TextField>(field).readOnly, isTrue);
    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).readOnly, isFalse);
    expect(repo.leases, hasLength(2));
    expect(repo.leases.first.releases, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(repo.leases.last.releases, 1);
  });

  testWidgets('disabled formatting scope keeps text and format unchanged', (tester) async {
    final controller = NoteFormatController(text: 'Text', format: TextFormat.plain);
    final focus = FocusNode();
    await bare(
      tester,
      NoteFormatScope(
        controller: controller,
        enabled: false,
        child: TextField(controller: controller, focusNode: focus),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    Actions.invoke(tester.element(find.byType(TextField)), const NoteFormatIntent(NoteFormatCommand.bold));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(controller.text, 'Text');
    expect(controller.format, TextFormat.plain);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    focus.dispose();
  });

  testWidgets('study note source editing protects both block identity and live source', (tester) async {
    final repo = InputRepository();
    await repo.update('demo-1', (_) => noteFixture());
    final app = await pumpApp(tester, content: repo, prefs: {'settings.betaFeaturesEnabled': true});
    app.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    app.read(workspaceProvider('demo-1').notifier).openStudyNote('written');
    await tester.pumpAndSettle();
    final block = find.byKey(const ValueKey('note-edit-own'));
    await tester.ensureVisible(block);
    await tester.tap(find.descendant(of: block, matching: find.text('My original note')));
    await tester.pumpAndSettle();
    expect(repo.leases.map((l) => l.paths), [
      [
        ['studyNotes', 'written', 'sections', 'items', 'section', 'blocks', 'items', 'own'],
      ],
      [
        ['marginNotes', 'margin'],
      ],
    ]);
    final field = find.descendant(of: block, matching: find.byType(TextField));
    await tester.enterText(field, 'Edited live source');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect((await repo.load('demo-1')).marginNotes.single.text, 'Edited live source');
    expect(repo.leases.map((l) => l.releases), [1, 1]);
  });
}
