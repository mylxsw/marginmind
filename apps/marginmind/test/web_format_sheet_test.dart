import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/document_commands.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/assistant/widgets/assistant_markdown.dart';
import 'package:marginmind/features/workspace/widgets/browser_pane.dart';
import 'package:marginmind/features/workspace/workspace_browser.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/workspace/web_conversion.dart';
import 'package:marginmind/features/workspace/web_document.dart';
import 'package:marginmind/features/workspace/web_format_runtime.dart';
import 'package:marginmind/features/workspace/widgets/web_format_panel.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import 'helpers.dart';

const ready = RoutingRowState(
  effective: ModelReference('svc', 'm'),
  source: RoutingSource.categoryDefault,
  issue: RoutingIssue.none,
  serviceLabel: 'Anthropic',
  modelLabel: 'Claude',
);
const unset = RoutingRowState(effective: null, source: RoutingSource.categoryDefault, issue: RoutingIssue.unset);
const disabled = RoutingRowState(
  effective: ModelReference('svc', 'm'),
  source: RoutingSource.categoryDefault,
  issue: RoutingIssue.modelOff,
);

final page = BrowserDocumentCapture(
  url: Uri.parse('https://example.com/article'),
  title: '文章 - 网站',
  capturedAt: DateTime.utc(2026, 11, 3),
  html: '<p>首页 分享</p><p>第一段正文内容第一段正文内容</p>',
  snapshot: '<p>snapshot</p>',
  resources: {},
);

class Harness {
  Harness({this.answer = '# 干净标题\n\n## 小节\n\n第一段正文内容第一段正文内容'});
  String answer;
  Map<String, Uint8List> resources = const {};
  String sourceText = '首页 分享\n\n第一段正文内容第一段正文内容';
  Object? failure;
  Completer<void>? gate;
  final calls = <Map<String, dynamic>>[];
  final origins = <DocumentOriginFormatting>[];
  final bodies = <String>[];
  final modes = <WebCaptureMode>[];
  final plain = <WebCaptureMode>[];
  PreparedWebDocument? saved;
  static const converter = WebDocumentConverter(inspectPdf: _pdf);
  static Future<WebPdfInfo> _pdf(List<int> _) async => (pageCount: 1, pages: <TranslationPage>[], preview: null);

  late final host = WebFormatHost(
    executor: (input, model, onDraft, cancel) async {
      calls.add(input);
      onDraft(answer.substring(0, answer.length ~/ 2));
      if (gate != null) await cancel.bind(gate!.future);
      if (failure != null) throw failure!;
      return answer;
    },
    load: () async => (markdown: sourceText, pageTitle: page.title, resources: resources),
    prepare: (mode, body, title, origin) async {
      bodies.add(body);
      origins.add(origin);
      modes.add(mode);
      return Harness.converter.prepare(
        page,
        id: 'doc',
        title: title,
        mode: WebCaptureMode.readable,
        formatted: WebFormattedContent(markdown: '# $title\n\n$body', origin: origin),
      );
    },
  );

