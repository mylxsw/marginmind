// Release verification of the actual workspace using isolated generated data.
// Commands are driven programmatically; this is not a physical-input acceptance test.
import 'dart:async';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:marginmind/app/app.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
// Diagnostic entry only: read the renderer's zoom without exposing it to app features.
// ignore: depend_on_referenced_packages
import 'package:pdfrx/pdfrx.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  stdout.writeln('BOOT bindings');
  await DesktopWindow.initialize(
    title: 'GUL-502 Workspace',
    minimumSize: const Size(1200, 800),
    initialSize: const Size(1600, 1000),
  );
  stdout.writeln('BOOT window');
  await windowManager.setAlwaysOnTop(true);
  await windowManager.setVisibleOnAllWorkspaces(true);
  await windowManager.maximize();
  stdout.writeln('BOOT engine');
  await MMPdfEngine.initialize();
  final directory = await Directory.systemTemp.createTemp('gul495-workspace-');
  final store = FileLibraryStore(directory);
  final set = await store.create(const NewStudySet(title: 'GUL-502 • Bidirectional location', colorIndex: 0));
  final data = await rootBundle.load('assets/sample/sample.pdf');
  final source = File('${directory.path}/images.pdf');
  await source.writeAsBytes(data.buffer.asUint8List());
  final fileName = await store.importFile(set.id, source.path);
  var counter = 0;
  final editor = StudySetEditor(newId: () => 'fixture-${++counter}', now: () => DateTime(2026, 10, 26));
  var content = editor.addDocument(StudySetContent.empty, title: 'Sample', fileName: fileName, pageCount: 3).$1;
  final excerpt = editor.createExcerpt(
    content,
    documentId: content.documents.first.id,
    page: 2,
    rects: const [PageRect(70, 450, 400, 420)],
    quote: 'Learning grows through connections.',
    colorIndex: 1,
  );
  content = excerpt.$1;
  final card = excerpt.$2;
  await store.update(set.id, (_) => content);
  stdout.writeln('BOOT seeded');
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      studySetRepositoryProvider.overrideWithValue(store),
      contentRepositoryProvider.overrideWithValue(store),
    ],
  );
  stdout.writeln('BOOT provider');
  stdout.writeln('BOOT loaded');
  container.read(navigationProvider.notifier).openStudySet(set.id);

  runApp(UncontrolledProviderScope(container: container, child: const MarginMindApp()));
  T widgetOf<T extends Widget>() {
    T? result;
    void visit(Element e) {
      if (e.widget is T) result = e.widget as T;
      e.visitChildren(visit);
    }

    visit(WidgetsBinding.instance.rootElement!);
    return result!;
  }

  Future<void> pause() => Future<void>.delayed(const Duration(seconds: 3));
  Timer(const Duration(seconds: 10), () async {
    try {
      final controller = container.read(workspaceProvider(set.id).notifier);
      final pdf = widgetOf<PdfViewer>().controller!;
      final map = widgetOf<MindMapCanvas>().transformation;
      await pdf.setZoom(pdf.centerPosition, 1);
      await pause();
      stdout.writeln('READY');
      await pause();
      controller.revealCard(card.id);
      await pause();
      stdout.writeln('REVEAL zoom=${pdf.currentZoom}');
      map.value = Matrix4.identity()..scaleByDouble(.1, .1, 1, 1);
      await pause();
      await controller.locateHighlightCard(card.annotationId!);
      await pause();
      stdout.writeln('LOCATE scale=${mapScale(map.value)}');
      await pause();
      await stdout.flush();
      exit(0);
    } catch (error, stack) {
      stderr.writeln('$error\n$stack');
      exit(1);
    }
  });
}
