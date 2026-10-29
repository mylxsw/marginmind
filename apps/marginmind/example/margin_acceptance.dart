// Native acceptance fixture using the production app, PDFium and bundled PDF.
// flutter run -d macos -t example/margin_acceptance.dart
// Add --dart-define=MARGIN_READER_STYLE=paper for the paper palette.
import 'dart:io';

import 'package:marginmind/features/workspace/reader_margin.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DesktopWindow.initialize(
    title: 'MarginMind · Margin acceptance',
    minimumSize: const Size(1100, 800),
    initialSize: const Size(1800, 1000),
  );
  await MMPdfEngine.initialize();
  debugPrint('MARGIN_NATIVE engine initialized');
  final bytes = await rootBundle.load('assets/sample/sample.pdf');
  final file = File('${Directory.systemTemp.path}/marginmind-margin-acceptance.pdf');
  await file.writeAsBytes(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
  final pdf = await PdfDocument.openFile(file.path);
  debugPrint('MARGIN_NATIVE document open');
  final text = await pdf.pages.first.loadStructuredText();
  final rects = text.fragments
      .where((f) => f.bounds.width > 40)
      .skip(2)
      .take(2)
      .map((f) => PageRect(f.bounds.left, f.bounds.top, f.bounds.right, f.bounds.bottom))
      .toList();
  final count = pdf.pages.length;
  await pdf.dispose();
  final now = DateTime.now();
  const id = 'margin-acceptance', docId = 'margin-document';
  final content = StudySetContent.empty.copyWith(
    documents: [Document(id: docId, title: '学习与记忆', fileName: file.path, pageCount: count, importedAt: now)],
    annotations: [
      Annotation(id: 'highlight', documentId: docId, page: 1, rects: rects, quote: '', colorIndex: 0, createdAt: now),
    ],
    marginNotes: [
      MarginNote(
        id: 'native-anchor',
        documentId: docId,
        page: 1,
        anchor: AnnotationAnchor(
          pages: [
            AnnotationPage(page: 1, rects: [rects.first]),
          ],
          quote: 'Learning and memory',
        ),
        text: '把新知识与已有经验联系起来。',
        colorIndex: 0,
        createdAt: now,
        updatedAt: now,
      ),
      MarginNote(
        id: 'native-line',
        documentId: docId,
        page: 1,
        lineY: rects.last.bottom - 20,
        text: '间隔练习比集中练习更有利于长期记忆。',
        colorIndex: 2,
        createdAt: now,
        updatedAt: now,
      ),
    ],
    inkStrokes: [
      InkStroke(
        id: 'ink',
        documentId: docId,
        page: 1,
        tool: InkTool.pen,
        colorIndex: 0,
        width: 2,
        points: [for (var x = 0; x <= 100; x += 5) InkPoint(100 + x.toDouble(), 300 + (x % 20) * .15)],
      ),
    ],
  );
  debugPrint('MARGIN_NATIVE text read');
  // This standalone acceptance harness must not change the user's preferences.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({
    'settings.appearance': 'light',
    'settings.language': 'zh',
    'settings.readerStyle': const String.fromEnvironment('MARGIN_READER_STYLE', defaultValue: 'white'),
  });
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      studySetRepositoryProvider.overrideWithValue(
        InMemoryStudySetRepository(
          sets: [
            StudySet(id: id, title: '阅读增强 · 页边批注', colorIndex: 0, createdAt: now, lastOpenedAt: now, documentCount: 1),
          ],
        ),
      ),
      contentRepositoryProvider.overrideWithValue(InMemoryStudySetContentRepository({id: content})),
    ],
  );
  container.read(navigationProvider.notifier).openStudySet(id);
  debugPrint('MARGIN_NATIVE container ready');
  // Mount before awaiting providers whose error reporting uses Flutter frames.
  runApp(UncontrolledProviderScope(container: container, child: const MarginMindApp()));
  await container.read(contentProvider(id).future);
  debugPrint('MARGIN_NATIVE content loaded');
  final workspace = container.read(workspaceProvider(id).notifier);
  workspace.openDocument(docId);
  workspace.setLayout(MMSplitMode.split);
  final marginLifetime = container.listen(readerMarginProvider(id), (_, _) {});
  final margin = container.read(readerMarginProvider(id).notifier);
  margin.expand(docId);
  if (const bool.fromEnvironment('MARGIN_SELF_CHECK')) {
    await _verify(container);
    marginLifetime.close();
    exit(0);
  }
}

Future<void> _verify(ProviderContainer container) async {
  const id = 'margin-acceptance', docId = 'margin-document';
  final pdf = container.read(readerPdfProvider(id));
  final session = container.read(readerMarginProvider(id).notifier);
  final workspace = container.read(workspaceProvider(id).notifier);
  for (var n = 0; n < 200 && !pdf.isReady; n++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  if (!pdf.isReady) throw StateError('PDF not ready');
  final before = pdf.readingPosition!;
  await session.start(docId, page: 1, lineY: 400);
  session.text('Native saved note');
  await session.finish();
  final note = workspace.content.marginNotes.last;
  final layout = container.read(workspaceProvider(id)).layout;
  final cardId = await workspace.attachMarginNote(note.id);
  await workspace.rename(cardId!, 'Native map edit');
  if (workspace.content.marginNotes.last.text != 'Native map edit' ||
      container.read(workspaceProvider(id)).layout != layout) {
    throw StateError('Native map synchronization failed');
  }
  await workspace.deleteMarginNote(note.id);
  if (workspace.content.card(cardId) == null) throw StateError('Deleted linked card');
  await workspace.undo();
  session.toggle(docId);
  await Future<void>.delayed(const Duration(milliseconds: 500));
  final after = pdf.readingPosition!;
  if (before.page != after.page || (before.y - after.y).abs() > 1) throw StateError('Reading position moved');
  debugPrint('NATIVE_MARGIN_OK');
}
