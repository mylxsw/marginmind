import 'package:marginmind/features/study_notes/note_model_route.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/study_notes/note_session.dart';
import 'package:marginmind/features/study_notes/note_updates.dart';
import 'package:marginmind/features/study_notes/note_view.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_assistant/mm_assistant.dart' show RoutingRowState, RoutingIssue;
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';
import 'study_notes_ui_test.dart' show noteFixture, openNote;

StudySetContent updateFixture({NoteTemplate template = NoteTemplate.reading, bool ai = false}) {
  final c = noteFixture(), note = noteFixture().studyNotes.single;
  final a = c.annotations.single;
  return c.copyWith(
    annotations: [
      a,
      Annotation(
        id: 'fresh',
        documentId: a.documentId,
        page: a.page,
        rects: a.rects,
        quote: 'New evidence for active recall',
        colorIndex: 1,
        createdAt: testNow.add(const Duration(days: 1)),
      ),
    ],
    marginNotes: [
      ...c.marginNotes,
      MarginNote(
        id: 'fresh-own',
        documentId: a.documentId,
        page: a.page,
        lineY: 1,
        text: 'A new reflection',
        colorIndex: 0,
        createdAt: testNow.add(const Duration(days: 1)),
        updatedAt: testNow.add(const Duration(days: 1)),
      ),
    ],
    studyNotes: [
      note.copyWith(
        template: template,
        settings: NoteSettings(depth: ai ? NoteDepth.deep : NoteDepth.none),
        sections: [
          NoteSection(
            id: 'section',
            title: 'Memory',
            question: 'Why recall?',
            blocks: [
              const TextBlock(
                id: 'summary',
                text: 'My corrected summary',
                kind: TextKind.summary,
                origin: NoteOrigin.mixed,
                edited: true,
              ),
              ...note.sections.single.blocks,
            ],
          ),
        ],
      ),
    ],
  );
}

Future<void> previewUpdate(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('note-update-preview')));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('note-update-apply')), findsOneWidget);
}

class PlacementOrganizer implements NoteOrganizer {
  Completer<void>? gate;
  NoteMaterials? received;
  @override
  Future<NotePlacements> place(NoteMaterials materials, StudyNote note) async {
    received = materials;
    await gate?.future;
    return NotePlacements([
      for (final m in materials.items)
        NotePlacement(
          ref: m.ref,
          sectionId: note.sections.first.id,
          afterBlockId: 'quote',
          title: 'Memory',
          why: 'Supports active recall',
        ),
    ]);
  }

  @override
  Future<NoteOutline> outline(NoteMaterials m, NoteSettings s) => throw UnimplementedError();
  @override
  Future<NoteDraft> write(NoteMaterials m, NoteOutline o, NoteSettings s) => throw UnimplementedError();
}

class PlacementSession extends NoteSession {
  PlacementSession(super.organizer);
  bool closed = false;
  @override
  void close() {
    closed = true;
    super.close();
  }
}

Future<(ProviderContainer, PlacementSession)> openAiUpdate(WidgetTester tester, PlacementOrganizer organizer) async {
  final session = PlacementSession(organizer);
  final container = await pumpApp(
    tester,
    size: const Size(1800, 1100),
    content: InMemoryStudySetContentRepository({'demo-1': updateFixture(ai: true)}),
    overrides: [
      noteAiAvailableProvider.overrideWith((ref) async => true),
      noteRoutingRowProvider.overrideWith(
        (ref, model) async => const RoutingRowState(
          effective: ModelReference('fixture', 'model'),
          source: RoutingSource.functionBinding,
          issue: RoutingIssue.none,
        ),
      ),
      noteSessionFactoryProvider.overrideWithValue(({studySetId, sessionId, modelOverride}) async => session),
    ],
  );
  container.read(navigationProvider.notifier).openStudySet('demo-1');
  await tester.pumpAndSettle();
  container.read(workspaceProvider('demo-1').notifier).openStudyNote('written');
  await tester.pumpAndSettle();
  return (container, session);
}

