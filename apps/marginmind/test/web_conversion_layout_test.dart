import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/web_conversion.dart';
import 'package:marginmind/features/workspace/web_document.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import 'vocabulary_screenshots.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadVocabularyScreenshotFonts();
    if (!vocabularyScreenshotsEnabled) return;
    for (final family in ['.AppleSystemUIFont', 'CupertinoSystemText', 'CupertinoSystemDisplay', 'Roboto']) {
      final bytes = ByteData.sublistView(await File('/System/Library/Fonts/SFNS.ttf').readAsBytes());
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
    final pingFang = Directory('/System/Library/AssetsV2/com_apple_MobileAsset_Font8')
        .listSync(recursive: true)
        .whereType<File>()
        .firstWhere((f) => f.path.endsWith('/PingFang.ttc'));
    await (FontLoader('PingFang SC')..addFont(Future.value(ByteData.sublistView(await pingFang.readAsBytes())))).load();
  });

  for (final size in [const Size(1512, 1040), const Size(390, 780), const Size(900, 420)]) {
    testWidgets('library save layout remains usable at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const title = 'Super-agent 设计探索：迈向更自主的 Agent 系统';
      final prepared = await const WebDocumentConverter().prepare(
        BrowserDocumentCapture(
          url: Uri.parse('https://mp.weixin.qq.com/article'),
          title: title,
          capturedAt: DateTime(2026, 11, 1),
          html:
              '<p>本文是一篇面向工程实践的架构思路探讨，并非对 DeepSeek Harness 现有产品功能的介绍。</p>'
              '<h2>1. Super-agent</h2><p>过去一年里，以 Coding Agent 为代表的单任务 Agent 已经证明，模型能够使用工具解决复杂问题。</p>'
              '${List.generate(12, (i) => '<p>第 $i 段：越来越多的团队开始探索更自主的系统，让 Agent 在更长的任务中持续理解目标、使用工具并检查结果。</p>').join()}',
          snapshot: '<p>Article</p>',
          resources: {},
        ),
        id: 'preview',
        title: title,
        mode: WebCaptureMode.readable,
      );
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: MMTheme.dark().copyWith(platform: TargetPlatform.macOS),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: RepaintBoundary(
            key: const ValueKey('capture'),
            child: Scaffold(
              body: Builder(
                builder: (context) => MMButton(
                  label: 'Open',
                  onPressed: () => unawaited(
                    showMMSheet<void>(
                      context: context,
                      width: MMSizes.webConversionSheetWidth,
                      builder: (_) => WebConversionSheet(prepare: (_) async => prepared),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('保存到资料库'), findsOneWidget);
      expect(find.text('文档名称'), findsOneWidget);
      expect(find.text('保存格式'), findsOneWidget);
      final preview = find.byKey(const ValueKey('web-conversion-preview'));
      expect(preview, findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).maxLines, 1);
      expect(find.textContaining('适合阅读与标注'), findsNothing);
      expect(tester.takeException(), isNull);
      final save = find.widgetWithText(MMButton, '保存文档');
      expect(save.hitTestable(), findsOneWidget);
      if (size.width >= 900) {
        final settings = find.byKey(const ValueKey('web-conversion-settings'));
        expect(tester.getRect(preview).right, lessThan(tester.getRect(settings).left));
        expect(tester.getSize(preview).width, greaterThan(tester.getSize(settings).width));
        expect(tester.getSize(preview).height, greaterThanOrEqualTo(220));
        if (size.width > 1000) expect(tester.getSize(preview).height, greaterThanOrEqualTo(500));
        expect(tester.getTopLeft(find.text('阅读模式')).dy, lessThan(tester.getTopLeft(find.text('Markdown')).dy));
      }
      expect(find.descendant(of: preview, matching: find.byType(RawScrollbar)), findsNothing);
      if (vocabularyScreenshotsEnabled) {
        final view = tester.binding.renderViews.first;
        final image = (await tester.runAsync(
          () => (view.debugLayer! as OffsetLayer).toImage(Offset.zero & view.size),
        ))!;
        final png = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png)))!;
        await tester.runAsync(
          () =>
              File('${Platform.environment['MM_SCREENSHOTS']}/web-conversion-${size.width.toInt()}.png')
                  .writeAsBytes(png.buffer.asUint8List()),
        );
        image.dispose();
      }
      await tester.ensureVisible(preview);
      await tester.pumpAndSettle();
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: preview, matching: find.byType(Scrollable)).first,
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(0));
      await tester.drag(preview, const Offset(0, -160));
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, greaterThan(0));
      expect(find.descendant(of: preview, matching: find.byType(RawScrollbar)), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byType(WebConversionSheet), findsNothing);
    });
  }
}
