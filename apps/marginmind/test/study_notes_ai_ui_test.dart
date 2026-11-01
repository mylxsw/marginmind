import 'package:marginmind/features/study_notes/note_model_route.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/app.dart' show touchPlatformProvider, phoneProvider;
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/study_notes/note_session.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

class FakeNoteOrganizer implements NoteOrganizer {
  Completer<void>? gate;
  bool fail = false;
  NoteOutline? accepted;
  @override
  Future<NoteOutline> outline(NoteMaterials m, NoteSettings s) async => NoteOutline([
    for (final (i, h) in m.highlights.indexed)
      NoteOutlineSection(
        title: 'Theme ${i + 1}',
        refs: [h.ref, ...m.items.where((n) => !n.isHighlight && n.annotationId == h.sourceId).map((n) => n.ref)],
      ),
  ]);
  @override
  Future<NoteDraft> write(NoteMaterials m, NoteOutline outline, NoteSettings settings) async {
    accepted = outline;
    await gate?.future;
    if (fail) throw StateError('private transport details');
    return NoteDraft([
      for (final (i, s) in outline.sections.indexed)
        NoteDraftSection(
          title: s.title,
          question: settings.depth == NoteDepth.deep ? 'Question ${s.title}?' : null,
          blocks: [
            NoteDraftBlock.fromJson({'type': 'summary', 'text': 'Summary ${s.title}'}),
            for (final r in s.refs) NoteDraftBlock.fromJson({'type': m[r]!.isHighlight ? 'quote' : 'own', 'ref': r}),
            NoteDraftBlock.fromJson({
              'type': 'points',
              'items': ['Point A', 'Point B'],
            }),
            if (i == 0 && outline.sections.length > 1)
              NoteDraftBlock.fromJson({'type': 'xref', 'to': 1, 'text': 'Related theme'}),
          ],
        ),
    ]);
  }

  @override
  Future<NotePlacements> place(NoteMaterials m, StudyNote n) async => NotePlacements([]);
}

class RetryingOutlineOrganizer extends FakeNoteOrganizer {
  var attempts = 0;
  @override
  Future<NoteOutline> outline(NoteMaterials m, NoteSettings s) async {
    if (attempts++ == 0) throw const ResearchFailure(ResearchFailureKind.budget, 'outputTruncated');
    return super.outline(m, s);
  }
}

class FakeNoteSession extends NoteSession {
  FakeNoteSession(FakeNoteOrganizer super.organizer);
  bool closed = false;
  @override
  void close() => closed = true;
  @override
  Future<String> rewrite(String text, NoteRewrite mode) async => 'Rewritten ${mode.name}';
  @override
  Future<String> reviewQuestion(NoteDraftSection section) async => 'Why does recall help?';
  @override
  Future<String> explain(NoteMaterial material) async => 'Explanation of the quote';
}

class StreamingNoteSession extends FakeNoteSession {
  StreamingNoteSession(super.organizer, this.gate);
  final Completer<void> gate;
  @override
  Stream<NoteDraftSection> write(NoteMaterials m, NoteOutline o, NoteSettings s, int startAt) async* {
    final draft = await organizer.write(m, o, s);
    for (final (i, section) in draft.sections.indexed) {
      if (i < startAt) continue;
      if (i == 1) await gate.future;
      yield section;
    }
  }
}

StudySetContent aiFixture() {
  final original = demoContent();
  final a = original.annotations.first;
  final c = original.copyWith(
    marginNotes: [
      MarginNote(
        id: 'attached-note',
        documentId: a.documentId,
        page: a.page,
        text: 'Attached observation',
        colorIndex: 0,
        anchor: AnnotationAnchor(quote: a.quote, pages: a.pages),
        createdAt: testNow,
        updatedAt: testNow,
      ),
    ],
  );
  final editor = StudySetEditor(newId: () => 'second', now: () => testNow);
  return editor
      .createExcerpt(
        c,
        documentId: c.documents.first.id,
        page: 30,
        rects: const [PageRect(10, 100, 100, 20)],
        quote: 'Spaced practice builds durable memories.',
        colorIndex: 1,
      )
      .$1;
}

