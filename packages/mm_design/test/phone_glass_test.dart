import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

Future<void> host(
  WidgetTester tester,
  Widget child, {
  bool dark = false,
  bool reduce = false,
  bool phone = true,
  bool touch = true,
}) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? MMTheme.dark() : MMTheme.light(),
      home: MMInput(
        touchPlatform: touch,
        phone: phone,
        child: MMAppearance(
          reduceTransparency: reduce,
          child: Material(child: child),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    if (Platform.environment['MM_SCREENSHOTS'] == null) return;
    final data = ByteData.sublistView(
      File(Platform.environment['MM_FONT'] ?? '/System/Library/Fonts/Supplemental/Arial Unicode.ttf').readAsBytesSync(),
    );
    for (final family in ['.AppleSystemUIFont', 'CupertinoSystemText', 'CupertinoSystemDisplay', 'Roboto']) {
      await (FontLoader(family)..addFont(Future.value(data))).load();
    }
  });
  for (final dark in [false, true]) {
    for (final style in MMPhoneGlass.values) {
      testWidgets('$style dark=$dark filters and opaque fallback', (tester) async {
        Widget glass({Color? opaque}) => Center(
          child: MMLiquidGlass(phoneStyle: style, opaqueColor: opaque, child: const SizedBox(width: 120, height: 56)),
        );
        await host(tester, glass(), dark: dark);
        expect(tester.widget<BackdropFilter>(find.byType(BackdropFilter)).filter, MMLiquidGlass.phoneFilter(style));
        final paints = tester
            .widgetList<CustomPaint>(
              find.descendant(of: find.byType(MMLiquidGlass), matching: find.byType(CustomPaint)),
            )
            .where((p) => p.foregroundPainter != null);
        expect(paints.single.foregroundPainter!.shouldRepaint(paints.single.foregroundPainter!), isFalse);
        List<Color> fills() => tester
            .widgetList<DecoratedBox>(find.byType(DecoratedBox))
            .map((w) => (w.decoration as BoxDecoration).color)
            .nonNulls
            .toList();
        expect(fills(), contains(style.fill(dark)));
        await host(tester, glass(), dark: dark, reduce: true);
        expect(find.byType(BackdropFilter), findsNothing);
        expect(fills(), contains(MMPhoneGlass.opaque(dark)));
        await host(tester, glass(opaque: Colors.red.withValues(alpha: .2)), dark: dark, reduce: true);
        expect(fills(), contains(Colors.red.withValues(alpha: 1)));
      });
    }
    testWidgets('393x852 phone materials ${dark ? 'dark' : 'light'}', (tester) async {
      if (Platform.environment['MM_SCREENSHOTS'] != null) {
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = true);
      }
      await host(
        tester,
        RepaintBoundary(
          key: const ValueKey('evidence'),
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: dark
                          ? [const Color(0xFF152B3C), const Color(0xFF372538)]
                          : [const Color(0xFFA9D8EF), const Color(0xFFF4D2AB)],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 64),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final style in MMPhoneGlass.values)
                      for (final reduce in [false, true])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 28),
                          child: MMAppearance(
                            reduceTransparency: reduce,
                            child: MMLiquidGlass(
                              phoneStyle: style,
                              borderRadius: BorderRadius.circular(MMRadii.phoneTabBar),
                              child: SizedBox(
                                height: MMSizes.phoneTabBarHeight,
                                child: Center(child: Text('${style.name}${reduce ? ' / opaque' : ''}')),
                              ),
                            ),
                          ),
                        ),
                    const Align(
                      child: MMLiquidGlass(
                        phoneStyle: MMPhoneGlass.regular,
                        borderRadius: BorderRadius.all(Radius.circular(25)),
                        child: SizedBox(
                          width: MMSizes.phoneToolOrb,
                          height: MMSizes.phoneToolOrb,
                          child: Center(child: Text('+')),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        dark: dark,
      );
      await expectLater(
        find.byKey(const ValueKey('evidence')),
        matchesGoldenFile(
          Platform.environment['MM_SCREENSHOTS'] == null
              ? 'goldens/phone_glass_${dark ? 'dark' : 'light'}.png'
              : '../../../docs/evidence/gul-630/phone-glass-${dark ? 'dark' : 'light'}.png',
        ),
      );
      debugDisableShadows = true;
    });
  }
  testWidgets('nested, flat and zero-blur surfaces avoid redundant filtering', (tester) async {
    const inner = MMLiquidGlass(phoneStyle: MMPhoneGlass.thick, child: Text('nested'));
    await host(
      tester,
      const Center(
        child: MMLiquidGlass(phoneStyle: MMPhoneGlass.regular, child: inner),
      ),
    );
    expect(find.byType(BackdropFilter), findsOneWidget);
    await host(tester, const MMFlatSurface(child: inner));
    expect(find.byType(BackdropFilter), findsNothing);
    await host(tester, const MMLiquidGlass(phoneStyle: MMPhoneGlass.regular, blurSigma: 0, child: Text('zero')));
    expect(find.byType(BackdropFilter), findsNothing);
  });
  testWidgets('iPad compact and desktop keep legacy surfaces', (tester) async {
    for (final touch in [true, false]) {
      await host(
        tester,
        const Center(child: MMGlass(child: Text('legacy'))),
        phone: false,
        touch: touch,
      );
      expect(find.byType(MMLiquidGlass), findsNothing);
      if (touch) {
        expect(find.byType(BackdropFilter), findsNothing);
      } else {
        expect(
          tester.widget<BackdropFilter>(find.byType(BackdropFilter)).filter,
          ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        );
      }
      await host(
        tester,
        const Center(child: MMLiquidGlass(child: Text('legacy'))),
        phone: false,
        touch: touch,
      );
      expect(tester.widget<BackdropFilter>(find.byType(BackdropFilter)).filter, MMLiquidGlass.liquidFilter(24));
    }
  });
}
