import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/map_pane.dart';
import 'package:marginmind/features/workspace/widgets/map_style_popover.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

void main() {
  for (final touch in [false, true]) {
    for (final width in [180.0, 360.0, 402.0, 435.0, 632.0]) {
      testWidgets('map toolbar actions remain reachable at $width pt (touch: $touch)', (tester) async {
        tester.view.physicalSize = const Size(800, 820);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: await testOverrides(),
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
        final style = find.byKey(const ValueKey('map-style-button'));
        await tester.ensureVisible(style);
        await tester.tap(style);
        await tester.pumpAndSettle();
        expect(find.byType(MapStylePopover), findsOneWidget);
        controller.setMapView(MapViewMode.outline);
        await tester.pumpAndSettle();
        expect(find.byType(MapStylePopover), findsNothing);
        final add = find.byTooltip('Add Topic');
        await tester.ensureVisible(add);
        await tester.tap(add);
        await tester.pumpAndSettle();
        expect(container.read(workspaceProvider('demo-1')).editingCardId, isNotNull);
        expect(tester.takeException(), isNull);
        await controller.cancelEditing();
        await settleHud(tester);
      });
    }
  }
}