void main() {
  testWidgets('preview is read only; cancel preserves content; apply merges and undo restores', (tester) async {
    final container = await openNote(tester, content: updateFixture(), size: const Size(1800, 1100));
    final owner = container.read(workspaceProvider('demo-1').notifier);
    final before = jsonEncode(owner.content.studyNotes.single.toJson());
    expect(find.text('1 new highlight, 1 new note'), findsOneWidget);
    expect(find.byKey(const ValueKey('note-update-badge-written')), findsOneWidget);
    await previewUpdate(tester);
    expect(find.text('In source order'), findsWidgets);
    expect(find.text('2 additions'), findsOneWidget);
    expect(find.text('New evidence for active recall'), findsWidgets);
    expect(jsonEncode(owner.content.studyNotes.single.toJson()), before);
    await tester.tap(find.byKey(const ValueKey('note-update-cancel')));
    await tester.pumpAndSettle();
    expect(jsonEncode(owner.content.studyNotes.single.toJson()), before);
    await previewUpdate(tester);
    owner.recordPage(owner.content.documents.first.id, 25);
    await tester.pump(const Duration(milliseconds: 850));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-update-apply')));
    await tester.pumpAndSettle();
    final blocks = owner.content.studyNotes.single.sections.expand((s) => s.blocks).toList();
    expect(blocks.whereType<QuoteBlock>().map((b) => b.annotationId), contains('fresh'));
    expect(blocks.whereType<OwnBlock>().map((b) => b.sourceId), contains('fresh-own'));
    expect(blocks.whereType<TextBlock>().single.text, 'My corrected summary');
    expect(blocks.whereType<TextBlock>().single.edited, isTrue);
    expect(find.text('Updated · 2 added'), findsOneWidget);
    expect(find.byKey(const ValueKey('note-update-banner')), findsNothing);
    expect(find.byKey(const ValueKey('note-update-badge-written')), findsNothing);
    expect(find.byTooltip('Keep when updating'), findsWidgets);
    await owner.undo();
    await tester.pumpAndSettle();
    expect(jsonEncode(owner.content.studyNotes.single.toJson()), before);
    await settleHud(tester);
  });

  testWidgets('ignore persists source IDs and reorganization still collects ignored sources', (tester) async {
    final container = await openNote(tester, content: updateFixture(), size: const Size(1800, 1100));
    final owner = container.read(workspaceProvider('demo-1').notifier);
    final before = jsonEncode(owner.content.studyNotes.single.toJson());
    await tester.tap(find.byKey(const ValueKey('note-update-ignore')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('note-update-banner')), findsNothing);
    expect(find.byKey(const ValueKey('note-update-badge-written')), findsNothing);
    expect(jsonEncode(owner.content.studyNotes.single.toJson()), before);
    expect(
      container.read(sharedPreferencesProvider).getStringList('studyNotes.ignored.demo-1.written'),
      contains('highlight:fresh'),
    );
    final note = owner.content.studyNotes.single;
    final all = const NoteMaterialCollector().collect(owner.content, note.scope, note.settings, now: DateTime.now());
    expect(all.highlights.map((h) => h.sourceId), contains('fresh'));
    container.invalidate(noteIgnoredUpdatesProvider(('demo-1', 'written')));
    expect(container.read(noteChangesProvider(('demo-1', 'written')))!.count, 0);
    await tester.tap(find.byKey(const ValueKey('note-regenerate')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pumpAndSettle();
    final blocks = owner.content.studyNotes.single.sections.expand((s) => s.blocks).toList();
    expect(blocks.whereType<QuoteBlock>().map((b) => b.annotationId), contains('fresh'));
    expect(blocks.whereType<TextBlock>().single.text, 'My corrected summary');
    expect(blocks.whereType<TextBlock>().single.edited, isTrue);
    await settleHud(tester);
  });

  testWidgets('deleted highlight stays archived until confirmed; removed documents stay preserved', (tester) async {
    final container = await openNote(tester, content: updateFixture());
    final owner = container.read(workspaceProvider('demo-1').notifier);
    final original = owner.content.annotations.first;
    await owner.deleteHighlight(original.id);
    await tester.pumpAndSettle();
    expect(resolveNoteSource(owner.content, original.id).status, NoteSourceStatus.annotationDeleted);
    await previewUpdate(tester);
    final text = tester
        .widgetList<Text>(find.text(original.quote))
        .where((t) => t.style?.decoration == TextDecoration.lineThrough);
    expect(text, isNotEmpty);
    await tester.tap(find.byKey(const ValueKey('note-update-cancel')));
    await tester.pumpAndSettle();
    expect(
      owner.content.studyNotes.single.sections
          .expand((s) => s.blocks)
          .whereType<QuoteBlock>()
          .map((b) => b.annotationId),
      contains(original.id),
    );
    await previewUpdate(tester);
    await tester.tap(find.byKey(const ValueKey('note-update-apply')));
    await tester.pumpAndSettle();
    expect(
      owner.content.studyNotes.single.sections
          .expand((s) => s.blocks)
          .whereType<QuoteBlock>()
          .map((b) => b.annotationId),
      isNot(contains(original.id)),
    );
    expect(owner.content.noteSourceArchive, isEmpty);
    await owner.undo();
    await owner.removeDocument(original.documentId);
    await tester.pumpAndSettle();
    expect(resolveNoteSource(owner.content, original.id).status, NoteSourceStatus.documentRemoved);
    expect(collectNoteChanges(owner.content, owner.content.studyNotes.single).deleted, isEmpty);
    expect(find.byKey(const ValueKey('note-source-quote')), findsOneWidget);
    expect(tester.widget<MMInteractive>(find.byKey(const ValueKey('note-source-quote'))).onTap, isNull);
    await settleHud(tester);
  });

  testWidgets('all templates preserve blocks, Cornell shows cues, review reveals and creates a card', (tester) async {
    final container = await openNote(tester, content: updateFixture(), size: const Size(1800, 1100));
    final owner = container.read(workspaceProvider('demo-1').notifier);
    final before = jsonEncode(owner.content.studyNotes.single.sections.map((s) => s.toJson()).toList());
    for (final template in [NoteTemplate.cornell, NoteTemplate.review, NoteTemplate.reading]) {
      await tester.tap(find.byKey(const ValueKey('note-template')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(switch (template) {
          NoteTemplate.cornell => 'Cornell Notes',
          NoteTemplate.review => 'Review Outline',
          _ => 'Reading Notes',
        }).last,
      );
      await tester.pumpAndSettle();
      expect(owner.content.studyNotes.single.template, template);
      expect(jsonEncode(owner.content.studyNotes.single.sections.map((s) => s.toJson()).toList()), before);
      if (template == NoteTemplate.cornell) {
        expect(find.byKey(const ValueKey('section:cornell:cue')), findsOneWidget);
        expect(find.text('Why recall?'), findsWidgets);
        expect(find.byKey(const ValueKey('section:cornell:summary')), findsOneWidget);
      }
      if (template == NoteTemplate.review) {
        final quote = find.byKey(ValueKey('quote-${owner.content.annotations.first.id}'));
        final recall =
            'What does ${owner.content.documents.first.title} Page ${owner.content.annotations.first.page} say?';
        expect(tester.widget<MMInteractive>(quote).semanticLabel, recall);
        expect(
          tester.widget<ImageFiltered>(find.descendant(of: quote, matching: find.byType(ImageFiltered))).enabled,
          isTrue,
        );
        await tester.tap(quote);
        await tester.pumpAndSettle();
        expect(tester.widget<MMInteractive>(quote).semanticLabel, isNull);
        expect(
          tester.widget<ImageFiltered>(find.descendant(of: quote, matching: find.byType(ImageFiltered))).enabled,
          isFalse,
        );
        final review = find.byWidgetPredicate(
          (w) => w is MMButton && w.label == 'Add to Review' && w.onPressed != null,
        );
        await tester.tap(review.first);
        await tester.pumpAndSettle();
        expect(
          owner.content.cards.any((c) => c.title == recall && c.body.contains(owner.content.annotations.first.quote)),
          isTrue,
        );
      }
    }
    await settleHud(tester);
  });

  testWidgets('AI placements show reason, close session, preserve locks and reject stale sources', (tester) async {
    final organizer = PlacementOrganizer();
    final (container, session) = await openAiUpdate(tester, organizer);
    final owner = container.read(workspaceProvider('demo-1').notifier);
    container.read(noteUpdateRequestedProvider('written').notifier).request();
    await tester.pumpAndSettle();
    expect(organizer.received!.items, hasLength(2));
    expect(find.text('Supports active recall'), findsWidgets);
    expect(session.closed, isTrue);
    await owner.saveMarginNote(
      owner.content.marginNotes.first.copyWith(text: 'Changed while previewing', updatedAt: DateTime.now()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-update-apply')));
    await tester.pumpAndSettle();
    expect(find.text('The note or its sources changed. Preview again.'), findsOneWidget);
    expect(owner.content.studyNotes.single.sections.expand((s) => s.blocks).whereType<QuoteBlock>(), hasLength(1));
    await settleHud(tester);
  });

  testWidgets('cancel an in-flight AI placement closes connection and discards late results', (tester) async {
    final organizer = PlacementOrganizer()..gate = Completer<void>();
    final (container, session) = await openAiUpdate(tester, organizer);
    await tester.tap(find.byKey(const ValueKey('note-update-preview')));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('note-update-cancel')));
    await tester.pumpAndSettle();
    expect(session.closed, isTrue);
    organizer.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('note-update-apply')), findsNothing);
    expect(
      container
          .read(workspaceProvider('demo-1'))
          .content!
          .studyNotes
          .single
          .sections
          .expand((s) => s.blocks)
          .whereType<QuoteBlock>(),
      hasLength(1),
    );
    await settleHud(tester);
  });
  testWidgets('preview from review keeps the stored template and supports scrolling without editing', (tester) async {
    final container = await openNote(
      tester,
      content: updateFixture(template: NoteTemplate.review),
      size: const Size(1800, 700),
    );
    final owner = container.read(workspaceProvider('demo-1').notifier);
    final before = jsonEncode(owner.content.studyNotes.single.toJson());
    await previewUpdate(tester);
    expect(owner.content.studyNotes.single.template, NoteTemplate.review);
    final scroll = find.byKey(const ValueKey('note-scroll'));
    final bar = find.byKey(const ValueKey('note-update-preview-bar'));
    final barTop = tester.getTopLeft(bar);
    expect(tester.getSize(bar).width, tester.getSize(find.byType(StudyNoteView)).width);
    expect(tester.widget<MMGlassBar>(bar), isNotNull);
    final controller = tester.widget<SingleChildScrollView>(scroll).controller!;
    await tester.drag(scroll, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
    expect(tester.getTopLeft(bar), barTop);
    expect(find.descendant(of: scroll, matching: find.byType(TextField)), findsNothing);
    await tester.tap(find.byKey(const ValueKey('note-update-cancel')));
    await tester.pumpAndSettle();
    expect(jsonEncode(owner.content.studyNotes.single.toJson()), before);
    await settleHud(tester);
  });

  testWidgets('editing a note during preview rejects apply and retains the edit', (tester) async {
    final container = await openNote(tester, content: updateFixture());
    final owner = container.read(workspaceProvider('demo-1').notifier);
    await previewUpdate(tester);
    await owner.editStudyNoteBlock('written', 'summary', text: 'A later correction');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-update-apply')));
    await tester.pumpAndSettle();
    expect(find.text('The note or its sources changed. Preview again.'), findsOneWidget);
    expect(
      owner.content.studyNotes.single.sections.expand((s) => s.blocks).whereType<TextBlock>().single.text,
      'A later correction',
    );
    expect(collectNoteChanges(owner.content, owner.content.studyNotes.single).highlights, 1);
    await settleHud(tester);
  });

  test('scope and cutoff exclude existing, old and out-of-scope materials', () {
    final content = updateFixture();
    final note = content.studyNotes.single;
    final selected = note.copyWith(scope: SelectedAnnotations([content.annotations.first.id]));
    expect(collectNoteChanges(content, selected).highlights, 0);
    expect(collectNoteChanges(content, note).highlights, 1);
    final newer = note.copyWith(organizedAt: DateTime.now());
    expect(collectNoteChanges(content, newer).count, 0);
  });
  testWidgets('File menu previews the independent note while its source is open', (tester) async {
    final container = await openNote(tester, content: updateFixture());
    final owner = container.read(workspaceProvider('demo-1').notifier);
    owner.showNoteReference(NoteReference.document);
    await tester.pumpAndSettle();
    Iterable<PlatformMenuItem> flatten(List<PlatformMenuItem> items) sync* {
      for (final item in items) {
        yield item;
        if (item is PlatformMenu) yield* flatten(item.menus);
        if (item is PlatformMenuItemGroup) yield* flatten(item.members);
      }
    }

    final command = flatten(tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar)).menus)
        .firstWhere((item) => item.label == 'Preview Update');
    expect(command.onSelected, isNotNull);
    command.onSelected!();
    await tester.pumpAndSettle();
    expect(find.byType(StudyNoteView), findsOneWidget);
    expect(find.byKey(const ValueKey('note-update-apply')), findsOneWidget);
    expect(container.read(noteUpdateRequestedProvider('written')), isFalse);
    expect(container.read(workspaceProvider('demo-1')).tabs.current.reference?.kind, WorkspaceReferenceKind.document);
    await tester.tap(find.byKey(const ValueKey('note-update-cancel')));
    await settleHud(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  testWidgets('section AI question appears once and each review card saves its own displayed question', (tester) async {
    final content = updateFixture(template: NoteTemplate.review, ai: true);
    final note = content.studyNotes.single;
    final section = note.sections.single;
    final c = content.copyWith(
      studyNotes: [
        note.copyWith(
          sections: [
            section.copyWith(
              blocks: [
                ...section.blocks,
                const QuoteBlock(id: 'second-quote', annotationId: 'fresh'),
              ],
            ),
          ],
        ),
      ],
    );
    final container = await openNote(tester, content: c, size: const Size(1800, 1100));
    final owner = container.read(workspaceProvider('demo-1').notifier);
    expect(tester.widget<Text>(find.byKey(const ValueKey('note-review-question-quote'))).data, 'Why recall?');
    final fallback = 'What does ${content.documents.first.title} Page ${content.annotations.last.page} say?';
    expect(tester.widget<Text>(find.byKey(const ValueKey('note-review-question-second-quote'))).data, fallback);
    expect(find.byKey(const ValueKey('note-review-ai-quote')), findsOneWidget);
    expect(find.byKey(const ValueKey('note-review-ai-second-quote')), findsNothing);
    for (final id in ['quote', 'second-quote']) {
      final button = find.byKey(ValueKey('note-review-add-$id'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      final widget = tester.widget<MMButton>(button);
      expect(widget.label, 'Add to Review');
      expect(widget.variant, MMButtonVariant.plain);
      expect(widget.icon, MMIcons.review);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }
    expect(
      owner.content.cards.any((c) => c.title == 'Why recall?' && c.body.contains(content.annotations.first.quote)),
      isTrue,
    );
    expect(
      owner.content.cards.any((c) => c.title == fallback && c.body.contains(content.annotations.last.quote)),
      isTrue,
    );
    await settleHud(tester);
  });

  testWidgets('narrow Chinese preview bar and applied count match the copy specification', (tester) async {
    await openNote(tester, content: updateFixture(), language: 'zh', size: const Size(960, 900));
    await previewUpdate(tester);
    final bar = find.byKey(const ValueKey('note-update-preview-bar'));
    expect(find.text('新增 2 处'), findsOneWidget);
    expect(tester.getSize(bar).width, tester.getSize(find.byType(StudyNoteView)).width);
    expect(find.descendant(of: bar, matching: find.byIcon(MMIcons.regenerate)), findsOneWidget);
    expect(tester.widget<MMButton>(find.byKey(const ValueKey('note-update-cancel'))).variant, MMButtonVariant.plain);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('note-update-apply')));
    await tester.pumpAndSettle();
    expect(find.text('已更新 · 新增 2 条'), findsOneWidget);
    await settleHud(tester);
  });
}
