import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

const _imageKey = ValueKey('assistant-image');
Widget _scene({bool thinking = false, bool reduce = false, bool tickers = true, bool animated = true}) => MaterialApp(
  home: MMAppearance(
    reduceMotion: reduce,
    child: TickerMode(
      enabled: tickers,
      child: Center(
        child: RepaintBoundary(
          key: _imageKey,
          child: MMAssistantIcon(size: 184, thinking: thinking, animated: animated),
        ),
      ),
    ),
  ),
);
Future<Uint8List> _pixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_imageKey));
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = (await image.toByteData())!.buffer.asUint8List();
    image.dispose();
    return data;
  }))!;
}

void main() {
  testWidgets('idle stays still; touch blinks without delaying parent action', (tester) async {
    var clicks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: GestureDetector(
            onTap: () => clicks++,
            child: const RepaintBoundary(key: _imageKey, child: MMAssistantIcon(size: 184)),
          ),
        ),
      ),
    );
    final idle = await _pixels(tester);
    await tester.pump(const Duration(seconds: 10));
    expect(await _pixels(tester), orderedEquals(idle));
    expect(tester.binding.hasScheduledFrame, isFalse);
    final touch = await tester.startGesture(tester.getCenter(find.byType(MMAssistantIcon)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 95));
    expect(await _pixels(tester), isNot(orderedEquals(idle)));
    await touch.up();
    expect(clicks, 1);
    await tester.pumpAndSettle();
    expect(await _pixels(tester), orderedEquals(idle));
  });
  testWidgets('hover follows pointer and settles back on exit', (tester) async {
    await tester.pumpWidget(_scene());
    final idle = await _pixels(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getTopRight(find.byType(MMAssistantIcon)) + const Offset(-8, 8));
    await tester.pumpAndSettle();
    expect(await _pixels(tester), isNot(orderedEquals(idle)));
    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(await _pixels(tester), orderedEquals(idle));
    await mouse.removePointer();
  });
  testWidgets('work moves only eyes and completion settles without a loop', (tester) async {
    await tester.pumpWidget(_scene(thinking: true));
    await tester.pump(const Duration(milliseconds: 300));
    final first = await _pixels(tester);
    await tester.pump(const Duration(milliseconds: 600));
    final next = await _pixels(tester);
    expect(next, isNot(orderedEquals(first)));
    expect(next.sublist(0, 184 * 55 * 4), orderedEquals(first.sublist(0, 184 * 55 * 4)));
    await tester.pumpWidget(_scene());
    await tester.pumpAndSettle();
    final settled = await _pixels(tester);
    await tester.pump(const Duration(seconds: 5));
    expect(await _pixels(tester), orderedEquals(settled));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
  testWidgets('reduced motion and static swatches suppress work and pointer motion', (tester) async {
    for (final reduce in [false, true]) {
      await tester.pumpWidget(_scene(thinking: true, reduce: reduce, animated: reduce));
      final before = await _pixels(tester);
      await tester.tap(find.byType(MMAssistantIcon));
      await tester.pump(const Duration(seconds: 2));
      expect(await _pixels(tester), orderedEquals(before));
      expect(tester.binding.hasScheduledFrame, isFalse);
    }
  });
  testWidgets('hidden and background icons stop ticking, then resume', (tester) async {
    await tester.pumpWidget(_scene(thinking: true));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(_scene(thinking: true, tickers: false));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(_scene(thinking: true));
    await tester.pump(const Duration(milliseconds: 300));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    final paused = await _pixels(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(await _pixels(tester), orderedEquals(paused));
    expect(tester.binding.hasScheduledFrame, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(await _pixels(tester), isNot(orderedEquals(paused)));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  testWidgets('rapid interruptions dispose cleanly', (tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pumpWidget(_scene(thinking: i.isEven));
      await tester.tap(find.byType(MMAssistantIcon));
      await tester.pump(const Duration(milliseconds: 45));
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  final preview = Platform.environment['MM_ASSISTANT_MOTION_PREVIEW'];
  testWidgets('export native animation preview', (tester) async {
    final dir = Directory(preview!);
    dir.createSync(recursive: true);
    final font = Platform.environment['MM_FONT'];
    if (font != null) {
      await tester.runAsync(
        () => (FontLoader(
          'MotionPreview',
        )..addFont(Future.value(ByteData.sublistView(File(font).readAsBytesSync())))).load(),
      );
    }
    final working = ValueNotifier(true);
    addTearDown(working.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: _imageKey,
            child: ColoredBox(
              color: const Color(0xFFF5F6F8),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: ValueListenableBuilder(
                  valueListenable: working,
                  builder: (context, value, _) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (palette, label) in [
                        (MMAssistantPalette.iris, '蓝紫'),
                        (MMAssistantPalette.jade, '湖绿'),
                        (MMAssistantPalette.apricot, '杏橙'),
                      ])
                        SizedBox(
                          width: 200,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              MMAssistantIcon(size: 112, palette: palette, thinking: value),
                              const SizedBox(height: 22),
                              Text(
                                '$label · ${value ? "思考中" : "完成"}',
                                style: const TextStyle(
                                  inherit: false,
                                  fontFamily: 'MotionPreview',
                                  fontSize: 18,
                                  color: Color(0xFF28303B),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 88; i++) {
      if (i == 63) working.value = false;
      await tester.pump(const Duration(milliseconds: 50));
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_imageKey));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1.5);
        final png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
        await File('${dir.path}/frame-${i.toString().padLeft(3, '0')}.png').writeAsBytes(png);
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }, skip: preview == null);
}
