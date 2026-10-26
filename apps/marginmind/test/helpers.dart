import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/shared/pdf_picker.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final testNow = DateTime(2026, 10, 25, 12);

/// Content of demo-1 ("认知科学入门"): two documents, three topics and one
/// excerpt under the first topic.
StudySetContent demoContent() {
  var n = 0;
  final editor = StudySetEditor(newId: () => 'c${++n}', now: () => testNow);
  var c = StudySetContent.empty;
  final (c1, d1) = editor.addDocument(c, title: '学习的底层逻辑', fileName: 'a.pdf', pageCount: 164);
  final (c2, _) = editor.addDocument(c1, title: '论文：检索练习效应', fileName: 'b.pdf', pageCount: 12);
  final (c3, t1) = editor.addTopic(c2, title: '遗忘的规律');
  final (c4, _) = editor.addTopic(c3, title: '对策一：间隔重复');
  final (c5, _) = editor.createExcerpt(
    c4,
    documentId: d1.id,
    page: 24,
    rects: const [PageRect(10, 100, 200, 88)],
    quote: '这条先陡后平的曲线，被称为遗忘曲线。',
    colorIndex: 0,
    parentId: t1.id,
  );
  return c5;
}

/// Overrides that make the app run in memory with fixed time. The open
/// panel answers with [pdfPicker], or is cancelled.
Future<List<Override>> testOverrides({
  Map<String, Object> prefs = const {},
  bool renderPdf = false,
  List<StudySet>? sets,
  InMemoryStudySetContentRepository? content,
  PdfPicker? pdfPicker,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final instance = await SharedPreferences.getInstance();
  return [
    sharedPreferencesProvider.overrideWithValue(instance),
    clockProvider.overrideWithValue(() => testNow),
    pdfRenderingEnabledProvider.overrideWithValue(renderPdf),
    pdfPickerProvider.overrideWithValue(pdfPicker ?? (_) async => const []),
    studySetRepositoryProvider.overrideWithValue(
      InMemoryStudySetRepository(
        sets: sets ?? DemoLibrary.studySets(testNow),
        folders: DemoLibrary.folders,
        clock: () => testNow,
      ),
    ),
    contentRepositoryProvider.overrideWithValue(
      content ?? InMemoryStudySetContentRepository({'demo-1': demoContent()}),
    ),
  ];
}

/// Pumps the whole app at a desktop window size.
Future<ProviderContainer> pumpApp(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  bool renderPdf = false,
  List<StudySet>? sets,
  InMemoryStudySetContentRepository? content,
  PdfPicker? pdfPicker,
}) async {
  tester.view.physicalSize = const Size(1280, 820);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final overrides = await testOverrides(
    prefs: prefs,
    sets: sets,
    content: content,
    renderPdf: renderPdf,
    pdfPicker: pdfPicker,
  );
  await tester.pumpWidget(ProviderScope(overrides: overrides, child: const MarginMindApp()));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(MarginMindApp)));
}

/// Double-clicks [finder] (Finder-style "open").
Future<void> doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Lets HUD / flash timers run out so tests end without pending timers.
Future<void> settleHud(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

/// Colors painted just outside a selected color dot found by [dot]: the gap
/// ring (1pt past its edge) and the outer ring (2.75pt past it), sampled on
/// the dot's horizontal center line.
Future<(Color gap, Color ring)> dotRingColors(WidgetTester tester, Finder dot) async {
  final box = tester.renderObject<RenderBox>(dot);
  RenderObject node = box;
  while (!node.isRepaintBoundary) {
    node = node.parent!;
  }
  final boundary = node as RenderBox;
  final center = boundary.globalToLocal(box.localToGlobal(box.size.center(Offset.zero)));
  const ratio = 4.0;
  final image = (await tester.runAsync(
    () => (boundary.debugLayer! as OffsetLayer).toImage(Offset.zero & boundary.size, pixelRatio: ratio),
  ))!;
  final bytes = (await tester.runAsync(() => image.toByteData()))!;
  Color at(double dx) {
    final x = ((center.dx + dx) * ratio).floor();
    final y = (center.dy * ratio).floor();
    final i = (y * image.width + x) * 4;
    return Color.fromARGB(bytes.getUint8(i + 3), bytes.getUint8(i), bytes.getUint8(i + 1), bytes.getUint8(i + 2));
  }

  final radius = box.size.width / 2;
  final colors = (at(radius + 1), at(radius + 2.75));
  image.dispose();
  return colors;
}

/// Whether [actual] matches [expected] within rounding of the rasterizer.
Matcher sameColor(Color expected) => predicate<Color>(
  (actual) =>
      (actual.r - expected.r).abs() < 0.02 &&
      (actual.g - expected.g).abs() < 0.02 &&
      (actual.b - expected.b).abs() < 0.02,
  'color close to $expected',
);