  Future<void> pump(
    WidgetTester tester, {
    RoutingRowState row = ready,
    Size size = const Size(1280, 900),
    bool initialFormatting = false,
    String? initialTitle,
    bool withHost = true,
    bool realRoute = false,
    bool phone = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final overrides = await testOverrides();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [...overrides, if (!realRoute) webFormatRouteProvider.overrideWith((ref, model) async => row)],
        child: MaterialApp(
          theme: MMTheme.dark().copyWith(platform: TargetPlatform.macOS),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          builder: phone ? (_, child) => MMInput(touchPlatform: true, phone: true, child: child!) : null,
          home: Scaffold(
            body: Builder(
              builder: (context) => MMButton(
                label: 'Open',
                onPressed: () => unawaited(
                  showMMSheet<PreparedWebDocument>(
                    context: context,
                    width: MMSizes.webConversionSheetWidth,
                    initialFraction: MMSizes.phoneSheetExpanded,
                    builder: (_) => WebConversionSheet(
                      prepare: (mode) {
                        plain.add(mode);
                        return Harness.converter.prepare(
                          page,
                          id: 'doc',
                          title: page.title,
                          mode: WebCaptureMode.readable,
                        );
                      },
                      formatting: withHost ? host : null,
                      initialFormatting: initialFormatting,
                      initialTitle: initialTitle,
                    ),
                  ).then((value) => saved = value),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }
}

Future<void> finish(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

Finder get toggle =>
    find.descendant(of: find.byKey(const ValueKey('web-format-card')), matching: find.byType(MMSwitch));

Future<void> startFormatting(WidgetTester tester) async {
  await tester.ensureVisible(toggle);
  await tester.pumpAndSettle();
  await tester.tap(toggle);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(MMButton, '开始整理'));
  await tester.pump();
}

Future<void> startFormattingKeepingGate(WidgetTester tester, Harness h) async {
  h.gate = Completer<void>();
  await startFormatting(tester);
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('the switch is off by default and saving stays unchanged', (tester) async {
    final h = Harness();
    await h.pump(tester);
    expect(find.text('保存文档'), findsOneWidget);
    expect(find.text('开始整理'), findsNothing);
    expect(tester.widget<MMSwitch>(toggle).value, isFalse);
    await tester.tap(find.widgetWithText(MMButton, '保存文档'));
    await tester.pumpAndSettle();
    expect(h.calls, isEmpty);
    expect(h.saved!.package.document.origin!.formatting, isNull);
  });

  testWidgets('without a host there is no AI option at all', (tester) async {
    final h = Harness();
    await h.pump(tester, withHost: false);
    expect(find.byType(WebFormatCard), findsNothing);
  });

  testWidgets('no model: the switch is disabled and points to settings', (tester) async {
    final h = Harness();
    await h.pump(tester, row: unset);
    expect(tester.widget<MMSwitch>(toggle).onChanged, isNull);
    expect(find.text('去设置'), findsOneWidget);
    expect(find.text('添加模型后即可使用'), findsOneWidget);
    expect(find.text('保存文档'), findsOneWidget);
  });

  testWidgets('the real route reports an empty configuration as needing a model', (tester) async {
    final h = Harness();
    await h.pump(tester, realRoute: true);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(tester.widget<MMSwitch>(toggle).onChanged, isNull);
    expect(find.text('添加模型后即可使用'), findsOneWidget);
  });

  testWidgets('a disabled model explains itself and blocks the switch', (tester) async {
    final h = Harness();
    await h.pump(tester, row: disabled);
    expect(tester.widget<MMSwitch>(toggle).onChanged, isNull);
    expect(find.text('模型已停用'), findsOneWidget);
  });

  testWidgets('turning it on discloses the destination and asks to start', (tester) async {
    final h = Harness();
    await h.pump(tester);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('开始整理'), findsOneWidget);
    expect(find.text('保存文档'), findsNothing);
    expect(find.textContaining('正文会发送到 Anthropic'), findsOneWidget);
    expect(find.textContaining('分 1 段'), findsOneWidget);
    expect(h.calls, isEmpty, reason: 'nothing is sent until the user starts');
  });

  testWidgets('streams progress, blocks saving, then saves formatted text under the clean title', (tester) async {
    final h = Harness()..gate = Completer<void>();
    await h.pump(tester);
    await startFormatting(tester);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('整理进度'), findsOneWidget);
    expect(find.textContaining('正在整理第 1/1 段'), findsOneWidget);
    expect(find.text('停止整理'), findsOneWidget);
    expect(find.textContaining('可以随时停止'), findsOneWidget);
    expect(tester.widget<MMButton>(find.widgetWithText(MMButton, '保存文档')).onPressed, isNull);

    h.gate!.complete();
    await finish(tester);
    expect(find.text('完整性检查'), findsOneWidget);
    expect(find.text('预览'), findsOneWidget);
    expect(find.text('小节'), findsWidgets);
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, '干净标题');

    await tester.tap(find.widgetWithText(MMButton, '保存文档'));
    await tester.pumpAndSettle();
    expect(h.bodies.single, contains('## 小节'));
    expect(h.bodies.single, isNot(contains('# 干净标题')));
    expect(h.modes.single, WebCaptureMode.readable);
    expect(h.origins.single.model, 'Claude');
    expect(h.origins.single.edited, isFalse);
    expect(h.saved!.package.document.title, '干净标题');
    expect(h.saved!.package.document.origin!.formatting!.promptVersion, webFormatPromptVersion);
    expect(jsonEncode(h.saved!.package.document.toJson()), contains('formatting'));
  });

  testWidgets('a name the user typed is never replaced', (tester) async {
    final h = Harness();
    await h.pump(tester);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '我的名字');
    await tester.pump();
    await startFormatting(tester);
    await finish(tester);
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, '我的名字');
  });

  testWidgets('editing changes what is saved and can be reverted', (tester) async {
    final h = Harness();
    await h.pump(tester);
    await startFormatting(tester);
    await finish(tester);
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(find.text('实时预览'), findsOneWidget);
    expect(find.byKey(const ValueKey('web-conversion-settings')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('web-format-editor')), '## 改过的\n\n内容');
    await tester.pump();
    expect(find.text('改过的'), findsOneWidget);
    expect(find.text('还原 AI 结果'), findsOneWidget);

    await tester.tap(find.text('还原 AI 结果'));
    await tester.pumpAndSettle();
    expect(find.text('还原 AI 结果？'), findsOneWidget);
    await tester.tap(find.widgetWithText(MMButton, '取消').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(MMButton, '保存文档'));
    await tester.pumpAndSettle();
    expect(h.bodies.single, '## 改过的\n\n内容');
    expect(h.origins.single.edited, isTrue);
  });

  testWidgets('comparison strikes removed text and review can be acknowledged', (tester) async {
    final h = Harness(answer: '## 小节\n\n一');
    await h.pump(tester);
    await startFormatting(tester);
    await finish(tester);
    expect(find.textContaining('比原文少'), findsOneWidget);
    await tester.tap(find.text('查看对照'));
    await tester.pumpAndSettle();
    expect(find.text('原始提取'), findsOneWidget);
    expect(find.byKey(const ValueKey('web-format-removed')), findsWidgets);
    await tester.tap(find.text('没问题'));
    await tester.pumpAndSettle();
    expect(find.textContaining('删除的内容已划线'), findsNothing);
  });

  testWidgets('tabs keep the pane: comparison reveals its section and review starts at the top', (tester) async {
    final filler = List.filled(40, '第一段正文内容第一段正文内容第一段正文内容。').join('\n\n');
    final h = Harness(answer: '## 小节\n\n$filler')..sourceText = '$filler\n\n**二、后面**\n\n$filler\n\n**三、最后**\n\n$filler';
    await h.pump(tester);
    await startFormatting(tester);
    await finish(tester);
    final scroll = find.byKey(const ValueKey('web-format-scroll'));
    expect(tester.widget<SingleChildScrollView>(scroll).controller!.offset, 0, reason: 'review starts from the title');
    final state = tester.state(find.byType(WebFormatPane));
    await tester.tap(find.text('对照原文'));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(WebFormatPane)), same(state), reason: 'switching tabs must not rebuild the pane');
    expect(find.text('AI 整理后'), findsOneWidget);
    await tester.drag(find.byKey(const ValueKey('web-format-compare')), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('AI 整理后'), findsOneWidget, reason: 'column heads stay in place');
  });

  testWidgets('a failed section offers retry and captured text, without blocking save', (tester) async {
    final h = Harness()..failure = const ResearchFailure(ResearchFailureKind.rateLimited);
    await h.pump(tester);
    await startFormatting(tester);
    await finish(tester);
    expect(find.text('第 1 段没有整理成功'), findsOneWidget);
    expect(find.textContaining('已整理 0/1 段'), findsOneWidget);
    await tester.tap(find.text('使用原始内容'));
    await tester.pumpAndSettle();
    expect(find.textContaining('未整理，保留原始内容'), findsOneWidget);
    await tester.tap(find.widgetWithText(MMButton, '保存文档'));
    await tester.pumpAndSettle();
    expect(h.origins.single.unformattedSections, 1);
    expect(h.bodies.single, contains('第一段正文内容'));
  });

  testWidgets('an interrupted run keeps a way to continue', (tester) async {
    final h = Harness()..failure = const ResearchFailure(ResearchFailureKind.network);
    await h.pump(tester);
    await startFormatting(tester);
    await finish(tester);
    expect(find.byKey(const ValueKey('web-format-run-error')), findsOneWidget);
    h.failure = null;
    await tester.tap(find.text('继续整理'));
    await finish(tester);
    expect(find.byKey(const ValueKey('web-format-run-error')), findsNothing);
    expect(find.text('小节'), findsWidgets);
  });

  testWidgets('closing with work asks first; stay keeps it, discard closes', (tester) async {
    final h = Harness()..gate = Completer<void>();
    await h.pump(tester);
    await startFormatting(tester);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.widgetWithText(MMButton, '取消'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('放弃整理结果？'), findsOneWidget);
    await tester.tap(find.widgetWithText(MMButton, '取消').last);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(WebConversionSheet), findsOneWidget);
    await tester.tap(find.widgetWithText(MMButton, '取消'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('放弃'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byType(WebConversionSheet), findsNothing);
    expect(h.saved, isNull);
  });

  testWidgets('stopping keeps the sheet, and discarding returns to the plain flow', (tester) async {
    final h = Harness()..gate = Completer<void>();
    await h.pump(tester);
    await startFormatting(tester);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('停止整理'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已整理 0/1 段'), findsOneWidget);
    expect(find.text('继续整理'), findsOneWidget);
    await tester.tap(find.text('放弃整理，用原始内容'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃'));
    await tester.pumpAndSettle();
    expect(find.byType(WebFormatCard), findsOneWidget);
    expect(find.text('保存文档'), findsOneWidget);
    expect(find.text('预览'), findsNothing);
  });

  testWidgets('refetching a formatted document offers AI without calling it and keeps the name', (tester) async {
    final h = Harness();
    await h.pump(tester, initialFormatting: true, initialTitle: '原来的名字');
    await tester.pumpAndSettle();
    expect(find.text('开始整理'), findsOneWidget);
    expect(h.calls, isEmpty);
    await tester.tap(find.widgetWithText(MMButton, '开始整理'));
    await finish(tester);
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, '原来的名字');
  });

  testWidgets('refetching without a usable model falls back to saving as captured', (tester) async {
    final h = Harness();
    await h.pump(tester, row: unset, initialFormatting: true, initialTitle: '原来的名字');
    await tester.pumpAndSettle();
    expect(find.text('开始整理'), findsNothing);
    expect(find.text('保存文档'), findsOneWidget);
  });

  testWidgets('captured images show in the preview, and a missing one is labeled', (tester) async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jVYsAAAAASUVORK5CYII=',
    );
    final h = Harness(answer: '## 小节\n\n![曲线](⟦R1⟧)\n\n![没有的图](⟦R2⟧)')
      ..sourceText = '![](<resources/image-1.png>)\n\n![](<resources/gone.png>)'
      ..resources = {'resources/image-1.png': png};
    await h.pump(tester);
    await startFormatting(tester);
    await finish(tester);
    expect(find.byWidgetPredicate((w) => w is Image && w.image is MemoryImage), findsOneWidget);
    expect(find.text('没有的图'), findsOneWidget);
  });

  testWidgets('a narrow split pane stacks its status instead of cutting it off', (tester) async {
    final h = Harness()..failure = const ResearchFailure(ResearchFailureKind.network);
    await h.pump(tester, size: const Size(820, 900));
    await startFormatting(tester);
    await finish(tester);
    final tabs = tester.getRect(find.byType(MMSegmentedControl<WebFormatTab>));
    final status = tester.getRect(find.textContaining('已整理 0/1 段'));
    expect(status.top, greaterThanOrEqualTo(tabs.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('turning it on brings the destination into view on a phone', (tester) async {
    final h = Harness();
    await h.pump(tester, size: const Size(390, 700), phone: true);
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('web-format-disclosure')).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a single column keeps the main action on top and one level of tabs', (tester) async {
    final h = Harness();
    await h.pump(tester, size: const Size(390, 844), phone: true);
    final sheetTitle = tester.getRect(find.text('保存到资料库'));
    expect((tester.getCenter(find.widgetWithText(MMButton, '保存文档')).dy - sheetTitle.center.dy).abs(), lessThan(24));
    final sheetScroll = tester.state<ScrollableState>(
      find.ancestor(of: find.byType(MMSegmentedControl<bool>), matching: find.byType(Scrollable)).first,
    );
    expect(sheetScroll.position.maxScrollExtent, 0, reason: 'tabs stay pinned: only the pane below them scrolls');
    expect(find.byKey(const ValueKey('web-conversion-settings')), findsOneWidget);
    await tester.tap(find.text('预览'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('web-conversion-settings')), findsNothing);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await startFormattingKeepingGate(tester, h);
    expect(find.text('整理进度'), findsWidgets);
    await tester.tap(find.text('整理进度').first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('文档名称'), findsNothing, reason: 'the progress tab is about progress');
    h.gate!.complete();
    await finish(tester);
    expect(find.textContaining('用时'), findsNothing, reason: 'statistics do not earn a row on a single column');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a single column shares the pane with settings', (tester) async {
    final h = Harness();
    await h.pump(tester, size: const Size(600, 900));
    await startFormatting(tester);
    await finish(tester);
    expect(find.byKey(const ValueKey('web-conversion-settings')), findsNothing);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('web-conversion-settings')), findsOneWidget);
    await tester.tap(find.text('预览'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('web-conversion-settings')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('through the real conversion flow', () {
    Future<void> loaded(BrowserSession session, {Uint8List? pdf}) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel('marginmind/browser/${session.id}'),
        (call) async {
          if (call.method == 'printPdf') return pdf;
          if (call.method != 'evaluate') return null;
          final script = (call.arguments as Map)['script'] as String;
          return script.startsWith('JSON.stringify({ready:') ? '{"ready":true}' : '{}';
        },
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        'marginmind/browser/${session.id}',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('event', {'kind': 'loaded', 'navigationId': 1, 'url': session.url.toString()}),
        ),
        (_) {},
      );
      await session.stop();
    }

    Future<(ProviderContainer, List<WebCaptureMode>)> app(WidgetTester tester, List<Map<String, dynamic>> calls) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final captures = <WebCaptureMode>[];
      final container = await pumpApp(
        tester,
        overrides: [
          canAddWebPageProvider.overrideWithValue(true),
          webFormatRouteProvider.overrideWith((ref, model) async => ready),
          webFormatExecutorProvider.overrideWith(
            (ref, id) => (input, model, onDraft, cancel) async {
              calls.add(input);
              return '# 干净标题\n\n## 小节\n\n第一段正文内容第一段正文内容';
            },
          ),
          webDocumentConverterProvider.overrideWithValue(Harness.converter),
          webCaptureProvider.overrideWithValue((session, generation, mode, cancelled) async {
            captures.add(mode);
            return BrowserDocumentCapture(
              url: session.url,
              title: page.title,
              capturedAt: page.capturedAt,
              html: page.html,
              snapshot: page.snapshot,
              resources: page.resources,
            );
          }),
        ],
      );
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      return (container, captures);
    }

    Future<BrowserSession> open(
      WidgetTester tester,
      ProviderContainer container, {
      String? documentId,
      Uint8List? pdf,
    }) async {
      final owner = container.read(workspaceBrowserProvider('demo-1').notifier);
      owner.open(Uri.parse('https://example.com/article'), documentId: documentId);
      await tester.pump();
      final session = container.read(workspaceBrowserProvider('demo-1')).session!;
      await loaded(session, pdf: pdf);
      return session;
    }

    Future<void> convert(WidgetTester tester, ProviderContainer container, BrowserSession session) async {
      final context = tester.element(find.byType(BrowserPane));
      unawaited(container.read(browserConverterProvider)!(context, 'demo-1', session));
      await tester.pumpAndSettle();
    }

    testWidgets('saves AI Markdown as the document, keeps the snapshot and asks again on refetch', (tester) async {
      final calls = <Map<String, dynamic>>[];
      final (container, _) = await app(tester, calls);
      final session = await open(tester, container);
      await convert(tester, container, session);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MMButton, 'Start Formatting'));
      await finish(tester);
      await tester.tap(find.widgetWithText(MMButton, 'Save Document'));
      await tester.pumpAndSettle();

      expect(calls.single['first'], isTrue);
      expect(calls.single['text'], contains('首页 分享'));
      expect(calls.single['text'], isNot(contains('mm-web-source')), reason: 'provenance is added by the app');
      final controller = container.read(workspaceProvider('demo-1').notifier);
      final document = controller.content.documents.firstWhere((d) => d.origin != null);
      expect(document.title, '干净标题');
      expect(document.origin!.formatting!.model, 'Claude');
      expect(document.origin!.snapshotFile, isNotNull);
      final repository = container.read(contentRepositoryProvider) as DocumentRepository;
      final source = utf8.decode(await repository.readDocumentFile('demo-1', document.sourceFileName!));
      expect(source, startsWith('# 干净标题'));
      expect(source, contains('AI formatted'));
      expect(source, contains('## 小节'));

      final again = await open(tester, container, documentId: document.id);
      await convert(tester, container, again);
      expect(find.byType(WebConversionSheet), findsOneWidget, reason: 'never a silent model call or overwrite');
      expect(find.text('Start Formatting'), findsOneWidget);
      expect(calls.length, 1);
      await tester.tap(find.widgetWithText(MMButton, 'Cancel'));
      await tester.pumpAndSettle();
      container.read(workspaceBrowserProvider('demo-1').notifier).close();
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a PDF prints the approved Markdown, never the page', (tester) async {
      final calls = <Map<String, dynamic>>[];
      final (container, captures) = await app(tester, calls);
      final session = await open(tester, container, pdf: Uint8List.fromList(ascii.encode('%PDF-typeset')));
      await convert(tester, container, session);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MMButton, 'Start Formatting'));
      await finish(tester);
      await tester.tap(find.text('PDF'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.widgetWithText(MMButton, 'Save Document'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(captures, isNot(contains(WebCaptureMode.original)));
      final controller = container.read(workspaceProvider('demo-1').notifier);
      final document = controller.content.documents.firstWhere((d) => d.origin != null);
      expect(document.origin!.mode, WebCaptureMode.original);
      expect(document.origin!.formatting, isNotNull);
      final repository = container.read(contentRepositoryProvider) as DocumentRepository;
      expect(ascii.decode(await repository.readDocumentFile('demo-1', document.fileName)), '%PDF-typeset');
      container.read(workspaceBrowserProvider('demo-1').notifier).close();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  test('the executor refuses a study set without a directory, before any model call', () async {
    final container = ProviderContainer(overrides: await testOverrides());
    addTearDown(container.dispose);
    final execute = container.read(webFormatExecutorProvider(''));
    await expectLater(
      execute(const {'id': 's1', 'text': '正文'}, null, (_) {}, CancellationToken()),
      throwsA(isA<ConfigurationFailure>()),
    );
    final cancelled = CancellationToken()..cancel();
    await expectLater(
      execute(const {'id': 's1', 'text': '正文'}, null, (_) {}, cancelled),
      throwsA(isA<ResearchFailure>()),
    );
  });

  testWidgets('document rendering shows images by resource and a labeled placeholder otherwise', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: MMTheme.dark(),
        home: Scaffold(
          body: AnswerBody(
            text: '## 标题\n\n![图一](a.png)',
            citations: const [],
            onCitation: (_) {},
            imageBuilder: (source, alt) => Text('image:$source:$alt'),
            headingStyle: (level) => TextStyle(fontSize: level * 10.0),
          ),
        ),
      ),
    );
    expect(find.text('image:a.png:图一'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        theme: MMTheme.dark(),
        home: Scaffold(
          body: AnswerBody(text: '![只有文字](a.png)', citations: const [], onCitation: (_) {}),
        ),
      ),
    );
    expect(find.textContaining('只有文字', findRichText: true), findsOneWidget);
  });
}
