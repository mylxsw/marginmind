import 'package:marginmind/features/workspace/workspace_content_host.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/app/window_title.dart';
import 'package:marginmind/shared/pdf_picker.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
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
  VocabularyRepository? vocabulary,
  List<StudySet>? sets,
  InMemoryStudySetContentRepository? content,
  PdfPicker? pdfPicker,
  DateTime Function()? clock,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final instance = await SharedPreferences.getInstance();
  return [
    windowTitleSinkProvider.overrideWithValue((_) async {}),
    vocabularyRepositoryProvider.overrideWithValue(vocabulary ?? InMemoryVocabularyRepository()),
    sharedPreferencesProvider.overrideWithValue(instance),
    clockProvider.overrideWithValue(clock ?? () => testNow),
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
  VocabularyRepository? vocabulary,
  List<StudySet>? sets,
  InMemoryStudySetContentRepository? content,
  PdfPicker? pdfPicker,
  DateTime Function()? clock,
  List<Override> overrides = const [],
  Size size = const Size(1280, 820),
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final base = await testOverrides(
    prefs: prefs,
    sets: sets,
    content: content,
    renderPdf: renderPdf,
    vocabulary: vocabulary,
    pdfPicker: pdfPicker,
    clock: clock,
  );
  await tester.pumpWidget(ProviderScope(overrides: [...base, ...overrides], child: const MarginMindApp()));
  if (settle) await tester.pumpAndSettle();
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

/// Reveal the complete fixture before pointer tests address distant nodes.
Future<void> showWholeMap(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Show Entire Map'));
  await tester.pumpAndSettle();
}

/// Commands that moved into Aa remain covered through their actual menu path.
Future<void> tapReaderCommand(WidgetTester tester, Finder command) async {
  if (command.hitTestable().evaluate().isEmpty) {
    await tester.tap(find.byKey(const ValueKey('reader-more')));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(command.last);
  await tester.tap(command.last);
  await tester.pumpAndSettle();
}

Future<void> tapWorkspaceCommand(WidgetTester tester, String id) async {
  final direct = find.byKey(ValueKey('toolbar-$id')).hitTestable();
  if (direct.evaluate().isNotEmpty) {
    await tester.tap(direct.first);
  } else {
    final dedicatedMenu = find
        .byWidgetPredicate(
          (widget) =>
              widget is MMDropdownButton<VoidCallback> &&
              [
                const ValueKey('phone-workspace-more'),
                const ValueKey('note-workspace-more'),
                const ValueKey('workspace-more'),
              ].contains(widget.key),
        )
        .hitTestable();
    final adaptiveMenu = find.byType(MMAdaptiveToolbar).evaluate().where((element) {
      final toolbar = element.widget as MMAdaptiveToolbar;
      return toolbar.menuEntries.any((entry) => entry.key == ValueKey('workspace-command-$id')) ||
          toolbar.items.any((item) => item.menuEntry.key == ValueKey('workspace-command-$id'));
    });
    final noteMenu = find.byKey(const ValueKey('note-more')).hitTestable();
    final menu = noteMenu.evaluate().isNotEmpty
        ? noteMenu
        : dedicatedMenu.evaluate().isNotEmpty
        ? dedicatedMenu.first
        : find.byKey((adaptiveMenu.first.widget as MMAdaptiveToolbar).menuKey!).hitTestable();
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('workspace-command-$id')).hitTestable());
  }
  await tester.pumpAndSettle();
}

/// Opens (or closes) the style panel through the workspace More menu.
Future<void> toggleMapStyle(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('map-more')).hitTestable().first);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('map-style-menu')).hitTestable());
  await tester.pumpAndSettle();
}

/// Document management remains in More after removing the document title row.
Future<void> openReaderDocumentMenu(WidgetTester tester) async {
  final title = find.byKey(const ValueKey('reader-documents')).hitTestable();
  if (title.evaluate().isNotEmpty) {
    await tester.tap(title.first);
  } else {
    await tester.tap(find.byKey(const ValueKey('reader-more')).hitTestable().first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reader-switch-document')));
  }
  await tester.pumpAndSettle();
}

WorkspaceState referenceState(WidgetTester tester) {
  final target = tester.widget<WorkspaceCommandTarget>(find.byType(WorkspaceCommandTarget).last);
  return target.container.read(workspaceProvider(target.studySetId));
}

WorkspaceController referenceWorkspace(WidgetTester tester) {
  final target = tester.widget<WorkspaceCommandTarget>(find.byType(WorkspaceCommandTarget).last);
  return target.container.read(workspaceProvider(target.studySetId).notifier);
}

ProviderContainer referenceContainer(WidgetTester tester) =>
    tester.widget<WorkspaceCommandTarget>(find.byType(WorkspaceCommandTarget).last).container;
