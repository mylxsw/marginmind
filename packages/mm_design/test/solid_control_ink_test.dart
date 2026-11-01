import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('solid controls share white-first ink in every theme; dark=$dark', (tester) async {
      for (final (accent, ink) in [
        (const Color(0xFF007AFF), Colors.white),
        (const Color(0xFF0A84FF), Colors.white),
        (const Color(0xFF3B78F9), Colors.white),
        (const Color(0xFFAF52DE), Colors.white),
        (const Color(0xFFFFCC00), Colors.black),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? MMTheme.dark(systemAccent: accent) : MMTheme.light(systemAccent: accent),
            home: Scaffold(
              body: Builder(
                builder: (context) => Wrap(
                  children: [
                    MMButton(label: 'Primary', variant: MMButtonVariant.primary, icon: MMIcons.check, onPressed: () {}),
                    MMButton(
                      label: 'AI',
                      variant: MMButtonVariant.primary,
                      color: context.mmColors.research,
                      foregroundColor: context.mmColors.onResearch,
                      onPressed: () {},
                    ),
                    FilledButton(onPressed: () {}, child: const Text('Material')),
                    const MMCheckbox(value: true, semanticLabel: 'Included', onChanged: null),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final text in ['Primary', 'AI']) {
          expect(tester.widget<Text>(find.text(text)).style!.color, ink);
        }
        expect(DefaultTextStyle.of(tester.element(find.text('Material'))).style.color, ink);
        for (final icon in tester.widgetList<Icon>(find.byIcon(MMIcons.check))) {
          expect(icon.color, ink);
        }
        expect(tester.takeException(), isNull);
      }
    });
  }
}
