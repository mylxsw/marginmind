import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

import 'harness.dart';

void main() {
  testWidgets('settings group separates rows and shows a footer', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      harness(
        SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const MMSettingsHeader('Services'),
              MMSettingsGroup(
                footer: const Text('footer'),
                children: [
                  MMSettingsRow(label: 'Name', trailing: const Text('value')),
                  MMSettingsRow(
                    leading: const Text('custom'),
                    trailing: const Icon(MMIcons.chevronRight),
                    onTap: () => tapped++,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Services'), findsOneWidget);
    expect(find.text('footer'), findsOneWidget);
    expect(tester.getSize(find.ancestor(of: find.text('Name'), matching: find.byType(SizedBox)).first).height, 40);
    // The value sits at the right edge of its row.
    expect(
      tester.getRect(find.text('value')).right,
      closeTo(tester.getRect(find.byType(MMSettingsGroup)).right - 14, 1),
    );
    await tester.tap(find.text('custom'));
    expect(tapped, 1);
  });

  testWidgets('dark settings group uses a light wash', (tester) async {
    await tester.pumpWidget(harness(const MMSettingsGroup(children: [Text('row')]), brightness: Brightness.dark));
    final box = tester.widget<Container>(find.ancestor(of: find.text('row'), matching: find.byType(Container)).last);
    expect((box.decoration! as BoxDecoration).color, Colors.white.withValues(alpha: .05));
  });

  testWidgets('light settings group is a quaternary-fill panel without shadow', (tester) async {
    await tester.pumpWidget(harness(const MMSettingsGroup(children: [Text('row')])));
    final box = tester.widget<Container>(find.ancestor(of: find.text('row'), matching: find.byType(Container)).last);
    final decoration = box.decoration! as BoxDecoration;
    expect(decoration.color, MMColors.light.quaternaryFill);
    expect(decoration.boxShadow, isNull);
    expect(decoration.border, isNull);
  });

  testWidgets('pop-up button checks the current value and reports a choice', (tester) async {
    String? chosen;
    await tester.pumpWidget(
      harness(
        MMPopUpButton<String>(
          value: 'b',
          items: const [('a', 'Alpha'), ('b', 'Beta')],
          semanticLabel: 'Choice',
          onChanged: (v) => chosen = v,
        ),
      ),
    );
    expect(find.text('Beta'), findsOneWidget);
    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();
    // Scope the check to the interactive menu item, independent of nested
    // label/badge rows. The other choice must remain unchecked.
    final beta = find.text('Beta').last;
    expect(
      find.descendant(
        of: find.ancestor(of: beta, matching: find.byType(MMInteractive)).first,
        matching: find.byIcon(MMIcons.check),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.ancestor(of: find.text('Alpha'), matching: find.byType(MMInteractive)).first,
        matching: find.byIcon(MMIcons.check),
      ),
      findsNothing,
    );
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    expect(chosen, 'a');
  });

  testWidgets('pop-up button without items shows the placeholder and is disabled', (tester) async {
    await tester.pumpWidget(
      harness(MMPopUpButton<String>(value: null, items: const [], semanticLabel: 'Choice', onChanged: (_) {})),
    );
    expect(find.text('—'), findsOneWidget);
    await tester.tap(find.text('—'));
    await tester.pumpAndSettle();
    expect(find.byType(MMGlass), findsNothing);
  });

  testWidgets('plain text field has no fill and aligns right', (tester) async {
    await tester.pumpWidget(
      harness(
        SizedBox(
          width: 200,
          child: MMTextField(
            controller: TextEditingController(text: 'x'),
            plain: true,
            textAlign: TextAlign.right,
          ),
        ),
      ),
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.textAlign, TextAlign.right);
    final box = tester.widget<Container>(
      find.ancestor(of: find.byType(TextField), matching: find.byType(Container)).first,
    );
    expect(box.decoration, isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('settings input remains usable when narrowed and cannot focus while disabled ($brightness)', (
      tester,
    ) async {
      final controller = TextEditingController();
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      late StateSetter update;
      var enabled = true;
      var width = 500.0;
      await tester.pumpWidget(
        harness(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return SizedBox(
                width: width,
                child: MMSettingsGroup(
                  children: [
                    MMSettingsRow(
                      label: 'Account ID',
                      trailing: MMTextField.settings(
                        controller: controller,
                        focusNode: focus,
                        enabled: enabled,
                        placeholder: 'Enter Account ID',
                        semanticLabel: 'Account ID',
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          brightness: brightness,
        ),
      );
      final input = find.byType(MMTextField);
      BoxDecoration decoration() =>
          tester.widget<Container>(find.descendant(of: input, matching: find.byType(Container)).first).decoration!
              as BoxDecoration;
      expect(find.text('Enter Account ID'), findsOneWidget);
      expect(decoration().color, Colors.transparent);
      expect(decoration().border, Border.all(color: Colors.transparent));
      expect(tester.getSize(input).width, MMSizes.settingsFieldWidth);
      update(() => width = 240);
      await tester.pump();
      expect(tester.getSize(input).width, lessThan(MMSizes.settingsFieldWidth));
      await tester.tap(input);
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      expect(
        decoration().color,
        brightness == Brightness.light ? MMColors.light.quaternaryFill : MMColors.dark.quaternaryFill,
      );
      expect(decoration().border, Border.all(color: tester.element(input).mmColors.accent));
      await tester.enterText(input, 'account-123');
      expect(controller.text, 'account-123');
      update(() => enabled = false);
      await tester.pump();
      await tester.tap(input, warnIfMissed: false);
      await tester.pump();
      expect(focus.hasFocus, isFalse);
      expect(decoration().color, Colors.transparent);
      expect(controller.text, 'account-123');
      expect(tester.takeException(), isNull);
    });
  }
}
