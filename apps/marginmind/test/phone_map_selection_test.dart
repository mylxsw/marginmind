import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/phone_map_selection.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_design/mm_design.dart';

void main() {
  test('a frame can shrink without losing earlier rounds; interrupt restores the previous frame', () {
    final selection = PhoneMapSelectionController()..begin({'old'});
    addTearDown(selection.dispose);
    final nodes = {'a': const Rect.fromLTWH(10, 10, 20, 20), 'b': const Rect.fromLTWH(50, 50, 20, 20)};
    selection.beginStroke(newFrame: true);
    selection.updateFrame(const Rect.fromLTWH(0, 0, 80, 80), nodes);
    expect(selection.selected, {'old', 'a', 'b'});
    selection.updateFrame(const Rect.fromLTWH(0, 0, 35, 35), nodes);
    expect(selection.selected, {'old', 'a'});
    selection.finishStroke();
    final before = selection.frame;
    selection.beginStroke(newFrame: true);
    selection.updateFrame(const Rect.fromLTWH(40, 40, 50, 50), nodes);
    expect(selection.selected, {'old', 'a', 'b'});
    selection.rollbackStroke();
    expect(selection.frame, before);
    expect(selection.selected, {'old', 'a'});
    selection.setMode(PhoneMapSelectionMode.box);
    expect(selection.frame, isNull);
    expect(selection.selected, {'old', 'a'});
    selection.toggle('a');
    expect(selection.selected, {'old'});
    selection.clear();
    expect(selection.selected, isEmpty);
    selection.cancel();
    expect(selection.active, isFalse);
  });

  for (final scale in [.5, 1.0, 2.0]) {
    testWidgets('phone frame persists, resizes, moves, accumulates and can be refined at zoom $scale', (tester) async {
      final h = await _pump(tester, scale: scale);
      h.selection.setMode(PhoneMapSelectionMode.box);
      await tester.pump();
      await _drag(tester, const Offset(45, 220), const Offset(135, 300));
      expect(h.selection.selected, {'a'});
      final frame = find.byKey(const ValueKey('phone-map-selection-frame'));
      expect(tester.getRect(frame), const Rect.fromLTRB(45, 220, 135, 300));
      for (final corner in ['topLeft', 'topRight', 'bottomLeft', 'bottomRight']) {
        expect(tester.getSize(find.byKey(ValueKey('phone-map-selection-handle-$corner'))), const Size(44, 44));
      }
      await _drag(tester, const Offset(135, 300), const Offset(75, 250));
      expect(h.selection.selected, isEmpty);
      await _drag(tester, const Offset(75, 250), const Offset(135, 300));
      expect(h.selection.selected, {'a'});
      // The midpoint of the edge moves the frame and replaces this round's candidates.
      await _drag(tester, const Offset(90, 220), const Offset(240, 380));
      expect(h.selection.selected, {'b'});
      await _drag(tester, const Offset(45, 525), const Offset(150, 600));
      expect(h.selection.selected, {'b', 'c'});
      h.selection.setMode(PhoneMapSelectionMode.tap);
      await tester.pump();
      expect(frame, findsNothing);
      await tester.tapAt(const Offset(255, 415));
      await tester.pumpAndSettle();
      expect(h.selection.selected, {'c'});
      await tester.tapAt(const Offset(30, 320));
      expect(h.selection.selected, {'c'}, reason: 'blank taps preserve the draft');
      expect(h.done, isEmpty);
      await tester.tap(find.byKey(const ValueKey('phone-map-selection-done')));
      await tester.pumpAndSettle();
      expect(h.done, [
        {'c'},
      ]);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android}));
  }

  testWidgets('second finger cancels the current stroke, then camera changes preserve the stored frame', (
    tester,
  ) async {
    final h = await _pump(tester);
    h.selection.setMode(PhoneMapSelectionMode.box);
    await tester.pump();
    await _drag(tester, const Offset(45, 220), const Offset(135, 300));
    final frame = h.selection.frame;
    final a = await tester.startGesture(const Offset(200, 350), pointer: 1);
    await a.moveTo(const Offset(300, 450));
    await tester.pump();
    expect(h.selection.selected, {'a', 'b'});
    final b = await tester.startGesture(const Offset(80, 200), pointer: 2);
    await tester.pump();
    expect(h.selection.selected, {'a'});
    expect(h.selection.frame, frame);
    for (var i = 0; i < 5; i++) {
      await a.moveBy(const Offset(10, 10));
      await b.moveBy(const Offset(-10, -10));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(h.transform.value.storage[0], greaterThan(1));
    expect(h.selection.frame, frame);
    expect(h.selection.selected, {'a'});
    expect(
      tester.getRect(find.byKey(const ValueKey('phone-map-selection-frame'))),
      MatrixUtils.transformRect(h.transform.value, frame!),
    );
    // System cancellation restores the whole pre-stroke state as well.
    final g = await tester.startGesture(const Offset(250, 500));
    await g.moveBy(const Offset(40, 70));
    await tester.pump();
    await g.cancel();
    await tester.pumpAndSettle();
    expect(h.selection.frame, frame);
    expect(h.selection.selected, {'a'});
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(h.selection.active, isFalse);
    expect(h.done, isEmpty);
  }, variant: TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android}));

  testWidgets('accessibility node actions refine the same draft as touch input', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final h = await _pump(tester);
      final node = tester.getSemantics(find.byKey(const ValueKey('phone-map-select-accessibility-a')));
      expect(node.getSemanticsData().label, 'a');
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(h.selection.selected, {'a'});
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(h.selection.selected, isEmpty);
      expect(h.done, isEmpty);
    } finally {
      semantics.dispose();
    }
  });

  for (final dark in [false, true]) {
    testWidgets('narrow and landscape controls remain reachable (dark: $dark)', (tester) async {
      await _pump(tester, dark: dark);
      for (final size in [const Size(320, 640), const Size(844, 390)]) {
        tester.view.physicalSize = size;
        tester.view.padding = size.width > size.height
            ? const FakeViewPadding(left: 44, right: 44, bottom: 21)
            : const FakeViewPadding(top: 44, bottom: 34);
        await tester.pumpAndSettle();
        for (final key in ['phone-map-selection-cancel', 'phone-map-selection-done', 'phone-map-selection-clear']) {
          final button = find.byKey(ValueKey(key));
          expect(button.hitTestable(), findsOneWidget);
          final bounds = tester.getRect(button);
          expect(bounds.left, greaterThanOrEqualTo(size.width > size.height ? 44 : 0));
          expect(bounds.right, lessThanOrEqualTo(size.width > size.height ? 800 : 320));
        }
        expect(tester.takeException(), isNull);
      }
    }, variant: TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android}));
  }

  testWidgets('holding a frame near the edge scrolls the canvas and extends the scene selection', (tester) async {
    final h = await _pump(tester, extra: {'far': const Rect.fromLTWH(80, 900, 50, 40)});
    h.selection.setMode(PhoneMapSelectionMode.box);
    await tester.pump();
    final g = await tester.startGesture(const Offset(45, 220));
    await g.moveTo(const Offset(145, 690));
    await tester.pump();
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(h.transform.value.storage[13], lessThan(0));
    expect(h.selection.frame!.bottom, greaterThan(690));
    expect(h.selection.selected, {'a', 'c', 'far'});
    await g.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

class _Harness {
  final selection = PhoneMapSelectionController();
  final transform = TransformationController();
  final done = <Set<String>>[];
}

Future<_Harness> _pump(
  WidgetTester tester, {
  double scale = 1,
  bool dark = false,
  Map<String, Rect> extra = const {},
}) async {
  final h = _Harness();
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(h.selection.dispose);
  addTearDown(h.transform.dispose);
  h.selection.begin({});
  h.transform.value = Matrix4.identity()..scaleByDouble(scale, scale, 1, 1);
  final nodes = {
    'a': Rect.fromLTWH(60 / scale, 240 / scale, 50 / scale, 30 / scale),
    'b': Rect.fromLTWH(230 / scale, 400 / scale, 50 / scale, 30 / scale),
    'c': Rect.fromLTWH(80 / scale, 550 / scale, 50 / scale, 30 / scale),
    ...extra,
  };
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? MMTheme.dark() : MMTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (_, child) => MMInput(touchPlatform: true, phone: true, child: child!),
      home: Scaffold(
        body: MMBackScope(
          child: PhoneMapSelectionLayer(
            controller: h.selection,
            transformation: h.transform,
            nodes: () => nodes,
            onDone: () {
              h.done.add(h.selection.selected);
              h.selection.cancel();
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return h;
}

Future<void> _drag(WidgetTester tester, Offset from, Offset to) async {
  final g = await tester.startGesture(from);
  await g.moveTo(to);
  await tester.pump();
  await g.up();
  await tester.pumpAndSettle();
}
