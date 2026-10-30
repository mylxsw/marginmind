import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

void main() {
  for (final tablet in [false, true]) {
    testWidgets('${tablet ? 'tablet' : 'Mac'} control geometry and content typography', (t) async {
      var taps = 0;
      late BuildContext context;
      await t.pumpWidget(
        MaterialApp(
          theme: MMTheme.light(),
          home: MMInput(
            touchPlatform: tablet,
            child: Builder(
              builder: (c) {
                context = c;
                return Column(
                  children: [
                    MMButton(key: const ValueKey('button'), label: 'Save', onPressed: () => taps++),
                    MMIconButton(
                      key: const ValueKey('icon'),
                      icon: Icons.close,
                      tooltip: 'Close',
                      onPressed: () => taps++,
                    ),
                    MMSwitch(
                      key: const ValueKey('switch'),
                      value: true,
                      semanticLabel: 'Enabled',
                      onChanged: (_) => taps++,
                    ),
                    const MMSettingsRow(
                      label: 'Key',
                      trailing: MMTextField(key: ValueKey('field'), placeholder: 'Key'),
                    ),
                    MMSegmentedControl<int>(
                      segments: const [
                        MMSegment(value: 1, label: 'Source'),
                        MMSegment(value: 2, label: 'Map'),
                      ],
                      value: 1,
                      onChanged: (_) {},
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      expect(t.getSize(find.byKey(const ValueKey('button'))).height, tablet ? 44 : 30);
      expect(t.getSize(find.byKey(const ValueKey('icon'))).height, tablet ? 44 : 28);
      expect(t.getSize(find.byKey(const ValueKey('field'))).height, tablet ? 44 : 28);
      expect(t.getSize(find.byKey(const ValueKey('switch'))).height, tablet ? 44 : 16);
      expect(context.mmContentText.body.fontSize, 13);
      expect(context.mmText.body.fontSize, tablet ? 15 : 13);
      await t.tapAt(t.getBottomLeft(find.byKey(const ValueKey('button'))) + const Offset(4, -2));
      await t.pump();
      expect(taps, 1);
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(t.getCenter(find.byKey(const ValueKey('icon'))));
      await t.pumpAndSettle();
      expect(t.getSize(find.byKey(const ValueKey('icon'))).height, tablet ? 44 : 28);
      await mouse.removePointer();
    });
  }
}
