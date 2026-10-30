import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/map_pane.dart';
import 'package:marginmind/features/workspace/widgets/map_selection_bar.dart';
import 'package:marginmind/features/workspace/widgets/map_style_popover.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

void main() {
  for (final touch in [false, true]) {
    for (final (width, height) in [
      for (final width in [180.0, 360.0, 402.0, 435.0, 632.0, 800.0, 960.0])
        for (final height in [240.0, 820.0]) (width, height),
    ]) {
      testWidgets('map toolbar actions remain reachable at $width × $height pt (touch: $touch)', (tester) async {
        tester.view.physicalSize = const Size(1200, 820);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [...await testOverrides(), mapCommandBarVisibleProvider.overrideWithValue(true)],
            child: MaterialApp(
              theme: MMTheme.light(),
              builder: (context, child) => MMInput(
                touchPlatform: touch,
                child: MMHudHost(child: child!),
              ),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: const MapPane(studySetId: 'demo-1'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final pane = find.byType(MapPane);
        final container = ProviderScope.containerOf(tester.element(pane));
        final controller = container.read(workspaceProvider('demo-1').notifier);
        expect(find.byType(MapCommandBar), findsOneWidget);
        for (final action in ['child', 'sibling', 'relation', 'summary', 'note', 'image', 'tags', 'details']) {
          await tester.ensureVisible(find.byKey(ValueKey('map-command-$action')));
          expect(tester.takeException(), isNull);
        }
        final style = find.byKey(const ValueKey('map-style-button'));
        await tester.ensureVisible(style);
        final commands = tester.getRect(find.byType(MapCommandBar));
        final styleRect = tester.getRect(style);
        if (width >= 800 && !touch) {
          expect(commands.center.dy, closeTo(styleRect.center.dy, 0.01));
          expect(commands.right, lessThanOrEqualTo(styleRect.left));
        }
        await tester.tap(style);
        await tester.pumpAndSettle();
        expect(find.byType(MapStylePopover), findsOneWidget);
        // The longer node menu scrolls inside even a narrow pane.
        await tester.tap(style);
        await tester.pumpAndSettle();
        controller.selectCard('c6');
        await tester.pumpAndSettle();
        expect(find.byTooltip('Remove from Map'), findsNothing);
        final nodeDelete = find.byKey(const ValueKey('node-bar-delete'));
        await tester.ensureVisible(nodeDelete);
        await tester.tap(nodeDelete);
        await tester.pumpAndSettle();
        expect(controller.content.node('c6'), isNull);
        await controller.undo();
        await tester.pumpAndSettle();
        controller.selectMapRoot();
        await controller.addTopicAndEdit('New topic', asChild: true);
        await tester.pumpAndSettle();
        final created = container.read(workspaceProvider('demo-1')).editingCardId!;
        final local = tester.getRect(find.byType(MapNodeBar));
        final node = tester.getRect(find.byKey(ValueKey(created)));
        expect(local.overlaps(tester.getRect(find.byType(MapCommandBar))), isFalse);
        expect(local.overlaps(node), isFalse);
        expect(local.bottom, lessThanOrEqualTo(height));
        expect(node.bottom, lessThanOrEqualTo(height));
        await controller.cancelEditing();
        await tester.pumpAndSettle();
        await tester.ensureVisible(style);
        await tester.tap(style);
        await tester.pumpAndSettle();
        controller.setMapView(MapViewMode.outline);
        await tester.pumpAndSettle();
        expect(find.byType(MapStylePopover), findsNothing);
        controller.selectCard('c6');
        await tester.pumpAndSettle();
        final remove = find.byTooltip('Remove from Map');
        await tester.ensureVisible(remove);
        await tester.tap(remove);
        await tester.pumpAndSettle();
        expect(controller.content.node('c6'), isNull);
        expect(tester.takeException(), isNull);
        await settleHud(tester);
      });
    }
  }
}
