import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

void main() {
  testWidgets('iPad toolbar families share compact cells with separate edge hit targets', (t) async {
    final taps = <String>[];
    List<Widget> buttons(String kind) => [
      for (final id in ['a', 'b'])
        MMToolbarButton(
          key: ValueKey('$kind-$id'),
          icon: MMIcons.add,
          tooltip: '$kind-$id',
          onPressed: () => taps.add('$kind-$id'),
        ),
    ];
    final adaptive = buttons('adaptive');
    await t.pumpWidget(
      MaterialApp(
        theme: MMTheme.light(),
        home: MMInput(
          touchPlatform: true,
          child: Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MMToolbarGroup(key: const ValueKey('group'), children: buttons('group')),
                MMFloatingToolbar(key: const ValueKey('floating'), children: buttons('floating')),
                SizedBox(
                  width: 180,
                  height: 52,
                  child: MMAdaptiveToolbar(
                    menuLabel: 'More',
                    groups: const [
                      {'a', 'b'},
                    ],
                    items: [
                      for (var i = 0; i < 2; i++)
                        MMToolbarItem(
                          id: i == 0 ? 'a' : 'b',
                          child: adaptive[i],
                          menuEntry: MMDropdownItem<VoidCallback>(value: () {}, child: Text('Command $i')),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    for (final kind in ['group', 'floating', 'adaptive']) {
      final a = t.getRect(find.byKey(ValueKey('$kind-a')));
      final b = t.getRect(find.byKey(ValueKey('$kind-b')));
      expect(a.size, const Size(44, 44));
      expect(b.left, a.right);
      await t.tapAt(a.topRight + const Offset(-1, 2));
      await t.tapAt(b.topLeft + const Offset(1, 2));
      expect(taps.sublist(taps.length - 2), ['$kind-a', '$kind-b']);
    }
    expect(t.getSize(find.byKey(const ValueKey('group'))), t.getSize(find.byKey(const ValueKey('floating'))));
    expect(t.takeException(), isNull);
  });

  for (final tablet in [false, true]) {
    for (final dark in [false, true]) {
      testWidgets('${tablet ? 'ipad' : 'mac'} ${dark ? 'dark' : 'light'}', (t) async {
        final key = GlobalKey();
        var taps = 0;
        await t.pumpWidget(
          MaterialApp(
            theme: dark ? MMTheme.dark() : MMTheme.light(),
            home: MMInput(
              touchPlatform: tablet,
              child: Center(
                child: RepaintBoundary(
                  key: key,
                  child: Builder(
                    builder: (context) => Container(
                      width: 760,
                      height: 220,
                      padding: const EdgeInsets.all(16),
                      color: context.mmColors.windowBackground,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MMToolbarGroup(
                            children: [
                              MMToolbarButton(
                                key: const ValueKey('density-source'),
                                icon: MMIcons.document,
                                tooltip: 'Source',
                                onPressed: () => taps++,
                                selected: true,
                              ),
                              MMToolbarButton(icon: MMIcons.compare, tooltip: 'Split', onPressed: () {}),
                              MMToolbarButton(icon: MMIcons.mindMap, tooltip: 'Map', onPressed: () {}),
                            ],
                          ),
                          const SizedBox(height: 12),
                          MMToolbarGroup(
                            children: [
                              MMSegmentedControl<int>(
                                segments: const [
                                  MMSegment(value: 0, label: 'Map'),
                                  MMSegment(value: 1, label: 'Outline'),
                                ],
                                value: 0,
                                onChanged: (_) {},
                              ),
                              MMToolbarButton(
                                icon: MMIcons.mapStyle,
                                label: 'Style',
                                tooltip: 'Style',
                                onPressed: () {},
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              MMButton(label: 'Save', onPressed: () {}),
                              MMIconButton(icon: MMIcons.close, tooltip: 'Close', onPressed: () {}),
                            ],
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
        await t.pumpAndSettle();
        final source = find.byKey(const ValueKey('density-source'));
        expect(t.getSize(source).height, tablet ? 44 : 30);
        expect(
          t.getSize(find.descendant(of: source, matching: find.byType(AnimatedContainer)).first).height,
          tablet ? 32 : 30,
        );
        final captureDirectory = Platform.environment['MM_VISUAL_CAPTURE_DIR'];
        if (!tablet || captureDirectory != null) {
          final picture = (await t.runAsync(
            () => (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 2),
          ))!;
          // Keep strict baselines per host renderer, as in note_rich_export_test.
          if (!tablet) {
            final directory = Platform.isLinux ? 'goldens/linux' : 'goldens';
            await expectLater(picture, matchesGoldenFile('$directory/mac-controls-${dark ? 'dark' : 'light'}.png'));
          }
          if (captureDirectory != null) {
            await t.runAsync(() async {
              final data = await picture.toByteData(format: ui.ImageByteFormat.png);
              final out = Directory(captureDirectory);
              await out.create(recursive: true);
              await File('${out.path}/${tablet ? 'ipad' : 'mac'}-${dark ? 'dark' : 'light'}.png')
                  .writeAsBytes(data!.buffer.asUint8List());
            });
          }
          picture.dispose();
        }
        // The touch cell extends beyond its painted capsule without sharing a neighbour's target.
        await t.tapAt(t.getBottomLeft(source) + const Offset(2, -2));
        await t.pumpAndSettle();
        expect(taps, 1);
        expect(t.takeException(), isNull);
      });
    }
  }
  testWidgets('tablet dropdown preserves button accessibility and touch target', (t) async {
    final semantics = t.ensureSemantics();
    try {
      await t.pumpWidget(
        MaterialApp(
          theme: MMTheme.light(),
          home: MMInput(
            touchPlatform: true,
            child: Material(
              child: Center(
                child: MMDropdownButton<int>(
                  tooltip: 'More',
                  icon: const Icon(MMIcons.more),
                  itemBuilder: (_) => const [MMDropdownItem(value: 1, child: Text('Command'))],
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final more = find.byTooltip('More');
      expect(t.getSemantics(more).getSemanticsData().flagsCollection.isButton, isTrue);
      expect(t.getSize(more), const Size(44, 44));
      await t.tapAt(t.getBottomLeft(more) + const Offset(2, -2));
      await t.pumpAndSettle();
      expect(find.text('Command'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });
}
