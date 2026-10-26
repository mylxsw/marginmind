import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

import 'harness.dart';

void main() {
  group('placeFloatingToolbar', () {
    const viewport = Rect.fromLTWH(0, 0, 800, 600);
    const size = Size(220, 36);
    const margin = MMSpacing.s;
    const gap = MMSpacing.s;

    MMFloatingPlacement place(Rect anchor, {Size size = size, Rect viewport = viewport}) =>
        placeFloatingToolbar(anchor: anchor, size: size, viewport: viewport);

    /// Fully visible inside the margin, and clear of the anchor.
    void expectVisible(MMFloatingPlacement p, Rect anchor) {
      final rect = p.offset & size;
      final bounds = viewport.deflate(margin);
      expect(rect.left, greaterThanOrEqualTo(bounds.left), reason: '$rect');
      expect(rect.top, greaterThanOrEqualTo(bounds.top), reason: '$rect');
      expect(rect.right, lessThanOrEqualTo(bounds.right), reason: '$rect');
      expect(rect.bottom, lessThanOrEqualTo(bounds.bottom), reason: '$rect');
      expect(rect.overlaps(anchor), isFalse, reason: '$rect overlaps $anchor');
    }

    test('avoids another floating control by switching sides', () {
      const anchor = Rect.fromLTWH(300, 300, 200, 20);
      // The pill sits where the toolbar would go above the anchor.
      const pill = Rect.fromLTWH(300, 250, 200, 36);
      final p = placeFloatingToolbar(anchor: anchor, size: size, viewport: viewport, avoid: pill);
      expect(p.side, MMFloatingSide.below);
      expect((p.offset & size).overlaps(pill), isFalse);
      // Clear of the pill: the usual placement stays.
      expect(
        placeFloatingToolbar(anchor: anchor, size: size, viewport: viewport, avoid: const Rect.fromLTWH(0, 560, 100, 30)),
        place(anchor),
      );
    });

    test('goes above when both sides touch the avoided area', () {
      const anchor = Rect.fromLTWH(300, 300, 200, 20);
      const wide = Rect.fromLTWH(0, 200, 800, 300);
      final p = placeFloatingToolbar(anchor: anchor, size: size, viewport: viewport, avoid: wide);
      expect(p.side, MMFloatingSide.above);
      expect(p.offset.dy, 300 - gap - 36);
    });

    test('sits centered above a selection in the middle', () {
      const anchor = Rect.fromLTWH(300, 300, 200, 20);
      final p = place(anchor);
      const expected = MMFloatingPlacement(Offset(290, 300 - gap - 36), MMFloatingSide.above);
      expect(p, expected);
      expect(p.hashCode, expected.hashCode);
      expect(p.toString(), contains('above'));
      expectVisible(p, anchor);
    });

    test('moves below a selection near the top edge', () {
      const anchor = Rect.fromLTWH(300, 12, 200, 20);
      final p = place(anchor);
      expect(p.side, MMFloatingSide.below);
      expect(p.offset.dy, anchor.bottom + gap);
      expectVisible(p, anchor);
    });

    test('stays above a selection near the bottom edge', () {
      const anchor = Rect.fromLTWH(300, 570, 200, 22);
      // No room below (592 + gap + 36 > 592): must not be pushed off the bottom.
      expect(anchor.bottom + gap + size.height, greaterThan(600 - margin));
      final p = place(anchor);
      expect(p, const MMFloatingPlacement(Offset(290, 570 - gap - 36), MMFloatingSide.above));
      expectVisible(p, anchor);
    });

    test('is pushed inwards near the left and right edges', () {
      const left = Rect.fromLTWH(0, 300, 40, 20);
      final l = place(left);
      expect(l.offset.dx, margin);
      expectVisible(l, left);

      const right = Rect.fromLTWH(770, 300, 30, 20);
      final r = place(right);
      expect(r.offset.dx, 800 - margin - size.width);
      expectVisible(r, right);
    });

    test('is fully visible in all four corners', () {
      final corners = {
        'top left': const Rect.fromLTWH(0, 0, 60, 20),
        'top right': const Rect.fromLTWH(740, 0, 60, 20),
        'bottom left': const Rect.fromLTWH(0, 580, 60, 20),
        'bottom right': const Rect.fromLTWH(740, 580, 60, 20),
      };
      for (final MapEntry(key: name, value: anchor) in corners.entries) {
        final p = place(anchor);
        expect(p.side, name.startsWith('top') ? MMFloatingSide.below : MMFloatingSide.above, reason: name);
        expectVisible(p, anchor);
      }
    });

    test('overlaps a selection taller than the viewport instead of leaving it', () {
      const anchor = Rect.fromLTWH(100, -40, 400, 700);
      final p = place(anchor);
      final rect = p.offset & size;
      expect(viewport.deflate(margin).contains(rect.topLeft), isTrue);
      expect(viewport.deflate(margin).contains(rect.bottomRight), isTrue);
    });

    test('picks the roomier side when neither fits', () {
      const lowAnchor = Rect.fromLTWH(100, 30, 400, 550);
      expect(place(lowAnchor).side, MMFloatingSide.above);
      const highAnchor = Rect.fromLTWH(100, 20, 400, 550);
      expect(place(highAnchor).side, MMFloatingSide.below);
    });

    test('stays on screen when the selection scrolls out of view', () {
      final above = place(const Rect.fromLTWH(300, -200, 200, 20));
      expect(above.offset.dy, margin);
      final below = place(const Rect.fromLTWH(300, 900, 200, 20));
      expect(below.offset.dy, 600 - margin - size.height);
    });

    test('keeps the left edge when the toolbar is wider than the viewport', () {
      final p = place(
        const Rect.fromLTWH(50, 100, 20, 20),
        size: const Size(300, 36),
        viewport: const Rect.fromLTWH(0, 0, 200, 300),
      );
      expect(p.offset.dx, margin);
    });

    test('respects the viewport origin', () {
      const offsetViewport = Rect.fromLTWH(100, 50, 400, 300);
      final p = place(const Rect.fromLTWH(100, 50, 20, 20), viewport: offsetViewport);
      expect(p.offset, const Offset(100 + margin, 50 + 20 + gap));
    });
  });

  Widget toolbar({
    VoidCallback? onCopy,
    VoidCallback? onNote,
    ValueChanged<MMAnnotationColor>? onColor,
    MMAnnotationColor? selected,
    bool colorsEnabled = true,
  }) => MMFloatingToolbar(
    children: [
      for (final color in MMAnnotationColor.values)
        MMFloatingToolbarColor(
          color: color,
          tooltip: color.name,
          selected: color == selected,
          onPressed: colorsEnabled ? () => onColor?.call(color) : null,
        ),
      const MMToolbarDivider(),
      MMToolbarButton(icon: MMIcons.copy, tooltip: 'Copy', onPressed: onCopy ?? () {}),
      MMToolbarButton(icon: MMIcons.addNote, tooltip: 'Add Note', onPressed: onNote ?? () {}),
    ],
  );

  for (final brightness in Brightness.values) {
    testWidgets('renders on glass in ${brightness.name} appearance', (tester) async {
      await tester.pumpWidget(harness(toolbar(selected: MMAnnotationColor.blue), brightness: brightness));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final colors = brightness == Brightness.light ? MMColors.light : MMColors.dark;
      final fills = tester
          .widgetList<DecoratedBox>(find.descendant(of: find.byType(MMGlass), matching: find.byType(DecoratedBox)))
          .map((b) => (b.decoration as BoxDecoration).color);
      expect(fills, contains(colors.glass));
      for (final icon in [MMIcons.copy, MMIcons.addNote]) {
        expect(tester.widget<Icon>(find.byIcon(icon)).color, colors.label);
      }
      // Fully faded in.
      expect(tester.widget<Opacity>(find.byType(Opacity).first).opacity, 1);
    });
  }

  testWidgets('every item shows its tooltip on hover and is named for screen readers', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(harness(toolbar()));
    await tester.pumpAndSettle();
    final labels = [for (final c in MMAnnotationColor.values) c.name, 'Copy', 'Add Note'];
    expect(find.byType(MMInteractive), findsNWidgets(labels.length));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    for (final label in labels) {
      final item = find.bySemanticsLabel(label);
      expect(item, findsOneWidget, reason: label);
      await mouse.moveTo(tester.getCenter(item));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(label), findsOneWidget, reason: label);
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }
    semantics.dispose();
  });

  testWidgets('keyboard moves focus through the items and activates them', (tester) async {
    final picked = <MMAnnotationColor>[];
    var copied = 0;
    await tester.pumpWidget(harness(toolbar(onColor: picked.add, onCopy: () => copied++)));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(picked, [MMAnnotationColor.yellow]);

    // The focused dot gets an accent ring.
    final dot = tester
        .widgetList<Container>(
          find.descendant(of: find.byType(MMFloatingToolbarColor).first, matching: find.byType(Container)),
        )
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => d.shape == BoxShape.circle);
    expect(dot.boxShadow?.first.color, MMColors.light.accent);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(picked, [MMAnnotationColor.yellow, MMAnnotationColor.green]);

    for (var i = 0; i < MMAnnotationColor.values.length - 1; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    }
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(copied, 1);
  });

  testWidgets('disabled color dots ignore taps and skip focus', (tester) async {
    final picked = <MMAnnotationColor>[];
    var copied = 0;
    await tester.pumpWidget(harness(toolbar(onColor: picked.add, onCopy: () => copied++, colorsEnabled: false)));
    await tester.tap(find.byType(MMFloatingToolbarColor).first);
    expect(picked, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(copied, 1);
  });

  testWidgets('the selected dot gets a ring of its own color', (tester) async {
    await tester.pumpWidget(harness(toolbar(selected: MMAnnotationColor.purple)));
    final rings = tester
        .widgetList<Container>(
          find.descendant(of: find.byType(MMFloatingToolbarColor), matching: find.byType(Container)),
        )
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.shape == BoxShape.circle && d.boxShadow != null)
        .toList();
    expect(rings, hasLength(1));
    expect(rings.single.boxShadow!.first.color, MMAnnotationColor.purple.color);
  });

  testWidgets('a glass gap separates the selected dot from its ring', (tester) async {
    await tester.pumpWidget(harness(toolbar(selected: MMAnnotationColor.purple)));
    await tester.pumpAndSettle();
    final dot = find.descendant(
      of: find.byWidgetPredicate((w) => w is MMFloatingToolbarColor && w.selected),
      matching: find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).shape == BoxShape.circle,
      ),
    );
    final (gap, ring) = await dotRingColors(tester, dot);
    expect(gap, sameColor(MMColors.light.glassOpaque));
    expect(ring, sameColor(MMAnnotationColor.purple.color));
  });

  group('MMFloatingToolbarLayout', () {
    Future<void> pumpLayout(WidgetTester tester, Rect anchor, {VoidCallback? onBackground}) => tester.pumpWidget(
      MaterialApp(
        theme: MMTheme.light(),
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 600,
            height: 400,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onBackground),
                ),
                Positioned.fill(
                  child: MMFloatingToolbarLayout(
                    anchor: anchor,
                    padding: const EdgeInsets.only(top: MMSizes.toolbarHeight),
                    child: toolbar(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    testWidgets('places the toolbar above the anchor and follows it', (tester) async {
      const anchor = Rect.fromLTWH(200, 200, 160, 20);
      await pumpLayout(tester, anchor);
      final first = tester.getRect(find.byType(MMFloatingToolbar));
      expect(first.bottom, anchor.top - MMSpacing.s);
      expect(first.center.dx, closeTo(anchor.center.dx, 0.01));

      // Near the top, under the window toolbar: flips below.
      const high = Rect.fromLTWH(200, 70, 160, 20);
      await pumpLayout(tester, high);
      final flipped = tester.getRect(find.byType(MMFloatingToolbar));
      expect(flipped.top, high.bottom + MMSpacing.s);

      // Against the right edge: pushed inwards.
      const right = Rect.fromLTWH(560, 300, 40, 20);
      await pumpLayout(tester, right);
      expect(tester.getRect(find.byType(MMFloatingToolbar)).right, 600 - MMSpacing.s);
    });

    testWidgets('lets clicks outside the toolbar reach the content', (tester) async {
      var background = 0;
      await pumpLayout(tester, const Rect.fromLTWH(200, 200, 160, 20), onBackground: () => background++);
      await tester.tapAt(const Offset(20, 380));
      expect(background, 1);
      await tester.tap(find.byIcon(MMIcons.copy));
      expect(background, 1);
    });
  });
}
