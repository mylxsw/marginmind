import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_reflow/mm_reflow.dart';
import 'package:reflow_probe/main.dart';
import 'package:reflow_probe/l10n/probe_localizations.dart';

void main() {
  testWidgets('real EPUB chapter switch does not hit a disposed painter', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: ProbeLocalizations.localizationsDelegates,
        supportedLocales: ProbeLocalizations.supportedLocales,
        home: const Probe(),
      ),
    );
    Future<void> settleLoad() async {
      for (var attempt = 0; attempt < 100; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (find.byType(ReflowSurface).evaluate().isNotEmpty) return;
      }
      fail('EPUB did not load');
    }

    await settleLoad();
    await tester.tap(find.byTooltip('Chapter'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Font size'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(ReflowSurface), findsOneWidget);
    for (final control in ['Next', 'Previous', 'Scroll', 'Scroll']) {
      await tester.tap(find.byTooltip(control));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    final origin = tester.getTopLeft(find.byType(ReflowSurface));
    final drag = await tester.startGesture(origin + const Offset(40, 40));
    await drag.moveTo(origin + const Offset(140, 40));
    await drag.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
