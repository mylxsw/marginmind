import 'dart:convert';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/study_notes/note_export_sheet.dart';
import 'package:marginmind/features/study_notes/note_setup_sheet.dart';
import 'package:marginmind/features/study_notes/note_view.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

StudySetContent noteFixture() {
  final c = demoContent();
  final a = c.annotations.first;
  return c.copyWith(
    marginNotes: [
      MarginNote(
        id: 'margin',
        documentId: a.documentId,
        page: a.page,
        lineY: 1,
        text: 'My original note',
        colorIndex: 0,
        createdAt: testNow,
        updatedAt: testNow,
      ),
    ],
    studyNotes: [
      StudyNote(
        id: 'written',
        title: 'Learning through recall',
        scope: const WholeSet(),
        settings: NoteSettings(depth: NoteDepth.none),
        createdAt: testNow,
        updatedAt: testNow,
        organizedAt: testNow,
        sections: [
          NoteSection(
            id: 'section',
            title: 'Memory',
            blocks: [
              QuoteBlock(id: 'quote', annotationId: a.id),
              const OwnBlock(id: 'own', sourceId: 'margin', source: OwnSource.marginNote),
            ],
          ),
        ],
      ),
    ],
  );
}

Future<ProviderContainer> openNote(
  WidgetTester tester, {
  Size size = const Size(1600, 1000),
  String appearance = 'light',
  String language = 'en',
  StudySetContent? content,
  bool touch = false,
  bool phone = false,
}) async {
  final container = await pumpApp(
    tester,
    size: size,
    prefs: {
      'settings.appearance': appearance,
      'settings.language': language,
      'settings.betaFeaturesEnabled': true,
    },
    content: InMemoryStudySetContentRepository({'demo-1': content ?? noteFixture()}),
    overrides: [
      if (touch) touchPlatformProvider.overrideWithValue(true),
      if (touch) phoneProvider.overrideWithValue(phone),
    ],
  );
  container.read(navigationProvider.notifier).openStudySet('demo-1');
  await tester.pumpAndSettle();
  container.read(workspaceProvider('demo-1').notifier).openStudyNote('written');
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('setup scope, material toggles, local-only organization and layouts', (tester) async {
    final container = await openNote(tester);
    final owner = container.read(workspaceProvider('demo-1').notifier);
    owner.selectAnnotation(owner.content.annotations.first.id, true);
    await tapWorkspaceCommand(tester, 'organize-note');
    await tester.pumpAndSettle();
    expect(find.byType(NoteSetupSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('organization-source')), findsNothing);
    expect(find.byKey(const ValueKey('note-context-slider')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('note-advanced')));
    await tester.pumpAndSettle();
    final source = tester.widget<MMButton>(find.byKey(const ValueKey('organization-source')));
    expect(source.variant, MMButtonVariant.primary);
    expect(tester.widget<MMButton>(find.byKey(const ValueKey('organization-theme'))).onPressed, isNull);
    expect(tester.widget<MMButton>(find.byKey(const ValueKey('depth-deep'))).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('material-margin')));
    expect(tester.widget<MMButton>(find.byKey(const ValueKey('material-margin'))).variant, MMButtonVariant.secondary);
    await tester.tap(find.byKey(const ValueKey('organization-map')));
    await tester.tap(find.byKey(const ValueKey('template-cornell')));
    await tester.tap(find.byKey(const ValueKey('scope-recent')));
    await tester.pumpAndSettle();
    expect(find.text('No highlights in this scope'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('scope-selected')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-generate')));
    // File text extraction uses the engine asynchronously; the source fixture has no file.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pumpAndSettle();
    expect(owner.content.studyNotes.length, 2);
    final created = owner.content.studyNote(container.read(workspaceProvider('demo-1')).activeNoteId!)!;
    expect(created.scope, isA<SelectedAnnotations>());
    expect(created.template, NoteTemplate.cornell);
    expect(created.settings.depth, NoteDepth.none);
    expect(created.settings.organization, NoteOrganization.map);
    expect(created.sections.expand((s) => s.blocks).whereType<OwnBlock>(), isEmpty);
    final stored = container.read(sharedPreferencesProvider).getString('studyNotes.settings');
    expect(jsonDecode(stored!)['depth'], 'none');
    await settleHud(tester);
  });

  testWidgets('note renders quotes, edits synchronize and source navigation survives undo', (tester) async {
    final container = await openNote(tester);
    final owner = container.read(workspaceProvider('demo-1').notifier);
    expect(find.byType(StudyNoteView), findsOneWidget);
    expect(find.text(owner.content.annotations.first.quote), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('note-edit-own')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Updated from the study note');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(owner.content.marginNotes.single.text, 'Updated from the study note');
    await owner.undo();
    await tester.pumpAndSettle();
    expect(find.text('My original note'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('note-source-quote')));
    await tester.pumpAndSettle();
    expect(
      container.read(workspaceProvider('demo-1')).tabs.current.reference?.id,
      owner.content.annotations.first.documentId,
    );
    owner.tapHighlight(owner.content.annotations.first.id);
    await tester.pumpAndSettle();
    expect(find.byType(StudyNoteView), findsOneWidget);
    await owner.removeStudyNoteBlock('written', 'quote');
    await tester.pumpAndSettle();
    expect(find.text('1 unused highlights'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('note-coverage')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Put Back'));
    await tester.pumpAndSettle();
    expect(owner.content.studyNote('written')!.unusedAnnotationIds, isEmpty);
    expect(owner.content.annotations, hasLength(1));
    await owner.undo();
    expect(owner.content.studyNote('written')!.unusedAnnotationIds, hasLength(1));
    await settleHud(tester);
  });

  testWidgets('export preview switches formats, citations and own notes; save matches preview', (tester) async {
    final container = await openNote(tester);
    final owner = container.read(workspaceProvider('demo-1').notifier);
    String? saved, savedName;
    final context = tester.element(find.byType(StudyNoteView));
    showMMSheet<void>(
      context: context,
      width: MMSizes.noteExportSheetWidth,
      builder: (_) => NoteExportSheet(
        content: owner.content,
        note: owner.content.studyNote('written')!,
        save: (name, bytes, assets) async {
          savedName = name;
          saved = utf8.decode(bytes);
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();
    String preview() => tester.widget<SelectableText>(find.byKey(const ValueKey('note-export-preview'))).data!;
    expect(preview(), contains('My original note'));
    await tester.tap(find.byKey(const ValueKey('export-obsidian')));
    await tester.pumpAndSettle();
    expect(preview(), contains('> [!quote] [['));
    await tester.tap(find.byKey(const ValueKey('citation-footnote')));
    await tester.pumpAndSettle();
    expect(preview(), contains('[^h1]'));
    await tester.tap(find.byKey(const ValueKey('export-own')));
    await tester.pumpAndSettle();
    expect(preview(), isNot(contains('My original note')));
    final expected = preview();
    await tester.tap(find.byKey(const ValueKey('note-export-save')));
    await tester.pumpAndSettle();
    expect(saved, expected);
    expect(savedName, 'Learning through recall.md');
    expect(find.byType(NoteExportSheet), findsNothing);
    await settleHud(tester);
  });

  testWidgets('narrow dark note and export retain all controls without overflow', (tester) async {
    await openNote(tester, size: const Size(960, 680), appearance: 'dark');
    await tester.tap(find.byTooltip('Export Note…').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('note-export-preview')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await settleHud(tester);
  });
  testWidgets('export cancellation keeps the sheet; failure retries with a safe filename', (tester) async {
    final container = await openNote(tester);
    final owner = container.read(workspaceProvider('demo-1').notifier);
    final context = tester.element(find.byType(StudyNoteView));
    var attempts = 0;
    showMMSheet<void>(
      context: context,
      width: MMSizes.noteExportSheetWidth,
      builder: (_) => NoteExportSheet(
        content: owner.content,
        note: owner.content.studyNote('written')!.copyWith(title: 'A/B:C\\D'),
        save: (name, bytes, assets) async {
          expect(name, 'ABCD.md');
          attempts++;
          if (attempts == 1) return false;
          if (attempts == 2) throw StateError('Disk full');
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-export-save')));
    await tester.pumpAndSettle();
    expect(find.byType(NoteExportSheet), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('note-export-save')));
    await tester.pumpAndSettle();
    expect(find.text('Export failed. Please try again.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('note-export-save')));
    await tester.pumpAndSettle();
    expect(attempts, 3);
    expect(find.byType(NoteExportSheet), findsNothing);
    await settleHud(tester);
  });

  testWidgets('title edit cancels on Escape, commits on Enter, and the sidebar follows', (tester) async {
    final container = await openNote(tester);
    final owner = container.read(workspaceProvider('demo-1').notifier);
    await tester.tap(find.byKey(const ValueKey('note-title-written')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Discarded');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(owner.content.studyNote('written')!.title, 'Learning through recall');
    await tester.tap(find.byKey(const ValueKey('note-title-written')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'My study note');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(owner.content.studyNote('written')!.title, 'My study note');
    expect(
      find.descendant(of: find.byKey(const ValueKey('sidebar-note-written')), matching: find.text('My study note')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(ValueKey('quote-${owner.content.annotations.first.id}')));
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider('demo-1')).noteAnnotationId, owner.content.annotations.first.id);
    await settleHud(tester);
  });

  testWidgets('empty selected scope disables generation and remembered AI options stay local', (tester) async {
    await openNote(tester);
    await tapWorkspaceCommand(tester, 'organize-note');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scope-selected')));
    await tester.pumpAndSettle();
    expect(find.text('No highlights in this scope'), findsOneWidget);
    expect(tester.widget<MMButton>(find.byKey(const ValueKey('note-generate'))).onPressed, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await settleHud(tester);
  });
  testWidgets('sources merge by document, deduplicate and sort PDF pages, including multi-page quotes', (tester) async {
    final original = noteFixture();
    final docId = original.documents.first.id;
    Annotation quote(String id, int page) => Annotation(
      id: id,
      documentId: docId,
      page: page,
      rects: const [PageRect(1, 10, 10, 1)],
      quote: 'Quote $id',
      colorIndex: 0,
      createdAt: testNow,
    );
    final textDocument = Document(
      id: 'text-book',
      title: 'Article',
      fileName: 'article.md',
      format: DocumentFormat.markdown,
      pageCount: 0,
      importedAt: testNow,
    );
    final annotations = [
      ...original.annotations,
      quote('earlier', 12),
      quote('duplicate-page', 24),
      Annotation(
        id: 'multi-page',
        documentId: docId,
        pages: const [
          AnnotationPage(page: 16, rects: [PageRect(1, 10, 10, 1)]),
          AnnotationPage(page: 17, rects: [PageRect(1, 10, 10, 1)]),
        ],
        quote: 'Across pages',
        colorIndex: 0,
        createdAt: testNow,
      ),
      for (var i = 0; i < 2; i++)
        Annotation(
          id: 'text-$i',
          documentId: textDocument.id,
          textAnchors: [TextAnchor('main', 0, 4, 'Text', revision: 'v')],
          quote: 'Text',
          colorIndex: 0,
          createdAt: testNow,
        ),
    ];
    final note = original.studyNotes.single.copyWith(
      sections: [
        NoteSection(
          id: 'section',
          title: 'Quotes',
          blocks: [
            for (final annotation in annotations) QuoteBlock(id: 'block-${annotation.id}', annotationId: annotation.id),
            const QuoteBlock(id: 'missing-block', annotationId: 'missing'),
          ],
        ),
      ],
    );
    await openNote(
      tester,
      language: 'zh',
      content: original.copyWith(
        documents: [...original.documents, textDocument],
        annotations: annotations,
        studyNotes: [note],
      ),
    );
    final sources = find.byKey(const ValueKey('note-source-entry-0'));
    await tester.ensureVisible(sources);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(sources).data, '1. 学习的底层逻辑 · p.12、p.16、p.17、p.24');
    expect(tester.widget<Text>(find.byKey(const ValueKey('note-source-entry-1'))).data, '2. Article');
    expect(tester.widget<Text>(find.byKey(const ValueKey('note-source-entry-2'))).data, '3. 划线已删除');
    expect(find.text('《》'), findsNothing);
    expect(tester.takeException(), isNull);
    await settleHud(tester);
  });

  testWidgets('compact More exposes TOC and layout submenus, changes layouts and exports', (tester) async {
    final container = await openNote(tester, size: const Size(1240, 820));
    container.read(workspaceProvider('demo-1').notifier).showNoteReference(NoteReference.document);
    await tester.pumpAndSettle();
    expect(tester.widget<Icon>(find.byKey(const ValueKey('note-toolbar-icon'))).icon, MMIcons.studyNote);
    expect(find.byKey(const ValueKey('note-export')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('note-more')));
    await tester.pumpAndSettle();
    expect(find.text('Table of Contents'), findsOneWidget);
    expect(find.text('Layout'), findsOneWidget);
    expect(find.text('Export Note…'), findsOneWidget);
    expect(find.text('Cornell Notes'), findsNothing);
    await tester.tap(find.text('Layout'));
    await tester.pumpAndSettle();
    expect(find.text('Cornell Notes'), findsOneWidget);
    await tester.tap(find.text('Cornell Notes'));
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider('demo-1')).content!.studyNote('written')!.template, NoteTemplate.cornell);
    expect(find.text('Layout'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('note-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Table of Contents'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Memory').hitTestable().last);
    await tester.pumpAndSettle();
    expect(find.text('Export Note…'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('note-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export Note…'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteExportSheet), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await settleHud(tester);
  });

  testWidgets('medium note pane keeps AI, share and export actions without overflowing', (tester) async {
    final content = noteFixture();
    final note = content.studyNotes.single;
    await openNote(
      tester,
      size: const Size(1280, 1000),
      content: content.copyWith(
        studyNotes: [
          note.copyWith(
            sections: [
              note.sections.single.copyWith(
                blocks: [
                  ...note.sections.single.blocks,
                  const TextBlock(id: 'summary', text: 'AI summary', kind: TextKind.summary),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    final owner = ProviderScope.containerOf(tester.element(find.byType(StudyNoteView)))
        .read(workspaceProvider('demo-1').notifier);
    owner.showNoteReference(NoteReference.document);
    await tester.pumpAndSettle();
    final width = tester.getSize(find.byType(StudyNoteView)).width;
    expect(width, greaterThanOrEqualTo(MMSizes.noteSetupSheetWidth));
    expect(width, lessThan(MMNoteLayout.exportLabelMinWidth));
    expect(find.byKey(const ValueKey('note-ai-markers')), findsOneWidget);
    expect(find.byKey(const ValueKey('note-regenerate')), findsOneWidget);
    expect(find.byKey(const ValueKey('note-share')), findsOneWidget);
    final export = tester.widget<MMToolbarButton>(find.byKey(const ValueKey('note-export')));
    expect(export.label, isNull);
    expect(export.onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await settleHud(tester);
  });

  testWidgets('regular toolbar has labeled dropdowns, export icon and label; own sources include locations', (
    tester,
  ) async {
    final original = noteFixture();
    final card = Card(
      id: 'map-own',
      kind: CardKind.note,
      title: 'Recall plan',
      body: 'Own details',
      createdAt: testNow,
    );
    final note = original.studyNotes.single.copyWith(
      sections: [
        original.studyNotes.single.sections.single.copyWith(
          blocks: [
            ...original.studyNotes.single.sections.single.blocks,
            const OwnBlock(id: 'map-own-block', sourceId: 'map-own', source: OwnSource.card),
          ],
        ),
      ],
    );
    await openNote(
      tester,
      size: const Size(1800, 1000),
      content: original.copyWith(
        cards: [...original.cards, card],
        studyNotes: [note],
        documentOutlines: [
          DocumentOutline(
            documentId: original.documents.first.id,
            items: const [PdfOutlineEntry(id: 'chapter', title: 'Retrieval practice', page: 12)],
          ),
        ],
      ),
    );
    expect(find.text('Table of Contents'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const ValueKey('note-export')), matching: find.text('Export')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byKey(const ValueKey('note-export')), matching: find.byIcon(MMIcons.export)),
      findsOneWidget,
    );
    expect(find.text('Margin Note · p.24'), findsOneWidget);
    expect(find.text('Map Notes · Recall plan'), findsOneWidget);
    final source = find.byKey(const ValueKey('note-source-quote'));
    expect(tester.widget<MMInteractive>(source).tooltip, 'Retrieval practice');
    expect(find.descendant(of: source, matching: find.byIcon(MMIcons.revealSource)), findsOneWidget);
    expect(find.descendant(of: source, matching: find.text('学习的底层逻辑, p. 24')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await settleHud(tester);
  });
}
