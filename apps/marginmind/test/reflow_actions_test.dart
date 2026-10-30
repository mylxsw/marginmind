import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/workspace/reflow_session.dart';
import 'package:mm_book/mm_book.dart';
import 'package:marginmind/settings/app_settings.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';
import 'reflow_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('text highlight, excerpt, underline, note transaction, reveal and undo', () async {
    final repo = InMemoryStudySetContentRepository();
    final doc = await storeBook(repo);
    final container = ProviderContainer(overrides: await testOverrides(content: repo));
    addTearDown(container.dispose);
    final provider = workspaceProvider('demo-1');
    container.listen(provider, (_, _) {});
    await container.read(contentProvider('demo-1').future);
    final workspace = container.read(provider.notifier);
    workspace.openDocument(doc.id);
    final anchor = TextAnchor('main', 0, 8, 'Learning', revision: doc.revision!);
    final selection = SourceSelection.text([anchor], viewportRect: const Rect.fromLTWH(1, 2, 50, 20));
    final stale = SourceSelection.text([const TextAnchor('main', 0, 1, 'x', revision: 'stale')]);
    expect(await workspace.onSourceSelectionCommitted(doc.id, stale), isNull);
    await expectLater(workspace.highlightSource(doc.id, stale, MMAnnotationColor.blue), throwsArgumentError);
    await workspace.onSourceSelectionCommitted(doc.id, selection);
    expect((container.read(provider).pending as PendingSelection).selection.textAnchors.single, same(anchor));
    await workspace.highlightSource(doc.id, selection, MMAnnotationColor.blue);
    final annotation = workspace.content.annotations.single;
    expect(annotation.textAnchors.single.revision, doc.revision);
    expect(() => annotation.page, throwsStateError);
    await workspace.undo();
    expect(workspace.content.annotations, isEmpty);
    await workspace.redo();
    final card = (await workspace.excerptSource(doc.id, selection, MMAnnotationColor.yellow)).cardId!;
    workspace.revealCard(card);
    expect(container.read(provider).reveal!.textAnchors.single.quote, 'Learning');
    await workspace.setTool(AnnotationTool.underline);
    await workspace.onSourceSelectionCommitted(doc.id, selection);
    final underlines = workspace.content.annotations.where((a) => a.kind == AnnotationKind.underline).toList();
    expect(underlines.length, 1);
    await workspace.styleUnderline(
      annotationId: underlines.single.id,
      style: AnnotationLineStyle.wavy,
      color: MMAnnotationColor.pink,
    );
    await workspace.underlineSource(doc.id, selection);
    expect(workspace.content.annotations.where((a) => a.kind == AnnotationKind.underline).length, 1);
    await workspace.setTool(AnnotationTool.highlight);
    workspace.toggleSyncToMap();
    expect(await workspace.onSourceSelectionCommitted(doc.id, selection), isA<HighlightedNotice>());
    workspace.toggleSyncToMap();
    expect(await workspace.onSourceSelectionCommitted(doc.id, selection), isA<ExcerptedNotice>());
    await workspace.setReadingPosition(
      doc.id,
      TextReadingPosition(revision: doc.revision!, chapterId: 'main', offset: 10),
    );
    await workspace.toggleBookmark();
    expect(workspace.content.bookmarks.single.position, isA<TextReadingPosition>());
    await workspace.undo();
    expect((workspace.content.document(doc.id)!.readingPosition as TextReadingPosition).offset, 10);
    final count = workspace.content.cards.length;
    final note = await workspace.excerptSourceAndEditNote(doc.id, selection, MMAnnotationColor.green);
    expect(note, isNotNull);
    await workspace.cancelEditing();
    expect(workspace.content.cards.length, count);
    expect(() => SourceSelection.text([]), throwsArgumentError);
    expect(() => SourceSelection.text([const TextAnchor('main', 0, 1, 'x')]), throwsArgumentError);
  });
  test('reading settings clamp, persist and keep book/article groups separate', () async {
    final overrides = await testOverrides(
      prefs: {
        'settings.reading.book.size': 99,
        'settings.reading.article.lineHeight': -2,
        'settings.reading.book.font': 'unknown',
      },
    );
    var container = ProviderContainer(overrides: overrides);
    final initial = container.read(settingsProvider);
    expect(initial.bookReading.size, 7);
    expect(initial.articleReading.lineHeight, 0);
    expect(initial.articleReading.paged, isFalse);
    for (final format in [DocumentFormat.epub, DocumentFormat.mobi, DocumentFormat.azw3]) {
      expect(initial.reading(format).paged, isFalse);
      expect(const AppSettings().reading(format).paged, isFalse);
    }
    expect(initial.bookReading.font, ReaderFont.original);
    final value = const ReadingSettings().copyWith(size: 5, lineHeight: 2, font: ReaderFont.sans, paged: true);
    await container.read(settingsProvider.notifier).setReading(DocumentFormat.epub, value);
    expect(container.read(settingsProvider).reading(DocumentFormat.mobi), value);
    expect(container.read(settingsProvider).articleReading.size, 3);
    expect(value.copyWith(size: 99).size, 7);
    await container
        .read(settingsProvider.notifier)
        .setReading(DocumentFormat.web, const ReadingSettings(size: 99, lineHeight: -1));
    expect(container.read(settingsProvider).articleReading.size, 7);
    expect(container.read(settingsProvider).articleReading.lineHeight, 0);
    expect(container.read(settingsProvider).articleReading.font, ReaderFont.serif);
    expect(value.copyWith(lineHeight: -1).lineHeight, 0);
    expect(value.hashCode, value.copyWith().hashCode);
    container.dispose();
    container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    expect(container.read(settingsProvider).bookReading, value);
    await container.read(settingsProvider.notifier).setReading(DocumentFormat.web, const ReadingSettings(size: 2));
    expect(container.read(settingsProvider).reading(DocumentFormat.markdown).size, 2);
    expect(container.read(sharedPreferencesProvider).getInt('settings.reading.article.size'), 2);
  });
  test('a replacement revision invalidates the reader and rejects late saved positions', () async {
    final repo = InMemoryStudySetContentRepository();
    final doc = await storeBook(repo);
    final container = ProviderContainer(overrides: await testOverrides(content: repo));
    addTearDown(container.dispose);
    final workspaceProviderKey = workspaceProvider('demo-1');
    container.listen(workspaceProviderKey, (_, _) {});
    await container.read(contentProvider('demo-1').future);
    final workspace = container.read(workspaceProviderKey.notifier);
    workspace.openDocument(doc.id);
    final provider = reflowSessionProvider(('demo-1', doc.id));
    container.listen(provider, (_, _) {});
    final first = container.read(provider);
    await first.initialize();
    final updated = await storeBook(
      repo,
      book: Book('Updated', [const EpubParser().parseHtml('main', '<p>New revision.</p>')], {}, []),
    );
    await workspace.renameDocument(doc.id, 'Updated');
    final second = container.read(provider);
    expect(second, same(container.read(provider)));
    expect(second, isNot(same(first)));
    await second.initialize();
    expect(second.book!.revision, updated.revision);
    await workspace.setReadingPosition(
      doc.id,
      TextReadingPosition(revision: doc.revision!, chapterId: 'main', offset: 8),
    );
    expect((workspace.content.document(doc.id)!.readingPosition as TextReadingPosition).revision, updated.revision);
  });
}
