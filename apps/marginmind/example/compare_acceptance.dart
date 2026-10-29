// Native fixture: production ReaderPane, real PDFium, isolated in-memory library.
// flutter run -d macos -t example/compare_acceptance.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/reader_compare.dart';
import 'package:marginmind/features/workspace/reader_crop.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DesktopWindow.initialize(
    title: 'MarginMind · Compare acceptance',
    minimumSize: const Size(1100, 800),
    initialSize: const Size(1600, 1000),
  );
  await MMPdfEngine.initialize();
  final bytes = await rootBundle.load('assets/sample/compare-source.pdf');
  final left = File('${Directory.systemTemp.path}/marginmind-compare-source.pdf');
  await left.writeAsBytes(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
  final translated = await rootBundle.load('assets/sample/compare-fixture.pdf');
  final right = File('${Directory.systemTemp.path}/marginmind-compare-target.pdf');
  await right.writeAsBytes(translated.buffer.asUint8List(translated.offsetInBytes, translated.lengthInBytes));
  final rightPath = right.path;
  final now = DateTime.now();
  final documents = [
    Document(
      id: 'english',
      title: 'Learning and memory.pdf',
      fileName: left.path,
      pageCount: (await MMPdfEngine.inspect(left.path)).pageCount,
      importedAt: now,
    ),
    Document(
      id: 'chinese',
      title: '学习与记忆.pdf',
      fileName: rightPath,
      pageCount: (await MMPdfEngine.inspect(rightPath)).pageCount,
      importedAt: now,
    ),
  ];
  const id = 'compare-acceptance';
  // Keep acceptance runs isolated from the person's application preferences.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({'settings.language': 'zh'});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      studySetRepositoryProvider.overrideWithValue(
        InMemoryStudySetRepository(
          sets: [
            StudySet(id: id, title: '阅读增强 · 对照阅读', colorIndex: 0, createdAt: now, lastOpenedAt: now, documentCount: 2),
          ],
        ),
      ),
      contentRepositoryProvider.overrideWithValue(
        InMemoryStudySetContentRepository({
          id: StudySetContent.empty.copyWith(
            documents: documents,
            marginNotes: [
              for (final doc in documents)
                MarginNote(
                  id: 'note-${doc.id}',
                  documentId: doc.id,
                  page: 1,
                  lineY: 500,
                  text: '把新知识与已有经验联系起来。',
                  colorIndex: 0,
                  createdAt: now,
                  updatedAt: now,
                ),
            ],
          ),
        }),
      ),
    ],
  );
  container.read(navigationProvider.notifier).openStudySet(id);
  runApp(UncontrolledProviderScope(container: container, child: const MarginMindApp()));
  await container.read(contentProvider(id).future);
  final workspace = container.read(workspaceProvider(id).notifier);
  workspace.openDocument('english');
  workspace.setLayout(MMSplitMode.split);
  final session = container.read(readerCompareProvider(id).notifier);
  await session.select('chinese', readerWidth: 600);
  debugPrint('COMPARE_NATIVE_ENTERED pid=$pid');
  if (const bool.fromEnvironment('COMPARE_SELF_CHECK')) {
    Future<void> ready({bool both = true}) async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      for (var n = 0; n < 200; n++) {
        if ((!both || session.pdf('english').isReady) &&
            session.pdf('chinese').isReady &&
            !container.read(readerCropProvider(id)).busy &&
            !container.read(readerDocumentCropProvider((id, 'chinese'))).busy) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      throw StateError('Compare PDF readiness timed out');
    }

    await ready();
    await session.toggleSync();
    await session.pdf('english').jumpToReadingPosition(PdfReadingPosition(page: 1, y: 520));
    await session.pdf('chinese').jumpToReadingPosition(PdfReadingPosition(page: 1, y: 450));
    if (!await session.align()) throw StateError('Native alignment unavailable');
    await container.read(readerCropProvider(id).notifier).toggle();
    await ready();
    await container.read(readerDocumentCropProvider((id, 'chinese')).notifier).toggle();
    await ready();
    final before = session.pdf('english').readingPosition!;
    session.swap();
    await ready();
    final after = session.pdf('english').readingPosition!;
    if (before.page != after.page || (before.y - after.y).abs() > 1) throw StateError('Swap moved reading line');
    await session.exit();
    await ready(both: false);
    final restored = container.read(workspaceProvider(id));
    if (restored.layout != MMSplitMode.split || !restored.sidebarVisible) throw StateError('Layout was not restored');
    debugPrint(
      'NATIVE_COMPARE_OK persisted=${workspace.content.comparePairs.single.alignPoints.length} swap=${after.toJson()} layout=restored',
    );
    exit(0);
  }
}
