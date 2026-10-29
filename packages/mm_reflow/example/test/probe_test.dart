import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_reflow/mm_reflow.dart';
import 'package:reflow_probe/main.dart';
import 'package:reflow_probe/l10n/probe_localizations.dart';

void main() {
  testWidgets(
    'benchmark completes both frame states and memory rounds on real EPUB',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: ProbeLocalizations.localizationsDelegates,
          supportedLocales: ProbeLocalizations.supportedLocales,
          home: const Probe(),
        ),
      );
      for (
        var i = 0;
        i < 100 && find.byType(ReflowSurface).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      final dynamic state = tester.state(find.byType(Probe));
      var done = false;
      Object? failure;
      final Future<void> run = state.benchmark(
        iterations: 1,
        pageChanges: 2,
        memoryRounds: 1,
        switchesPerRound: 2,
        settleDelay: Duration.zero,
        bookIndices: <int>[0],
      );
      run.then(
        (_) => done = true,
        onError: (Object e) {
          failure = e;
          done = true;
        },
      );
      for (var i = 0; i < 1000 && !done; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(done, isTrue);
      expect(failure, isNull);
      expect(state.failure, isNull);
      expect(state.busy, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

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
    final dynamic state = tester.state(find.byType(Probe));
    Future<void> settleLayout(bool Function() ready) async {
      for (var attempt = 0; attempt < 100 && !ready(); attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(ready(), isTrue);
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byTooltip('Chapter'));
    await settleLayout(() => state.chapter == 1);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Font size'));
    await settleLayout(() => state.layout.spec.fontSize == state.size);
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
