import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/map_selection_bar.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_design/mm_design.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final root in [false, true]) {
      testWidgets('iPad node toolbar covers content (${brightness.name}, root: $root)', (tester) async {
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: brightness == Brightness.light ? MMTheme.light() : MMTheme.dark(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MMInput(
              touchPlatform: true,
              child: MMFlatSurface(
                child: Center(
                  child: RepaintBoundary(
                    key: boundaryKey,
                    child: SizedBox(
                      width: 600,
                      height: 100,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Row(
                            children: const [
                              Expanded(child: ColoredBox(color: Colors.black)),
                              Expanded(child: ColoredBox(color: Colors.white)),
                            ],
                          ),
                          Center(
                            child: MapNodeBar(
                              root: root,
                              onChild: () {},
                              onSibling: () {},
                              onNote: () {},
                              onImage: () {},
                              onRelation: () {},
                              onDelete: () {},
                              onEdit: () {},
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
        final rect = tester.getRect(find.byType(MapNodeBar));
        // Sample the capsule above the icons on opposite sides of the backdrop.
        final point = boundary.globalToLocal(Offset(rect.center.dx, rect.top + 6));
        final image = (await tester.runAsync(() => boundary.toImage()))!;
        final bytes = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
        final colors = brightness == Brightness.light ? MMColors.light : MMColors.dark;
        for (final dx in [-10, 10]) {
          final i = (point.dy.floor() * image.width + (point.dx + dx).floor()) * 4;
          final pixel = Color.fromARGB(
            bytes.getUint8(i + 3),
            bytes.getUint8(i),
            bytes.getUint8(i + 1),
            bytes.getUint8(i + 2),
          );
          expect(pixel.toARGB32(), colors.surface.toARGB32());
        }
        image.dispose();
        await tester.tap(find.byKey(const ValueKey('node-bar-edit')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
