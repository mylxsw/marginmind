import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

void main() {
  for (final phone in [true, false]) {
    for (final dark in [false, true]) {
      testWidgets('floating material phone=$phone dark=$dark keeps a readable platform surface', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? MMTheme.dark() : MMTheme.light(),
            home: MMInput(
              touchPlatform: phone,
              phone: phone,
              child: const Center(
                child: SizedBox(width: 200, height: 60, child: MMLiquidGlass(child: Text('Reading'))),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Reading'), findsOneWidget);
        expect(find.byType(BackdropFilter), phone ? findsNothing : findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('phone opt-out cannot accidentally restore painted liquid rims', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: MMTheme.light(),
        home: const MMInput(
          touchPlatform: true,
          phone: true,
          child: MMFlatSurface(
            enabled: false,
            child: Center(
              child: SizedBox(
                width: 120,
                height: 44,
                child: MMLiquidGlass(phoneStyle: MMPhoneGlass.regular, child: Text('Tools')),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
