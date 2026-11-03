import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/web_conversion.dart';
import 'package:marginmind/features/workspace/web_document.dart';
import 'package:marginmind/features/workspace/web_format_runtime.dart';
import 'package:marginmind/features/workspace/widgets/web_format_panel.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_book/mm_book.dart' as book;
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:shared_preferences/shared_preferences.dart';

const messyPage = '''<!DOCTYPE html><html><head><meta charset="utf-8"><title>间隔重复为什么有效 - 学习日报</title></head><body>
<div class="nav"><a href="/">PAGE_NAVIGATION</a></div>
<div class="content"><div>首页 / 学习方法 分享到 微信 阅读 12.4万</div>
<div>你一定有过这样的经历：考前通宵把书看完，考完一周就忘得差不多了。这不是记性不好。</div>
<div><b>一、遗忘曲线</b></div>
<div>1885 年，艾宾浩斯用无意义音节测量自己的记忆保持率。遗忘最快发生在学习后的最初几小时，之后逐渐放缓。</div>
<div>限时 5 折｜记忆大师训练营，立即抢购</div>
<div><b>二、间隔效应</b></div>
<div>原因主要有三点：1. 提取变难 2. 情境变化 3. 巩固</div>
</div></body></html>''';

const formatted = '''# 间隔重复为什么有效

你一定有过这样的经历：考前通宵把书看完，考完一周就忘得差不多了。这不是记性不好。

## 遗忘曲线

1885 年，艾宾浩斯用无意义音节测量自己的记忆保持率。遗忘最快发生在学习后的最初几小时，之后逐渐放缓。

## 间隔效应

原因主要有三点：

1. 提取变难
2. 情境变化
3. 巩固
''';

