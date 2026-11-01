import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/features/library/library_controller.dart';

import '../../../packages/mm_pdf/test/support/pdf_backend.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Text, PlatformMenuBar, PlatformMenuItem, PlatformMenu, PlatformMenuItemGroup;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/document_commands.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/document_import.dart';
import 'package:marginmind/features/workspace/document_reader.dart';
import 'package:marginmind/features/workspace/reader_compare.dart';
import 'package:marginmind/features/workspace/reader_translation.dart';
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';
import 'package:marginmind/features/workspace/widgets/notices.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/workspace/workspace_browser.dart';
import 'package:marginmind/shared/document_icon.dart';
import 'package:marginmind/shared/pdf_drop.dart';
import 'package:mm_book/mm_book.dart' as book;
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import 'helpers.dart';
import '../../../packages/mm_book/test/fixtures.dart' as fixtures;

class BrowserCapabilities extends MMPlatformCapabilities {
  const BrowserCapabilities() : super(TargetPlatform.macOS);
  @override
  bool get webBrowser => true;
}

class BlockingImporter extends DocumentImporter {
  final gate = Completer<void>();
  @override
  Future<DocumentPackage> prepare(
    MMDocumentFile file, {
    required String id,
    required DateTime now,
    book.BookCancellationToken? cancellation,
  }) async {
    await gate.future;
    return DocumentPackage(
      document: Document(
        id: id,
        title: file.name,
        fileName: 'documents/cancel.md',
        format: DocumentFormat.markdown,
        layout: DocumentLayout.reflow,
        pageCount: 0,
        importedAt: now,
      ),
      files: {
        'documents/cancel.md': [1],
      },
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Markdown pipeline saves original, hashed chapter, manifest and local image', () async {
    final directory = await Directory.systemTemp.createTemp('mm_document_import');
    addTearDown(() => directory.delete(recursive: true));
    final image = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, ...List.filled(24, 0)]);
    await File('${directory.path}/image.png').writeAsBytes(image);
    final source = File('${directory.path}/note.md');
    await source.writeAsString('# Title\n\n你好😀\n\n![Image](image.png)');
    final package = await const DocumentImporter().prepare(
      (path: source.path, name: 'note.md'),
      id: 'book',
      now: testNow,
    );
    expect(package.document.format, DocumentFormat.markdown);
    expect(package.document.pageCount, 0);
    expect(package.document.sourceFileName, endsWith('.md'));
    final manifest = jsonDecode(utf8.decode(package.files[package.document.fileName]!));
    expect(manifest['version'], 1);
    expect(manifest['spine'], isNotEmpty);
    expect(manifest['resources'], isNotEmpty);
    for (final chapter in manifest['spine']) {
      expect(jsonDecode(utf8.decode(package.files[chapter['path']]!))['canonicalText'], contains('你好😀'));
    }
    final cancelled = book.BookCancellationToken()..cancel();
    await expectLater(
      const DocumentImporter().prepare(
        (path: source.path, name: 'note.md'),
        id: 'other',
        now: testNow,
        cancellation: cancelled,
      ),
      throwsA(isA<book.BookParseException>()),
    );
    expect(await MMDocumentFiles.readRelativeResource(source.path, '../outside.png'), isNull);
    expect(await MMDocumentFiles.readRelativeResource(source.path, 'https://example.com/image.png'), isNull);
    expect(await MMDocumentFiles.readRelativeResource(source.path, 'missing.png'), isNull);
    expect(documentImportError(const book.BookParseException(book.BookErrorKind.drm, 'DRM')), DocumentImportError.drm);
    expect(
      documentImportError(const book.BookParseException(book.BookErrorKind.unsupported, 'KFX')),
      DocumentImportError.kfx,
    );
    expect(documentImportError(const FormatException('No readable content')), DocumentImportError.empty);
    expect(documentImportError(StateError('IO')), DocumentImportError.unavailable);
    expect(
      documentImportError(const book.BookParseException(book.BookErrorKind.damaged, 'Empty EPUB spine')),
      DocumentImportError.empty,
    );
    await expectLater(
      const DocumentImporter().prepare((path: '/missing', name: 'file.xyz'), id: 'unknown', now: testNow),
      throwsA(isA<book.BookParseException>()),
    );
    final empty = File('${directory.path}/empty.md');
    await empty.writeAsString(' \n');
    await expectLater(
      const DocumentImporter().prepare((path: empty.path, name: 'empty.md'), id: 'empty', now: testNow),
      throwsA(isA<FormatException>().having(documentImportError, 'kind', DocumentImportError.empty)),
    );
    expect(
      documentImportError(const book.BookParseException(book.BookErrorKind.unsupported, 'MOBI variant')),
      DocumentImportError.unsupported,
    );
    expect(
      documentImportError(const book.BookParseException(book.BookErrorKind.limitExceeded, 'Large book')),
      DocumentImportError.limitExceeded,
    );
    expect(
      documentImportError(const FormatException('Document exceeds import limit')),
      DocumentImportError.limitExceeded,
    );
  });

  test('image-heavy Kindle imports above 256 MiB share the 500 MiB reader and parser budget', () async {
    final directory = await Directory.systemTemp.createTemp('mm_large_mobi');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/large.mobi');
    await source.writeAsBytes(fixtures.mobi('<p>Large Kindle book</p>', tail: [Uint8List(1)]));
    final handle = await source.open(mode: FileMode.append);
    await handle.truncate(256 * 1024 * 1024 + 1);
    await handle.close();
    for (final name in ['large.mobi', 'large.azw', 'large.azw3']) {
      final package = await const DocumentImporter().prepare(
        (path: source.path, name: name),
        id: 'large',
        now: testNow,
      );
      final manifest = jsonDecode(utf8.decode(package.files[package.document.fileName]!));
      final chapter = jsonDecode(utf8.decode(package.files[manifest['spine'][0]['path']]!));
      expect(chapter['canonicalText'], 'Large Kindle book');
      expect(package.files[package.document.sourceFileName]!.length, 256 * 1024 * 1024 + 1);
    }
    final oversized = await source.open(mode: FileMode.append);
    await oversized.truncate(500 * 1024 * 1024 + 1);
    await oversized.close();
    await expectLater(
      const DocumentImporter().prepare((path: source.path, name: 'large.mobi'), id: 'large', now: testNow),
      throwsA(isA<FormatException>().having(documentImportError, 'kind', DocumentImportError.limitExceeded)),
    );
  });

  test('batch import commits PDF and Markdown, reports failures and opens the first success', () async {
    installTestPdfBackend(pageCount: 5);
    final directory = await Directory.systemTemp.createTemp('mm_import_batch');
    addTearDown(() => directory.delete(recursive: true));
    await File('${directory.path}/first.md').writeAsString('# First\n\nBody');
    await File('${directory.path}/second.pdf').writeAsString('%PDF-1.7');
    await File('${directory.path}/broken.epub').writeAsString('broken');
    final repository = InMemoryStudySetContentRepository();
    final container = ProviderContainer(overrides: await testOverrides(content: repository));
    addTearDown(container.dispose);
    container.listen(importedDocumentsProvider('demo-1'), (_, _) {});
    final controller = container.read(workspaceProvider('demo-1').notifier);
    final notice = await controller.importDocuments([
      for (final name in ['first.md', 'second.pdf', 'broken.epub']) (path: '${directory.path}/$name', name: name),
    ]);
    expect(notice.count, 2);
    expect(
      container.read(importedDocumentsProvider('demo-1')),
      containsAll(controller.content.documents.map((d) => d.id)),
    );
    expect(notice.failed, ['broken.epub']);
    expect(notice.errors['broken.epub'], DocumentImportError.damaged);
    expect(controller.content.documents.last.pageCount, 5);
    expect(container.read(workspaceProvider('demo-1')).activeDocumentId, controller.content.documents.first.id);
    expect(container.read(documentImportsProvider('demo-1')), isEmpty);
    final before = await container.read(studySetRepositoryProvider).watchAll().first;
    final failure = await container.read(libraryViewProvider.notifier).createFromFiles([
      (path: '${directory.path}/broken.epub', name: 'broken.epub'),
    ]);
    expect(failure.count, 0);
    expect((await container.read(studySetRepositoryProvider).watchAll().first).length, before.length);
  });

  test('cancelling a pending import leaves no document or failure notice', () async {
    final importer = BlockingImporter();
    final container = ProviderContainer(
      overrides: [...await testOverrides(), documentImporterProvider.overrideWithValue(importer)],
    );
    addTearDown(container.dispose);
    final importing = container.read(workspaceProvider('demo-1').notifier).importDocuments([
      (path: 'pending.md', name: 'Pending.md'),
    ]);
    final task = container.read(documentImportsProvider('demo-1')).single;
    container.read(documentImportsProvider('demo-1').notifier).cancel(task.id);
    importer.gate.complete();
    final notice = await importing;
    expect(notice.count, 0);
    expect(notice.failed, isEmpty);
    expect(container.read(documentImportsProvider('demo-1')), isEmpty);
  });

  for (final available in [true, false]) {
    testWidgets('both import menus dispatch web command only when available=$available', (tester) async {
      var opened = 0;
      var picked = 0;
      final container = await pumpApp(
        tester,
        pdfPicker: (_) async {
          picked++;
          return [];
        },
        overrides: [
          documentPlatformProvider.overrideWithValue(
            available ? const BrowserCapabilities() : const MMPlatformCapabilities(TargetPlatform.linux),
          ),
          addWebPageHandlerProvider.overrideWithValue((context, ref, id) async {
            opened++;
          }),
        ],
      );
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      final add = find.byKey(const ValueKey('add-document-menu'));
      if (available) {
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: tester.getCenter(add));
        await mouse.moveTo(tester.getCenter(add));
        await tester.pumpAndSettle();
        await tester.tap(add);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add Web Page…'));
        await tester.pumpAndSettle();
        expect(opened, 1);
      } else {
        expect(add, findsNothing);
      }
      await openReaderDocumentMenu(tester);
      await tester.pumpAndSettle();
      expect(find.text('Import Document…'), findsOneWidget);
      if (available) {
        await tester.tap(find.text('Add Web Page…'));
        await tester.pumpAndSettle();
        expect(opened, 2);
        await openReaderDocumentMenu(tester);
        await tester.pumpAndSettle();
      } else {
        expect(find.text('Add Web Page…'), findsNothing);
      }
      await tester.tap(find.text('Import Document…'));
      await tester.pumpAndSettle();
      expect(picked, 1);
    });
  }

  testWidgets('missing browser handler hides entry even with platform support', (tester) async {
    final container = await pumpApp(
      tester,
      overrides: [
        documentPlatformProvider.overrideWithValue(const BrowserCapabilities()),
        addWebPageHandlerProvider.overrideWithValue(null),
      ],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('add-document-menu')), findsNothing);
  });

  for (final available in [true, false]) {
    testWidgets('real default web handler opens all three menus only when available=$available', (tester) async {
      final container = await pumpApp(
        tester,
        overrides: [
          documentPlatformProvider.overrideWithValue(
            available ? const BrowserCapabilities() : const MMPlatformCapabilities(TargetPlatform.linux),
          ),
        ],
      );
      expect(container.read(addWebPageHandlerProvider), showAddWebPage);
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      Iterable<PlatformMenuItem> flatten(Iterable<PlatformMenuItem> items) sync* {
        for (final item in items) {
          yield item;
          if (item is PlatformMenu) yield* flatten(item.menus);
          if (item is PlatformMenuItemGroup) yield* flatten(item.members);
        }
      }

      final commands = flatten(tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar)).menus)
          .where((item) => item.label == 'Add Web Page…');
      expect(commands.length, available ? 1 : 0);
      Future<void> closeAddressPanel() async {
        await tester.pumpAndSettle();
        expect(find.text('Add Web Page'), findsOneWidget);
        await tester.tap(find.widgetWithText(MMButton, 'Cancel'));
        await tester.pumpAndSettle();
      }

      if (available) {
        commands.single.onSelected!();
        await closeAddressPanel();
      }
      final add = find.byKey(const ValueKey('add-document-menu'));
      if (available) {
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: tester.getCenter(add));
        await mouse.moveTo(tester.getCenter(add));
        await tester.pumpAndSettle();
        await tester.tap(add);
        await tester.pumpAndSettle();
        expect(find.text('Add Web Page…'), findsOneWidget);
        await tester.tap(find.text('Add Web Page…'));
        await closeAddressPanel();
        await mouse.removePointer();
      } else {
        expect(add, findsNothing);
      }
      await openReaderDocumentMenu(tester);
      await tester.pumpAndSettle();
      expect(find.text('Add Web Page…'), available ? findsOneWidget : findsNothing);
      if (available) {
        await tester.tap(find.text('Add Web Page…'));
        await closeAddressPanel();
      } else {
        await tester.tapAt(Offset.zero);
        await tester.pumpAndSettle();
      }
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  }

  testWidgets('reflow swaps crop, disables zoom and never mounts PDF viewport', (tester) async {
    final doc = Document(
      id: 'book',
      title: 'Markdown',
      fileName: 'books/book/v1/manifest.json',
      contentManifest: 'books/book/v1/manifest.json',
      format: DocumentFormat.markdown,
      layout: DocumentLayout.reflow,
      pageCount: 0,
      importedAt: testNow,
      readingPosition: TextReadingPosition(revision: 'v1', chapterId: 'main', offset: 0),
    );
    final editor = StudySetEditor(newId: newId, now: () => testNow);
    final excerpt = editor.createExcerpt(
      StudySetContent.empty.copyWith(documents: [doc]),
      documentId: doc.id,
      textAnchors: [const TextAnchor('main', 0, 2, '原文', revision: 'v1')],
      quote: '原文',
      colorIndex: 0,
    );
    final content = InMemoryStudySetContentRepository({'demo-1': excerpt.$1});
    final container = await pumpApp(
      tester,
      content: content,
      sets: [
        StudySet(
          id: 'demo-1',
          title: 'Text set',
          colorIndex: 0,
          createdAt: testNow,
          lastOpenedAt: testNow,
          documentCount: 1,
          lastPosition: LastReadingPosition(documentTitle: doc.title, position: doc.readingPosition),
        ),
      ],
    );
    expect(find.text(doc.title), findsOneWidget);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final controller = container.read(workspaceProvider('demo-1').notifier);
    controller.openDocument('book');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reader-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reader-settings')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ReaderPane), findsOneWidget);
    controller.revealCard(excerpt.$2.id);
    await tester.pumpAndSettle();
    expect(referenceState(tester).reveal!.textAnchors.single.quote, '原文');
    await controller.toggleBookmark();
    expect(controller.content.bookmarks.single.position, isA<TextReadingPosition>());
    await controller.toggleBookmark();
    expect(controller.content.bookmarks, isEmpty);
    await controller.setReadingPosition(doc.id, TextReadingPosition(revision: 'v1', chapterId: 'main', offset: 2));
    expect((controller.content.document(doc.id)!.readingPosition as TextReadingPosition).offset, 2);
    expect(controller.activeCapabilities.crop, isFalse);
    controller.showReaderPanel(ReaderPanelMode.thumbnails);
    expect(container.read(workspaceProvider('demo-1')).readerPanelVisible, isFalse);
    expect(documentIcon(doc), MMIcons.markdown);
    expect(
      documentIcon(
        Document(
          id: 'web',
          title: 'Web',
          fileName: 'web.pdf',
          format: DocumentFormat.web,
          pageCount: 2,
          importedAt: testNow,
        ),
      ),
      MMIcons.web,
    );
    for (final format in [DocumentFormat.epub, DocumentFormat.mobi, DocumentFormat.azw3]) {
      expect(
        documentIcon(
          Document(id: 'book', title: 'Book', fileName: 'book', format: format, pageCount: 0, importedAt: testNow),
        ),
        MMIcons.ebook,
      );
    }
    final task = container.read(documentImportsProvider('demo-1').notifier).add('Pending.epub');
    await tester.pump();
    expect(find.text('Pending.epub'), findsOneWidget);
    final row = find.byKey(ValueKey('import-${task.id}'));
    expect(tester.widget<MMSidebarItem>(row).labelColor, tester.element(row).mmColors.secondaryLabel);
    container.read(documentImportsProvider('demo-1').notifier).cancel(task.id);
    expect(task.cancelled, isTrue);
    container.read(documentImportsProvider('demo-1').notifier).remove(task);
    await tester.pumpAndSettle();
    expect(find.text('Pending.epub'), findsNothing);
  });

  testWidgets('mixed comparison panes use the reader adapter on either side', (tester) async {
    final text = Document(
      id: 'text',
      title: 'Book',
      fileName: 'books/text/v1/manifest.json',
      contentManifest: 'books/text/v1/manifest.json',
      format: DocumentFormat.epub,
      layout: DocumentLayout.reflow,
      pageCount: 0,
      importedAt: testNow,
    );
    final base = demoContent();
    final content = InMemoryStudySetContentRepository({
      'demo-1': base.copyWith(documents: [...base.documents, text]),
    });
    final container = await pumpApp(
      tester,
      content: content,
      overrides: [
        documentReaderBuilderProvider.overrideWithValue((context, ref, id, doc) => const Text('Book reader adapter')),
        // This test replaces both renderers; no source IR or PDF backend is mounted.
        translationParagraphsProvider(('demo-1', text.id)).overrideWith((ref) async => []),
        translationParagraphsProvider(('demo-1', base.documents.first.id)).overrideWith((ref) async => []),
      ],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    await container.read(readerCompareProvider('demo-1').notifier).select(text.id, readerWidth: 700);
    await tester.pumpAndSettle();
    expect(find.text('Book reader adapter'), findsOneWidget);
    final info = await container.read(compareDocumentInfoProvider(('demo-1', text.id)).future);
    expect(info.hasText, isTrue);
    await container.read(readerCompareProvider('demo-1').notifier).swap();
    await tester.pumpAndSettle();
    expect(container.read(readerCompareProvider('demo-1'))!.leftDocumentId, text.id);
    expect(find.text('Book reader adapter'), findsOneWidget);
  });

  testWidgets('import failures show one localized reason and dismiss cleanly', (tester) async {
    final container = await pumpApp(tester);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    for (final (kind, reason) in const [
      (DocumentImportError.drm, 'Protected by DRM'),
      (DocumentImportError.unsupported, 'Unsupported format'),
      (DocumentImportError.kfx, 'KFX isn’t supported'),
      (DocumentImportError.limitExceeded, 'The file size or expanded content exceeds the import limit'),
    ]) {
      showNotice(
        tester.element(find.byType(ReaderPane)),
        ImportedNotice(0, ['Book.epub'], errors: {'Book.epub': kind}),
        rootTitle: '',
      );
      await tester.pumpAndSettle();
      expect(find.text('Couldn’t Import “Book.epub”'), findsOneWidget);
      expect(find.text(reason), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('import-failed-sheet'))).width, 520);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('import-failed-badge')), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const ValueKey('import-failed-badge')), matching: find.byIcon(MMIcons.shield)),
        kind == DocumentImportError.drm ? findsOneWidget : findsNothing,
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text(reason), findsNothing);
    }
    showNotice(
      tester.element(find.byType(ReaderPane)),
      const ImportedNotice(
        0,
        ['A.epub', 'B.mobi'],
        errors: {'A.epub': DocumentImportError.drm, 'B.mobi': DocumentImportError.damaged},
      ),
      rootTitle: '',
    );
    await tester.pumpAndSettle();
    expect(find.text('2 documents couldn’t be imported'), findsOneWidget);
    expect(find.text('B.mobi — The file is damaged'), findsOneWidget);
    expect(find.byKey(const ValueKey('import-failed-badge')), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  });

  testWidgets('import failure fits a phone with a long filename and multiple errors', (tester) async {
    await pumpApp(
      tester,
      size: const Size(390, 844),
      overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(true)],
    );
    final name = '${List.filled(20, 'Very long book title ').join()}.mobi';
    showNotice(
      tester.element(find.byType(Text).first),
      ImportedNotice(
        0,
        [name, 'B.mobi'],
        errors: {name: DocumentImportError.limitExceeded, 'B.mobi': DocumentImportError.damaged},
      ),
      rootTitle: '',
    );
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byKey(const ValueKey('import-failed-sheet')));
    expect(rect.width, lessThanOrEqualTo(390));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(390));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  });

  testWidgets('mixed desktop drop preserves supported documents and reports unsupported name', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final container = await pumpApp(tester);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final target = find.byType(PdfDropTarget).first;
    final platform = tester.widget<MMFileDropTarget>(
      find.descendant(of: target, matching: find.byType(MMFileDropTarget)).first,
    );
    platform.onDrop([(path: '/not-a-file', name: 'unsupported.exe')]);
    await tester.pumpAndSettle();
    expect(find.text('“unsupported.exe” isn’t supported'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
