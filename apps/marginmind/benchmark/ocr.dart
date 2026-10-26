// Native OCR acceptance harness with generated documents and an isolated library.
// First generate assets/sample/benchmark.pdf with tool/sample/make_ocr_pdf.swift.
// flutter build macos --debug -t benchmark/ocr.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/reader_ocr.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/settings/app_settings.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DesktopWindow.initialize(title: 'GUL-521 · OCR', minimumSize: MMSizes.windowMinSize);
  await MMPdfEngine.initialize();
  final directory = await Directory.systemTemp.createTemp('marginmind-ocr-');
  final store = FileLibraryStore(directory);
  final set = await store.create(const NewStudySet(title: '扫描讲义 · 学习与思考', colorIndex: 0));
  const asset = String.fromEnvironment('OCR_SAMPLE', defaultValue: 'assets/sample/benchmark.pdf');
  final data = await rootBundle.load(asset);
  final sample = File('${directory.path}/sample.pdf');
  await sample.writeAsBytes(data.buffer.asUint8List());
  final info = await MMPdfEngine.inspect(sample.path);
  final fileName = await store.importFile(set.id, sample.path);
  final editor = StudySetEditor(newId: newId, now: DateTime.now);
  final content = editor
      .addDocument(StudySetContent.empty, title: '中英文扫描讲义', fileName: fileName, pageCount: info.pageCount)
      .$1;
  await store.update(set.id, (_) => content);
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance()),
      settingsProvider.overrideWith(_OcrSettings.new),
      studySetRepositoryProvider.overrideWithValue(store),
      contentRepositoryProvider.overrideWithValue(store),
    ],
  );
  container.read(navigationProvider.notifier).openStudySet(set.id);
  runApp(UncontrolledProviderScope(container: container, child: const MarginMindApp()));
  stdout.writeln('OCR_READY pid=$pid library=${directory.path}');
  if (const bool.fromEnvironment('OCR_AUTO')) {
    Timer(const Duration(seconds: 15), () async {
      final controller = container.read(workspaceProvider(set.id).notifier);
      final source = controller.filePath(content.documents.first);
      final ocr = container.read(readerOcrProvider(source).notifier);
      await ocr.inspect();
      await ocr.recognize(1, info.pageCount, PdfOcrLanguage.chineseEnglish);
      stdout.writeln('OCR_FINISHED failed=${container.read(readerOcrProvider(source)).failed}');
    });
  }
}

class _OcrSettings extends SettingsController {
  @override
  AppSettings build() => const AppSettings(language: LanguagePreference.zh);
}