Future<ProviderContainer> openAi(
  WidgetTester tester,
  FakeNoteOrganizer fake, {
  Future<NoteSession> Function()? factory,
  Size size = const Size(1600, 1100),
}) async {
  final container = await pumpApp(
    tester,
    size: size,
    prefs: const {'settings.betaFeaturesEnabled': true},
    content: InMemoryStudySetContentRepository({'demo-1': aiFixture()}),
    overrides: [
      if (size.width < 600) touchPlatformProvider.overrideWithValue(true),
      if (size.width < 600) phoneProvider.overrideWithValue(true),
      noteAiAvailableProvider.overrideWith((ref) async => true),
      noteRoutingRowProvider.overrideWith(
        (ref, model) async => const RoutingRowState(
          effective: ModelReference('fixture', 'model'),
          source: RoutingSource.functionBinding,
          issue: RoutingIssue.none,
        ),
      ),
      noteSessionFactoryProvider.overrideWithValue(
        ({studySetId, sessionId, modelOverride}) => (factory ?? () async => FakeNoteSession(fake))(),
      ),
    ],
  );
  container.read(navigationProvider.notifier).openStudySet('demo-1');
  await tester.pumpAndSettle();
  if (size.width < 600) {
    await tester.tap(find.byKey(const ValueKey('phone-workspace-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('phone-row-organize-notes')));
  } else {
    await tapWorkspaceCommand(tester, 'organize-note');
  }
  await tester.pumpAndSettle();
  await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pumpAndSettle();
  return container;
}

Future<void> generate(WidgetTester tester, {bool preview = false}) async {
  if (preview) {
    await tester.ensureVisible(find.byKey(const ValueKey('note-advanced')));
    await tester.tap(find.byKey(const ValueKey('note-advanced')));
    await tester.pumpAndSettle();
  }
  final action = find.byKey(ValueKey(preview ? 'note-preview-outline' : 'note-generate'));
  await tester.ensureVisible(action);
  await tester.tap(action);
  await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 100)));
  // A running request has a continuously animated activity indicator.
  await tester.pump();
  if (find.byKey(const ValueKey('note-stop')).evaluate().isNotEmpty) {
    await tester.pump(const Duration(milliseconds: 300));
  } else {
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('AI defaults, linkage and remembered depth', (tester) async {
    final c = await openAi(tester, FakeNoteOrganizer());
    expect(tester.widget<MMButton>(find.byKey(const ValueKey('depth-deep'))).variant, MMButtonVariant.primary);
    expect(find.textContaining('Send 2 highlights'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('depth-none')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-advanced')));
    await tester.pumpAndSettle();
    expect(tester.widget<MMButton>(find.byKey(const ValueKey('organization-source'))).variant, MMButtonVariant.primary);
    await tester.tap(find.byKey(const ValueKey('organization-theme')));
    await tester.tap(find.byKey(const ValueKey('depth-context')));
    await generate(tester);
    expect(c.read(workspaceProvider('demo-1').notifier).content.studyNotes.single.settings.depth, NoteDepth.context);
    expect(jsonDecode(c.read(sharedPreferencesProvider).getString('studyNotes.settings')!)['depth'], 'context');
    final owner = c.read(workspaceProvider('demo-1').notifier);
    final note = owner.content.studyNotes.single;
    final block = note.sections.first.blocks.first;
    await tester.tap(find.byKey(ValueKey('note-edit-${block.id}')), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Review Card'));
    await tester.pumpAndSettle();
    expect(owner.content.cards.any((c) => c.title == 'Why does recall help?'), isTrue);
    await settleHud(tester);
  });
  testWidgets('model truncation explains recovery and retry generates the note', (tester) async {
    final organizer = RetryingOutlineOrganizer();
    final c = await openAi(tester, organizer);
    await generate(tester);
    expect(find.textContaining('model stopped'), findsOneWidget);
    expect(find.textContaining('outputTruncated'), findsNothing);
    expect(c.read(workspaceProvider('demo-1').notifier).content.studyNotes, isEmpty);
    await tester.tap(find.byKey(const ValueKey('note-continue')));
    await tester.pumpAndSettle();
    expect(organizer.attempts, 2);
    expect(c.read(workspaceProvider('demo-1').notifier).content.studyNotes, hasLength(1));
    await settleHud(tester);
  });

  testWidgets('compact AI setup and outline wrap all footer actions without overflow', (tester) async {
    await openAi(tester, FakeNoteOrganizer(), size: const Size(400, 800));
    expect(tester.takeException(), isNull);
    await generate(tester, preview: true);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('outline-generate')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await settleHud(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('outline drag, rename, delete, unassigned and reorder', (tester) async {
    final fake = FakeNoteOrganizer();
    await openAi(tester, fake);
    await generate(tester, preview: true);
    expect(find.text('Confirm outline'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'Renamed');
    await tester.tap(find.byKey(const ValueKey('outline-add')));
    await tester.pumpAndSettle();
    final item = find.byKey(const ValueKey('outline-ref-h1'));
    final target = find.byKey(const ValueKey('outline-target-2'));
    await tester.dragFrom(tester.getCenter(item), tester.getCenter(target) - tester.getCenter(item));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('outline-delete-0')));
    await tester.pumpAndSettle();
    final handles = find.byType(ReorderableDragStartListener);
    final gesture = await tester.startGesture(tester.getCenter(handles.first));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(handles.last) + const Offset(0, 60));
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('outline-generate')));
    await tester.pumpAndSettle();
    expect(fake.accepted!.sections.expand((s) => s.refs).where((r) => r.startsWith('h')).toSet(), {'h1', 'h2'});
    expect(fake.accepted!.sections.first.title, 'New section');
    expect(fake.accepted!.sections.first.refs.any((r) => r.startsWith('n')), isTrue);
    await settleHud(tester);
  });
  testWidgets('stop ignores late results, continue failure offers local fallback', (tester) async {
    final fake = FakeNoteOrganizer()..gate = Completer<void>();
    final c = await openAi(tester, fake);
    await generate(tester);
    await tester.tap(find.byKey(const ValueKey('note-stop')));
    await tester.pumpAndSettle();
    fake.gate!.complete();
    await tester.pumpAndSettle();
    expect(c.read(workspaceProvider('demo-1').notifier).content.studyNotes, isEmpty);
    fake.gate = null;
    fake.fail = true;
    await tester.tap(find.text('Continue organizing').last);
    await tester.pumpAndSettle();
    expect(find.text('private transport details'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('note-fallback')));
    await tester.pumpAndSettle();
    final note = c.read(workspaceProvider('demo-1').notifier).content.studyNotes.single;
    expect(note.settings.depth, NoteDepth.none);
    expect(note.sections.expand((s) => s.blocks).whereType<QuoteBlock>(), hasLength(2));
    // Reorganizing a local note never opens a model session, even if it would fail.
    await tester.tap(find.byKey(const ValueKey('note-regenerate')));
    await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(c.read(workspaceProvider('demo-1').notifier).content.studyNotes, hasLength(1));
    expect(find.byKey(const ValueKey('note-fallback')), findsNothing);
    await settleHud(tester);
  });
  testWidgets('streamed sections persist on stop and continue skips completed sections', (tester) async {
    final fake = FakeNoteOrganizer();
    final gate = Completer<void>();
    final sessions = <StreamingNoteSession>[];
    final c = await openAi(
      tester,
      fake,
      factory: () async {
        final session = StreamingNoteSession(fake, gate);
        sessions.add(session);
        return session;
      },
    );
    await generate(tester);
    expect(find.text('Summary Theme 1'), findsWidgets);
    expect(find.text('Completed 1 / 2 sections'), findsOneWidget);
    expect(find.text('Writing section 2'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('note-stop')));
    await tester.pumpAndSettle();
    final owner = c.read(workspaceProvider('demo-1').notifier);
    expect(owner.content.studyNotes.single.sections, hasLength(1));
    expect(sessions.first.closed, isTrue);
    gate.complete();
    await tester.pumpAndSettle();
    expect(owner.content.studyNotes.single.sections, hasLength(1));
    await tester.tap(find.text('Continue organizing').last);
    await tester.pumpAndSettle();
    expect(owner.content.studyNotes, hasLength(1));
    expect(owner.content.studyNotes.single.sections, hasLength(2));
    expect(sessions.every((s) => s.closed), isTrue);
    await settleHud(tester);
  });

  testWidgets('Escape stops once, preserves completed work and ignores a late section', (tester) async {
    final fake = FakeNoteOrganizer();
    final gate = Completer<void>();
    final session = StreamingNoteSession(fake, gate);
    final c = await openAi(tester, fake, factory: () async => session);
    await generate(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(session.closed, isTrue);
    expect(find.byKey(const ValueKey('note-stop')), findsNothing);
    final owner = c.read(workspaceProvider('demo-1').notifier);
    expect(owner.content.studyNotes.single.sections, hasLength(1));
    gate.complete();
    await tester.pumpAndSettle();
    expect(owner.content.studyNotes.single.sections, hasLength(1));
    await settleHud(tester);
  });

  testWidgets('quote explanation, make mine and own-note menus use the right voices', (tester) async {
    final c = await openAi(tester, FakeNoteOrganizer());
    await generate(tester);
    final owner = c.read(workspaceProvider('demo-1').notifier);
    final note = owner.content.studyNotes.single;
    final quote = note.sections.first.blocks.whereType<QuoteBlock>().single;
    await tester.tap(find.byKey(ValueKey('quote-${quote.annotationId}')), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Explain This Passage'));
    await tester.pumpAndSettle();
    expect(
      owner.content
          .studyNote(note.id)!
          .sections
          .first
          .blocks
          .whereType<TextBlock>()
          .where((b) => b.kind == TextKind.gloss)
          .single
          .annotationId,
      quote.annotationId,
    );
    expect(find.text('Explanation of the quote'), findsOneWidget);
    final block = note.sections.first.blocks.first;
    await tester.tap(find.byKey(ValueKey('note-edit-${block.id}')), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Make it mine'));
    await tester.pumpAndSettle();
    final mine = owner.content.studyNote(note.id)!.sections.first.blocks.first;
    expect(mine.edited, isTrue);
    expect(mine.origin, NoteOrigin.user);
    await tester.tap(find.byKey(ValueKey('note-edit-${block.id}')), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Rephrase'), findsNothing);
    await tester.tapAt(const Offset(10, 100));
    await tester.pumpAndSettle();
    final a = owner.content.annotations.first;
    await owner.saveMarginNote(
      MarginNote(
        id: 'personal',
        documentId: a.documentId,
        page: a.page,
        lineY: 1,
        text: 'My own observation',
        colorIndex: 0,
        createdAt: testNow,
        updatedAt: testNow,
      ),
    );
    await owner.changeStudyNote(
      note.id,
      (n) => n.copyWith(
        sections: [
          n.sections.first.copyWith(
            blocks: [
              const OwnBlock(id: 'personal-block', sourceId: 'personal', source: OwnSource.marginNote),
              ...n.sections.first.blocks,
            ],
          ),
          ...n.sections.skip(1),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-edit-personal-block')), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Rephrase'), findsNothing);
    expect(find.text('Make concise'), findsNothing);
    expect(find.text('Expand'), findsNothing);
    await tester.tapAt(const Offset(10, 100));
    await settleHud(tester);
  });

  testWidgets('markers, rewrite locks, review sources and preservation on regenerate', (tester) async {
    final c = await openAi(tester, FakeNoteOrganizer());
    await generate(tester);
    final owner = c.read(workspaceProvider('demo-1').notifier);
    final note = owner.content.studyNotes.single;
    final block = note.sections.first.blocks.first;
    final xref = note.sections.first.blocks.whereType<XrefBlock>().single;
    await tester.ensureVisible(find.byKey(ValueKey('note-xref-${xref.id}')));
    await tester.tap(find.byKey(ValueKey('note-xref-${xref.id}')));
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byKey(ValueKey('note-edit-${xref.id}')), matching: find.byType(TextField)),
      findsNothing,
    );
    await tester.ensureVisible(find.byKey(ValueKey('note-edit-${block.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('note-ai-tag-${block.id}')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('note-ai-markers')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('note-ai-tag-${block.id}')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('note-ai-markers')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('note-edit-${block.id}')), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Make concise'));
    await tester.pumpAndSettle();
    final edited = owner.content.studyNote(note.id)!.sections.first.blocks.first;
    expect(edited.edited, isTrue);
    expect(edited.origin, NoteOrigin.mixed);
    expect(find.text('AI · Edited'), findsWidgets);
    await owner.addNoteReviews(note.id);
    await owner.addNoteReviews(note.id);
    final cards = owner.content.cards.where((c) => c.title.startsWith('Question '));
    expect(cards, hasLength(2));
    expect(cards.first.body, contains(owner.content.annotations.first.quote));
    expect(cards.first.body, contains(owner.content.documents.first.title));
    expect(owner.content.reviewableCards.map((c) => c.id), contains(cards.first.id));
    final face = buildReviewFace(cards.first, owner.content);
    expect(face.front.title, cards.first.title);
    expect(face.back.notes.first.text, cards.first.body);
    await owner.editStudyNoteBlock(note.id, xref.id, text: 'My edited connection');
    final editedLink = owner.content.studyNote(note.id)!.sections.first.blocks.whereType<XrefBlock>().single;
    await tester.tap(find.byKey(const ValueKey('note-regenerate')));
    await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(
      owner.content
          .studyNote(note.id)!
          .sections
          .expand((s) => s.blocks)
          .where((b) => b.id == edited.id)
          .single
          .toJson(),
      edited.toJson(),
    );
    final refreshed = owner.content.studyNote(note.id)!;
    expect(refreshed.sections.where((s) => s.title == note.sections.first.title), hasLength(1));
    expect(
      refreshed.sections.first.blocks.whereType<TextBlock>().where((b) => b.kind == TextKind.summary),
      hasLength(1),
    );
    final keptLink = refreshed.sections
        .expand((s) => s.blocks)
        .whereType<XrefBlock>()
        .where((b) => b.id == editedLink.id)
        .single;
    expect(keptLink.toJson(), editedLink.toJson());
    expect(refreshed.sections.any((s) => s.id == keptLink.toSectionId), isTrue);
    await settleHud(tester);
    expect(tester.takeException(), isNull);
  });
}
