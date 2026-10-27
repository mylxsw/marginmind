import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

import 'harness.dart';

void main() {
  testWidgets('checkbox and switch toggle; disabled ones do not', (tester) async {
    var checked = false;
    var on = true;
    await tester.pumpWidget(
      harness(
        StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MMCheckbox(value: checked, label: 'Split', onChanged: (v) => setState(() => checked = v)),
              MMCheckbox(value: true, semanticLabel: 'Fixed', onChanged: null, color: Colors.purple),
              MMSwitch(value: on, semanticLabel: 'Context', onChanged: (v) => setState(() => on = v)),
              const MMSwitch(value: false, semanticLabel: 'Off', onChanged: null),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Split'));
    await tester.pumpAndSettle();
    expect(checked, isTrue);
    expect(find.byIcon(MMIcons.check), findsNWidgets(2));
    await tester.tap(find.bySemanticsLabel('Context'));
    await tester.pumpAndSettle();
    expect(on, isFalse);
    await tester.tap(find.bySemanticsLabel('Off'));
    await tester.tap(find.bySemanticsLabel('Fixed'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('pills tint their label, or stay neutral', (tester) async {
    await tester.pumpWidget(
      harness(
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MMPill('Full text', color: Color(0xFF248A3D)),
            MMPill('External', icon: MMIcons.openExternal),
          ],
        ),
      ),
    );
    expect(tester.widget<Text>(find.text('Full text')).style!.color, const Color(0xFF248A3D));
    final context = tester.element(find.text('External'));
    expect(tester.widget<Text>(find.text('External')).style!.color, context.mmColors.secondaryLabel);
    expect(find.byIcon(MMIcons.openExternal), findsOneWidget);
  });

  testWidgets('a HUD with an action takes the click; without one it ignores pointers', (tester) async {
    var undone = 0;
    await tester.pumpWidget(
      harness(
        Builder(
          builder: (context) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MMButton(
                label: 'Save',
                onPressed: () => MMHud.show(context, 'Saved', action: ('Undo', () => undone++)),
              ),
              MMButton(label: 'Plain', onPressed: () => MMHud.show(context, 'Done')),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Undo'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(undone, 1);
    await tester.tap(find.text('Plain'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Undo'), findsNothing);
    final ignore = tester.widget<IgnorePointer>(
      find.ancestor(of: find.text('Done'), matching: find.byType(IgnorePointer)).first,
    );
    expect(ignore.ignoring, isTrue);
    await tester.pump(MMMotion.hud);
    await tester.pumpAndSettle();
  });

  testWidgets('menu headers are not selectable', (tester) async {
    String? picked;
    await tester.pumpWidget(
      harness(
        Builder(
          builder: (context) => MMButton(
            label: 'Open',
            onPressed: () => showMMMenu(
              context,
              position: const Offset(100, 100),
              entries: [
                const MMMenuHeader('Research “Node”'),
                MMMenuItem('Explain', () => picked = 'explain'),
                const MMMenuDivider(),
                MMMenuItem('Details', () => picked = 'details'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Research “Node”'), findsOneWidget);
    await tester.tap(find.text('Research “Node”'));
    await tester.pumpAndSettle();
    expect(picked, isNull);
    await tester.tap(find.text('Explain'));
    await tester.pumpAndSettle();
    expect(picked, 'explain');
  });

  testWidgets('text fields grow over lines, hide secrets and share a focus node', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final controller = TextEditingController(text: 'one\ntwo\nthree');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      harness(
        SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MMTextField(controller: controller, maxLines: 4, minLines: 1, focusNode: focus),
              const MMTextField(placeholder: 'Key', obscureText: true),
            ],
          ),
        ),
      ),
    );
    final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields.first.maxLines, 4);
    expect(fields.first.keyboardType, TextInputType.multiline);
    expect(fields.last.obscureText, isTrue);
    expect(tester.getSize(find.byType(MMTextField).first).height, greaterThan(MMSizes.field));
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);
  });

  testWidgets('a primary button and toolbar button can wear a feature color', (tester) async {
    const research = Color(0xFF5E5CE6);
    await tester.pumpWidget(
      harness(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MMButton(label: 'Start', variant: MMButtonVariant.primary, color: research, onPressed: () {}),
            MMToolbarButton(icon: MMIcons.research, tooltip: 'Research', tint: research, onPressed: () {}),
          ],
        ),
      ),
    );
    final box = tester.widget<Container>(
      find.descendant(of: find.byType(MMButton), matching: find.byType(Container)).first,
    );
    expect((box.decoration! as BoxDecoration).color, research);
    expect(tester.widget<Icon>(find.byIcon(MMIcons.research)).color, research);
  });

  test('status colors read on their own wash in both appearances', () {
    for (final c in [MMColors.light, MMColors.dark]) {
      final bg = c.brightness == Brightness.light ? const Color(0xFFFFFFFF) : const Color(0xFF2C2C2E);
      for (final status in [c.positive, c.caution, c.critical]) {
        expect(contrastRatio(status, composite(status.withValues(alpha: 0.12), bg)), greaterThan(3), reason: '$status');
      }
    }
    final mid = MMColors.light.lerp(MMColors.dark, 0.5);
    expect(mid.positive, Color.lerp(MMColors.light.positive, MMColors.dark.positive, 0.5));
    expect(MMColors.light.withAccent(Colors.red).critical, MMColors.light.critical);
  });
}
