import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

void main() {
  testWidgets('content toolbar ignores window gestures even inside window chrome', (tester) async {
    var clicks = 0;
    var zooms = 0;
    var drags = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: MMTheme.light(),
        home: MMWindowChrome(
          onTitleDoubleTap: () => zooms++,
          onDragStart: () => drags++,
          child: Scaffold(
            body: MMToolbar.content(
              semanticLabel: 'Reader',
              child: Row(
                children: [
                  MMToolbarButton(icon: MMIcons.sidebar, tooltip: 'Pages', onPressed: () => clicks++),
                  const Expanded(child: SizedBox()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final empty = tester.getCenter(find.byType(MMToolbar));
    await tester.dragFrom(empty, const Offset(80, 0), kind: PointerDeviceKind.mouse);
    await tester.tapAt(empty, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(empty, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(drags, 0);
    expect(zooms, 0);
    await tester.tap(find.byTooltip('Pages'), kind: PointerDeviceKind.mouse);
    expect(clicks, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sidebar header buttons respond immediately and leave title gestures on empty space', (tester) async {
    var clicks = 0;
    var zooms = 0;
    var drags = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: MMTheme.light(),
        home: MMWindowChrome(
          onTitleDoubleTap: () => zooms++,
          onDragStart: () => drags++,
          child: Scaffold(
            body: MMSidebar(
              topTrailing: MMIconButton(icon: MMIcons.sidebar, tooltip: 'Hide sidebar', onPressed: () => clicks++),
              children: const [],
            ),
          ),
        ),
      ),
    );
    final button = find.byTooltip('Hide sidebar');
    await tester.tap(button, kind: PointerDeviceKind.mouse);
    expect(clicks, 1, reason: 'a header button must not wait for the double-click timeout');
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(button, kind: PointerDeviceKind.mouse);
    expect(clicks, 2);
    await tester.pump(kDoubleTapTimeout);
    expect(zooms, 0);
    final title = tester.getCenter(button).translate(-100, 0);
    await tester.tapAt(title, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(title, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(zooms, 1);
    await tester.dragFrom(title, const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(drags, 1);
  });

  testWidgets('toolbar actions respond on release without waiting for a title double click', (tester) async {
    var opened = false;
    var zooms = 0;
    var leadingClicks = 0;
    var drags = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: MMTheme.light(),
        home: MMWindowScaffold(
          onTitleDoubleTap: () => zooms++,
          onDragStart: () => drags++,
          toolbar: MMToolbar(
            title: 'Study set',
            leading: MMIconButton(icon: MMIcons.sidebar, tooltip: 'Sidebar', onPressed: () => leadingClicks++),
            actions: [
              MMToolbarGroup(
                children: [
                  MMToolbarButton(
                    iconWidget: const MMAssistantIcon(),
                    tooltip: 'Assistant',
                    onPressed: () => opened = true,
                  ),
                ],
              ),
            ],
          ),
          body: const SizedBox(),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Assistant'), kind: PointerDeviceKind.mouse);
    var waited = 0;
    while (!opened && waited < 400) {
      await tester.pump(const Duration(milliseconds: 10));
      waited += 10;
    }
    debugPrint('Toolbar action callback delay: ${waited}ms');
    expect(waited, 0, reason: 'the title double-click recognizer must not delay a button click');
    await tester.pump(const Duration(milliseconds: 350));
    expect(zooms, 0);

    await tester.tap(find.byTooltip('Sidebar'), kind: PointerDeviceKind.mouse);
    expect(leadingClicks, 1);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.byTooltip('Sidebar'), kind: PointerDeviceKind.mouse);
    expect(leadingClicks, 2, reason: 'two quick button clicks must remain two separate actions');
    await tester.pump(const Duration(milliseconds: 350));
    expect(zooms, 0);

    final title = tester.getCenter(find.text('Study set'));
    await tester.tapAt(title, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(title, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(zooms, 1, reason: 'double-clicking the title must still zoom the window');

    await tester.dragFrom(title, const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(drags, 1, reason: 'dragging the title must still move the window');
  });
}