/// Native proof: real WebKit capture, the real sheet with a scripted model, and
/// a real typeset PDF printed from the live tab. MM_WEB_FORMAT_EVIDENCE saves
/// screenshots and the PDF into the app's temporary directory.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('formats a captured page and prints the approved text', (tester) async {
    await DesktopWindow.initialize(
      title: 'Foliarc — AI Formatting Check',
      minimumSize: const Size(900, 650),
      initialSize: const Size(1280, 900),
    );
    await MMPdfEngine.initialize();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers.contentType = ContentType.html;
      request.response.write(messyPage);
      await request.response.close();
    });
    final session = BrowserSession(Uri.parse('http://localhost:${server.port}/article'));
    final shot = GlobalKey();
    final evidence = Platform.environment['MM_WEB_FORMAT_EVIDENCE'] != null;
    final out = Directory('${Directory.systemTemp.path}/web-format')..createSync(recursive: true);
    Future<void> capture(String name) async {
      if (!evidence) return;
      final boundary = shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('${out.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    }

    Future<void> settle([int steps = 15]) async {
      for (var i = 0; i < steps; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
    }

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final gate = Completer<void>();
    final inputs = <Map<String, dynamic>>[];
    const converter = WebDocumentConverter();
    const parser = book.WebBookParser();
    late final BrowserDocumentCapture readable;
    Uint8List? printed;
    final host = WebFormatHost(
      executor: (input, model, onDraft, cancel) async {
        inputs.add(input);
        onDraft(formatted.substring(0, formatted.length ~/ 2));
        await gate.future;
        return formatted;
      },
      load: () async {
        readable = await session.captureDocument(navigationId: session.navigationId);
        final resources = parser.sanitizeResources(readable.resources);
        return (
          markdown: parser.markdown(parser.sanitizeHtml(readable.html, resources.keys.toSet())),
          pageTitle: readable.title,
          resources: resources,
        );
      },
      prepare: (mode, body, title, origin) async {
        final markdown = parser.withMarkdownAttribution(body, title, readable.url, readable.capturedAt, note: 'AI 整理');
        final pdf = mode == WebCaptureMode.original
            ? await session.printDocument(
                navigationId: session.navigationId,
                html: parser.printableHtml(markdown, const {}),
                resources: const {},
              )
            : null;
        printed = pdf ?? printed;
        return converter.prepare(
          readable,
          id: 'doc',
          title: title,
          mode: mode,
          formatted: WebFormattedContent(markdown: markdown, origin: origin, pdf: pdf),
        );
      },
    );
    PreparedWebDocument? saved;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          webFormatRouteProvider.overrideWith(
            (ref, model) async => const RoutingRowState(
              effective: ModelReference('svc', 'm'),
              source: RoutingSource.categoryDefault,
              issue: RoutingIssue.none,
              serviceLabel: 'Anthropic',
              modelLabel: 'Claude',
            ),
          ),
        ],
        child: RepaintBoundary(
          key: shot,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: MMTheme.dark(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Scaffold(
              body: Stack(
                children: [
                  Positioned.fill(child: MMBrowserView(session: session)),
                  Builder(
                    builder: (context) => MMButton(
                      label: 'Open',
                      onPressed: () => unawaited(
                        showMMSheet<PreparedWebDocument>(
                          context: context,
                          width: MMSizes.webConversionSheetWidth,
                          builder: (_) => WebConversionSheet(
                            prepare: (mode) async => converter.prepare(
                              await session.captureDocument(
                                navigationId: session.navigationId,
                                mode: BrowserDocumentMode.values.byName(mode.name),
                              ),
                              id: 'doc',
                              title: '间隔重复为什么有效 - 学习日报',
                              mode: mode,
                            ),
                            formatting: host,
                          ),
                        ).then((value) => saved = value),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final elapsed = Stopwatch()..start();
    while (session.phase != BrowserPhase.ready && elapsed.elapsed < const Duration(seconds: 30)) {
      await tester.pump(const Duration(milliseconds: 200));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(session.phase, BrowserPhase.ready);
    await tester.tap(find.text('Open'));
    await settle(30);
    await capture('1-off');
    await tester.tap(
      find.descendant(of: find.byKey(const ValueKey('web-format-card')), matching: find.byType(MMSwitch)),
    );
    await settle(20);
    await capture('2-on');
    await tester.tap(find.widgetWithText(MMButton, '开始整理'));
    await settle();
    expect(find.textContaining('正在整理第'), findsOneWidget);
    await capture('3-streaming');
    expect(inputs.single['text'], contains('记忆大师训练营'), reason: 'Readability keeps this debris for AI to remove');
    expect(inputs.single['text'], isNot(contains('PAGE_NAVIGATION')));
    gate.complete();
    await settle();
    expect(find.byType(WebFormatPane), findsOneWidget);
    await capture('4-done');
    await tester.tap(find.text('编辑'));
    await settle();
    await capture('5-edit');
    await tester.tap(find.text('对照原文'));
    await settle();
    await capture('6-compare');
    await tester.tap(find.text('预览'));
    await settle();
    await tester.tap(find.text('PDF'));
    final printing = Stopwatch()..start();
    while (printed == null && printing.elapsed < const Duration(seconds: 50)) {
      await tester.pump(const Duration(milliseconds: 200));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(printed, isNotNull, reason: 'the real print pipeline produced a PDF');
    await settle(20);
    await capture('7-pdf');
    final info = await MMPdfEngine.inspectData(printed!);
    final text = info.pages.map((page) => page.text).join('\n');
    expect(text, contains('遗忘曲线'));
    expect(text, contains('AI 整理'));
    expect(text, isNot(contains('记忆大师训练营')), reason: 'the PDF holds the approved text, not the page');
    expect(text, isNot(contains('PAGE_NAVIGATION')));
    if (evidence) {
      File('${out.path}/typeset.pdf').writeAsBytesSync(printed!);
      debugPrint('[web-format] evidence: ${out.path}');
    }
    await tester.tap(find.widgetWithText(MMButton, '保存文档'));
    await settle(20);
    expect(saved!.package.document.title, '间隔重复为什么有效');
    expect(saved!.package.document.origin!.formatting!.model, 'Claude');
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
  }, timeout: const Timeout(Duration(minutes: 4)));
}
