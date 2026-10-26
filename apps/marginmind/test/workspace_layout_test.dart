import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
import 'package:marginmind/features/workspace/widgets/reader_sidebar.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/settings/app_settings.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import 'reader_navigation_test.dart' show openReader;

void main() {
  testWidgets('outline is one line with full tooltip and resizing persists', (tester) async {
    final r = await openReader(tester);
    const title = '很长的章节标题：数字化转型的组织架构与管理流程，以及实际案例';
    r.pdf.debugReport(pageCount: 164, page: 24, outline: const [MMPdfOutlineItem(title: title, page: 20)]);
    r.controller.showReaderPanel(ReaderPanelMode.outline);
    await tester.pumpAndSettle();
    expect(r.container.read(workspaceProvider('demo-1')).sidebarVisible, isFalse);
    final text = tester.widget<Text>(find.text(title));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(find.byTooltip(title), findsOneWidget);
    final sidebar = find.byType(ReaderSidebar);
    final before = tester.getSize(sidebar).width;
    await tester.drag(find.byKey(const ValueKey('reader-sidebar-resize')), const Offset(50, 0));
    await tester.pumpAndSettle();
    final after = tester.getSize(sidebar).width;
    expect(after, greaterThan(before));
    expect(r.container.read(sharedPreferencesProvider).getDouble('settings.readerSidebarWidth'), after);
    r.controller.toggleReaderPanel();
    await tester.pumpAndSettle();
    r.controller.toggleReaderPanel();
    await tester.pumpAndSettle();
    expect(tester.getSize(sidebar).width, after);
    r.container.invalidate(settingsProvider);
    expect(r.container.read(settingsProvider).readerSidebarWidth, after);
    expect(tester.takeException(), isNull);
  });

  testWidgets('map retains viewport across document, outline and layout changes', (tester) async {
    final r = await openReader(tester);
    final canvas = tester.widget<MindMapCanvas>(find.byType(MindMapCanvas));
    expect(mapScale(canvas.transformation.value), 1);
    final saved = Matrix4.identity()
      ..translateByDouble(110, 190, 0, 1)
      ..scaleByDouble(.5, .5, 1, 1);
    canvas.transformation.value = saved;
    await tester.pumpAndSettle();
    r.controller.openDocument('c2');
    await tester.pumpAndSettle();
    expect(canvas.transformation.value, saved);
    r.controller.setMapView(MapViewMode.outline);
    await tester.pumpAndSettle();
    r.controller.setMapView(MapViewMode.map);
    await tester.pumpAndSettle();
    final restored = tester.widget<MindMapCanvas>(find.byType(MindMapCanvas));
    expect(restored.transformation.value, saved);
    r.controller.setLayout(MMSplitMode.primary);
    await tester.pumpAndSettle();
    r.controller.setLayout(MMSplitMode.split);
    await tester.pumpAndSettle();
    expect(restored.transformation.value, saved);
    await tester.tap(find.byTooltip('Actual Size').last);
    await tester.pumpAndSettle();
    expect(mapScale(restored.transformation.value), 1);
    await tester.tap(find.byTooltip('Show Entire Map'));
    await tester.pumpAndSettle();
    expect(mapScale(restored.transformation.value), lessThan(1));
    await tester.tap(find.byTooltip('Locate Selected Node'));
    await tester.pumpAndSettle();
    expect(mapScale(restored.transformation.value), 1);
  });
}
