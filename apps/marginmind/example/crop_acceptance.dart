// Native acceptance fixture using the production app, PDFium and bundled PDF.
// flutter run -d macos -t example/crop_acceptance.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:marginmind/features/workspace/reader_crop.dart';

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
  await DesktopWindow.initialize(title: 'MarginMind · Crop acceptance', minimumSize: const Size(1100, 800));
  await MMPdfEngine.initialize();
  debugPrint('CROP_NATIVE engine initialized');
  final bytes = await rootBundle.load('assets/sample/sample.pdf');
  final file = File('${Directory.systemTemp.path}/marginmind-crop-acceptance.pdf');
  await file.writeAsBytes(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
  final pdf = await PdfDocument.openFile(file.path);
  debugPrint('CROP_NATIVE document open');
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
  const id = 'crop-acceptance', docId = 'crop-document';
  final content = StudySetContent.empty.copyWith(
    documents: [Document(id: docId, title: '学习与记忆', fileName: file.path, pageCount: count, importedAt: now)],
    annotations: [
      Annotation(id: 'highlight', documentId: docId, page: 1, rects: rects, quote: '', colorIndex: 0, createdAt: now),
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
  debugPrint('CROP_NATIVE text read');
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      studySetRepositoryProvider.overrideWithValue(
        InMemoryStudySetRepository(
          sets: [
            StudySet(id: id, title: '阅读增强 · 裁边', colorIndex: 0, createdAt: now, lastOpenedAt: now, documentCount: 1),
          ],
        ),
      ),
      contentRepositoryProvider.overrideWithValue(InMemoryStudySetContentRepository({id: content})),
    ],
  );
  container.read(navigationProvider.notifier).openStudySet(id);
  debugPrint('CROP_NATIVE container ready');
  // Mount before awaiting providers whose error reporting uses Flutter frames.
  runApp(UncontrolledProviderScope(container: container, child: const MarginMindApp()));
  await container.read(contentProvider(id).future);
  debugPrint('CROP_NATIVE content loaded');
  final workspace = container.read(workspaceProvider(id).notifier);
  workspace.openDocument(docId);
  workspace.setLayout(MMSplitMode.primary);
  if (const bool.fromEnvironment('CROP_SELF_CHECK')) {
    await _verify(container);
    exit(0);
  }
}

Future<void> _verify(ProviderContainer container) async {
  const id = 'crop-acceptance';
  final pdf = container.read(readerPdfProvider(id));
  final session = container.read(readerCropProvider(id).notifier);
  Future<void> ready() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (var n = 0; n < 200; n++) {
      final state = container.read(readerCropProvider(id));
      if (pdf.isReady && !state.busy && state.automatic != null) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw StateError('Native crop timed out');
  }

  await ready();
  final before = pdf.readingPosition!;
  final text = await pdf.pageText(1);
  final image = await pdf.captureArea(1, const PageRect(100, 500, 200, 400));
  await session.toggle();
  await ready();
  final after = pdf.readingPosition!;
  if (after.page != before.page || (after.y - before.y).abs() > 1) {
    throw StateError('Native reading position moved: ${before.toJson()} -> ${after.toJson()}');
  }
  if (text == null ||
      text.isEmpty ||
      text != await pdf.pageText(1) ||
      image == null ||
      !listEquals(image, await pdf.captureArea(1, const PageRect(100, 500, 200, 400)))) {
    throw StateError('Original text/export changed');
  }
  await session.adjust();
  await ready();
  session.change(1, CropInsets(left: 100, top: 60));
  session.cancel();
  await ready();
  final restored = pdf.readingPosition!;
  if (restored.page != before.page || (restored.y - before.y).abs() > 1) {
    throw StateError('Cancel moved reading position');
  }
  debugPrint(
    'NATIVE_CROP_OK original=${before.toJson()} cropped=${after.toJson()} cancelled=${restored.toJson()} text/export=unchanged',
  );
}
