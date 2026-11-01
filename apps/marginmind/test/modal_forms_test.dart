import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/notices.dart';
import 'package:marginmind/shared/l10n.dart';
import 'package:mm_design/mm_design.dart';

Future<BuildContext> host(
  WidgetTester tester, {
  bool dark = false,
  bool phone = false,
  Size size = const Size(1000, 700),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late BuildContext context;
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: dark ? MMTheme.dark() : MMTheme.light(),
      builder: (_, child) => MMInput(touchPlatform: phone, phone: phone, child: child!),
      home: Scaffold(
        body: Builder(
          builder: (c) {
            context = c;
            return const SizedBox.expand();
          },
        ),
      ),
    ),
  );
  return context;
}

Future<void> capture(WidgetTester tester, String name) async {
  final out = Platform.environment['MM_SCREENSHOTS'];
  if (out == null) return;
  final previous = debugDisableShadows;
  debugDisableShadows = false;
  void repaint(RenderObject object) {
    object.markNeedsPaint();
    object.visitChildren(repaint);
  }

  repaint(tester.binding.renderViews.first);
  await tester.pump();
  try {
    await tester.runAsync(() async {
      final view = tester.binding.renderViews.first;
      final image = await (view.debugLayer! as OffsetLayer).toImage(Offset.zero & view.size, pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(out).createSync(recursive: true);
      await File('$out/$name.png').writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  } finally {
    debugDisableShadows = previous;
  }
}

void main() {
  setUpAll(() async {
    if (Platform.environment['MM_SCREENSHOTS'] == null) return;
    final bytes = ByteData.sublistView(await File('/Library/Fonts/Arial Unicode.ttf').readAsBytes());
    for (final family in ['.AppleSystemUIFont', 'Roboto']) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
  });
  for (final dark in [false, true]) {
    testWidgets('name form: $dark, selected value, submit and escape', (tester) async {
      final context = await host(tester, dark: dark);
      final result = showRenameSheet(context, title: '新建脑图…', initial: '未命名脑图', actionLabel: '创建');
      await tester.pumpAndSettle();
      expect(find.text('新建脑图'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.selection, const TextSelection(baseOffset: 0, extentOffset: 5));
      expect(tester.getRect(find.text('名称')).bottom, lessThan(tester.getRect(find.byType(MMTextField)).top));
      await capture(tester, dark ? 'new-map-dark' : 'new-map-light');
      await tester.enterText(find.byType(TextField), '  我的脑图  ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(await result, '我的脑图');
      final cancel = showRenameSheet(context, title: '重命名文档', initial: '文档');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(await cancel, isNull);
    });
  }
  testWidgets('confirmation keeps long content scrollable in a short window', (tester) async {
    final context = await host(tester, size: const Size(640, 320));
    final result = showConfirmSheet(
      context,
      title: '删除脑图',
      message: List.filled(16, '删除后将无法恢复，请确认。').join('\n'),
      confirmLabel: '删除',
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
  });
  testWidgets('phone keyboard leaves name and actions reachable', (tester) async {
    final context = await host(tester, phone: true, size: const Size(390, 844));
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    final result = showRenameSheet(context, title: '重命名脑图', initial: '未命名脑图');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.text('保存')).bottom, lessThanOrEqualTo(524));
    await capture(tester, 'rename-phone-keyboard');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await result, isNull);
  });
}
