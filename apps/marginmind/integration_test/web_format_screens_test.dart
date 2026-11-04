import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/assistant/assistant_routing.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/assistant/settings/ai_task_settings.dart' show AiTaskFocusTask;
import 'package:marginmind/features/workspace/web_format_runtime.dart';
import 'package:marginmind/features/workspace/workspace_browser.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/settings/settings_window.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../test/assistant_support.dart' show FakeSecrets;
import '../test/helpers.dart';

/// Walks every AI formatting screen in the real app: real capture and printing,
/// only the model's replies are scripted. With CAPTURE_UI a host process saves
/// the actual window for each PHONE_SHOT marker; see docs/web-ai-format.md.
const _capture = bool.fromEnvironment('CAPTURE_UI');
const _dark = bool.fromEnvironment('UI_DARK', defaultValue: true);
const _landscape = bool.fromEnvironment('UI_LANDSCAPE');

const _filler = '记忆不是一次写入的磁盘，而是一条需要反复走过才会变宽的小路。每一次费力回想，都会让这条路更容易被再次找到。';
final _page =
    '''<!DOCTYPE html><html><head><meta charset="utf-8"><title>间隔重复为什么有效：从遗忘曲线到 FSRS - 学习日报</title></head><body>
<div class="nav"><a href="/">首页</a> <a href="/m">学习方法</a> <a href="/c">课程</a></div>
<div class="content"><div>首页 / 学习方法 / 记忆科学 分享到 微信 微博 阅读 12.4万</div>
<div>作者 林序 发布于 2026-10-28 · 点击上方蓝字关注我们</div>
<div>限时 5 折｜记忆大师训练营，立即抢购</div>
<div>你一定有过这样的经历：考前通宵把书看完，考完一周就忘得差不多了。这不是记性不好。大脑会主动丢弃它判断为不再需要的信息，而复习正是在告诉它“这条信息还要用”。</div>
${List.generate(28, (_) => '<div>$_filler</div>').join()}
<div><b>一、遗忘曲线</b></div>
<div>1885 年，艾宾浩斯用无意义音节测量自己的记忆保持率。遗忘最快发生在学习后的最初几小时，之后逐渐放缓。详见 <a href="https://psychclassics.yorku.ca/Ebbinghaus/index.htm">原始论文</a>。</div>
<img src="/curve.png" alt=""><div>图片来源网络，侵删</div>
${List.generate(28, (_) => '<div>$_filler</div>').join()}
<div><b>二、FSRS 的三个变量</b></div>
<table><tr><td>变量</td><td>含义</td></tr><tr><td>提取概率 R</td><td>此刻想起来的概率</td></tr><tr><td>稳定性 S</td><td>R 从 100% 降到 90% 需要的天数</td></tr></table>
<div>原因主要有三点：1. 提取变难 间隔后回想更费力 2. 情境变化 不同时间提供更多线索 3. 巩固 睡眠让新记忆有时间整合</div>
${List.generate(28, (_) => '<div>$_filler</div>').join()}
<div><b>三、实践建议</b></div>
<div>一张卡片只问一件事。用自己的话写问题，不要照抄原文。</div>
${List.generate(8, (_) => '<div>$_filler</div>').join()}
<div>${List.generate(6, (_) => '最后，如果你想系统学习记忆方法，欢迎报名《高效记忆 21 天》课程，扫描下方二维码添加助教微信。').join()}</div>
</div><div class="aside"><div>热门文章</div></div><div class="foot">©2026 学习日报 沪ICP备00000000号</div></body></html>''';

final _debris = RegExp(r'分享到|蓝字|限时 5 折|侵删|高效记忆 21 天');

/// A stand-in for a well-behaved model, derived from the input so it keeps tokens.
String _format(Map<String, dynamic> input) {
  final blocks = <String>[];
  if (input['first'] == true) blocks.add('# 间隔重复为什么有效：从遗忘曲线到 FSRS');
  for (final block in webMarkdownBlocks(input['text'] as String)) {
    if (_debris.hasMatch(block)) continue;
    final heading = RegExp(r'^\*\*[一二三四五]、(.+)\*\*$').firstMatch(block);
    if (heading != null) {
      blocks.add('## ${heading[1]}');
    } else if (block.startsWith('<table')) {
      final rows = RegExp(r'<tr>(.*?)</tr>', dotAll: true).allMatches(block).map((row) {
        return RegExp(r'<td>(.*?)</td>', dotAll: true).allMatches(row[1]!).map((c) => c[1]!).toList();
      }).toList();
      blocks.add(
        [
          '| ${rows.first.join(' | ')} |',
          '| ${rows.first.map((_) => '---').join(' | ')} |',
          for (final row in rows.skip(1)) '| ${row.join(' | ')} |',
        ].join('\n'),
      );
    } else if (block.startsWith('原因主要有三点')) {
      blocks.add('原因主要有三点：\n\n1. **提取变难**：间隔后回想更费力\n2. **情境变化**：不同时间提供更多线索\n3. **巩固**：睡眠让新记忆有时间整合');
    } else if (block.startsWith('![')) {
      blocks.add(block.replaceFirst('![]', '![遗忘曲线与复习]'));
    } else {
      blocks.add(block);
    }
  }
  return blocks.join('\n\n');
}

class _Script {
  int? pauseAt, failAt;
  Object? failure;
  Completer<void>? pause;
  final reached = Completer<void>();
  Future<String> call(
    Map<String, dynamic> input,
    ModelReference? model,
    void Function(String) onDraft,
    CancellationToken cancel,
  ) async {
    final index = int.parse((input['position'] as String).split('/').first);
    if (index == failAt) {
      await cancel.bind(Future<void>.delayed(const Duration(milliseconds: 300)));
      throw failure!;
    }
    final out = _format(input);
    for (var n = 0; n < out.length; n += 120) {
      await cancel.bind(Future<void>.delayed(const Duration(milliseconds: 16)));
      onDraft(out.substring(0, n));
      if (index == pauseAt && n >= out.length ~/ 2 && pause != null) {
        if (!reached.isCompleted) reached.complete();
        await cancel.bind(pause!.future);
      }
    }
    return out;
  }
}

const _ready = RoutingRowState(
  effective: ModelReference('anthropic', 'claude-opus-5-5'),
  source: RoutingSource.categoryDefault,
  issue: RoutingIssue.none,
  serviceLabel: 'Anthropic',
  modelLabel: 'Claude Opus 5.5',
);

Future<Uint8List> _chart() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 880, 360), Paint()..color = Colors.white);
  final curve = Path()
    ..moveTo(60, 40)
    ..cubicTo(140, 240, 300, 300, 840, 320);
  canvas.drawPath(
    curve,
    Paint()
      ..color = const Color(0xFFD70015)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4,
  );
  final kept = Path()
    ..moveTo(60, 40)
    ..cubicTo(100, 120, 160, 160, 220, 170)
    ..lineTo(220, 60)
    ..cubicTo(300, 110, 380, 130, 460, 140)
    ..lineTo(460, 70)
    ..cubicTo(580, 100, 700, 120, 840, 124);
  canvas.drawPath(
    kept,
    Paint()
      ..color = const Color(0xFF0A66D0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4,
  );
  final image = await recorder.endRecording().toImage(880, 360);
  return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('every AI formatting screen', (tester) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    await DesktopWindow.initialize(title: 'Foliarc', minimumSize: MMSizes.windowMinSize);
    await SystemChrome.setPreferredOrientations(
      _landscape ? [DeviceOrientation.landscapeLeft] : [DeviceOrientation.portraitUp],
    );
    final chart = await tester.runAsync(_chart);
    final server = (await tester.runAsync(() => HttpServer.bind(InternetAddress.loopbackIPv4, 0)))!;
    server.listen((request) async {
      if (request.uri.path == '/curve.png') {
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(chart!);
      } else {
        request.response.headers.contentType = ContentType.html;
        request.response.write(_page);
      }
      await request.response.close();
    });
    final url = Uri.parse('http://localhost:${server.port}/article');

    var route = _ready;
    var script = _Script();
    final base = await testOverrides(
      prefs: {
        'settings.language': 'zh',
        'settings.appearance': _dark ? 'dark' : 'light',
        AssistantServicesStore.settingsKey: jsonEncode(
          AssistantServices(
            services: [
              AssistantService(
                id: 'anthropic',
                protocol: ServiceProtocol.anthropic,
                name: 'Anthropic',
                endpoint: 'https://api.anthropic.com',
                models: const [ServiceModel(id: 'claude-opus-5-5', name: 'Claude Opus 5.5')],
              ),
            ],
          ).toJson(),
        ),
        AssistantRoutingStore.settingsKey: jsonEncode({
          'version': 1,
          'revision': 1,
          'defaults': {
            'quick': {'serviceId': 'anthropic', 'modelId': 'claude-opus-5-5'},
            'heavy': {'serviceId': 'anthropic', 'modelId': 'claude-opus-5-5'},
          },
          'bindings': <String, dynamic>{},
          'heavyReasoning': 'auto',
        }),
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...base,
          assistantSecretsProvider.overrideWithValue(FakeSecrets()),
          webFormatRouteProvider.overrideWith((ref, model) async => route),
          webFormatExecutorProvider.overrideWith(
            (ref, id) =>
                (input, model, onDraft, cancel) => script.call(input, model, onDraft, cancel),
          ),
        ],
        child: const MarginMindApp(),
      ),
    );

    Future<void> idle([int steps = 12]) async {
      for (var i = 0; i < steps; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      }
    }

    final errors = <String>[];
    final marker = File('${Directory.systemTemp.path}/web-format-shot');
    Future<void> shot(String name) async {
      await idle();
      Object? error;
      while ((error = tester.takeException()) != null) {
        errors.add('$name: $error');
        // ignore: avoid_print
        print('SCREEN_ERROR:$name:$error');
      }
      if (!_capture) return;
      await tester.runAsync(() async {
        await marker.writeAsString(name);
        // ignore: avoid_print
        print('PHONE_SHOT:$name:${marker.path}');
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (await marker.readAsString() != 'captured:$name') {
          if (DateTime.now().isAfter(deadline)) throw TimeoutException('Host did not capture $name');
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      });
    }

    Future<void> tap(Finder finder) async {
      await tester.ensureVisible(finder);
      await idle(3);
      await tester.tap(finder, warnIfMissed: false);
      await idle(6);
    }

    Finder button(String label) => find.widgetWithText(MMButton, label);
    bool has(Finder finder) => finder.evaluate().isNotEmpty;

    /// A single column keeps settings in the pane's own segmented control.
    Future<void> pane(String label) async {
      if (!has(find.byType(MMSegmentedControl<int>)) && !has(find.text('设置'))) return;
      final running = has(find.byType(MMSegmentedControl<int>));
      final name = label == '设置' ? (running ? '整理进度' : '设置') : (running ? '排版' : '预览');
      await tap(find.text(name).last);
    }

    Future<void> until(bool Function() done, {int seconds = 60}) async {
      for (var i = 0; i < seconds * 5 && !done(); i++) {
        await idle(2);
      }
      expect(done(), isTrue);
    }

    final container = ProviderScope.containerOf(tester.element(find.byType(MarginMindApp)));
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await idle(20);
    final owner = container.read(workspaceBrowserProvider('demo-1').notifier);

    Future<BrowserSession> browse({String? documentId}) async {
      owner.open(url, documentId: documentId);
      await idle(5);
      final session = container.read(workspaceBrowserProvider('demo-1')).session!;
      await until(() => session.canCapture && session.phase == BrowserPhase.ready);
      return session;
    }

    Future<void> openSheet(BrowserSession session) async {
      final context = tester.element(find.byType(MMBrowserView));
      unawaited(container.read(browserConverterProvider)!(context, 'demo-1', session));
      await idle(25);
    }

    Future<void> enable() async {
      final toggle = find.descendant(
        of: find.byKey(const ValueKey('web-format-card')),
        matching: find.byType(MMSwitch),
      );
      await tap(toggle);
      await idle(8);
    }

    Future<void> cancelSheet() async {
      await tap(button('取消'));
      await idle(8);
    }

    var session = await browse();
    await shot('01-entry');

    await openSheet(session);
    await shot('02-off');
    if (has(find.descendant(of: find.byType(MMSegmentedControl<bool>), matching: find.text('预览')))) {
      await tap(find.text('预览').last);
      await shot('02b-off-preview');
    }
    await cancelSheet();

    route = const RoutingRowState(effective: null, source: RoutingSource.categoryDefault, issue: RoutingIssue.unset);
    container.invalidate(webFormatRouteProvider);
    await openSheet(session);
    await tester.ensureVisible(find.byKey(const ValueKey('web-format-card')));
    await shot('03-no-model');
    await cancelSheet();

    route = const RoutingRowState(
      effective: ModelReference('anthropic', 'claude-opus-5-5'),
      source: RoutingSource.categoryDefault,
      issue: RoutingIssue.modelOff,
    );
    container.invalidate(webFormatRouteProvider);
    await openSheet(session);
    await tester.ensureVisible(find.byKey(const ValueKey('web-format-card')));
    await shot('04-model-off');
    await cancelSheet();

    route = _ready;
    container.invalidate(webFormatRouteProvider);
    await openSheet(session);
    await enable();
    await shot('05-on');

    script = _Script()
      ..pauseAt = 2
      ..pause = Completer<void>();
    await tap(button('开始整理'));
    await tester.runAsync(() => script.reached.future.timeout(const Duration(seconds: 30)));
    await shot('06-streaming');
    await tap(find.text('Markdown').first);
    await shot('07-streaming-markdown');
    await tap(find.text('排版').first);
    await pane('设置');
    await shot('08-progress');
    await pane('内容');
    await tap(button('取消'));
    await shot('09-close-confirm');
    await tap(button('取消').last);
    await tap(find.textContaining('停止整理').first);
    await shot('10-stopped');

    script = _Script();
    await tap(button('继续整理'));
    await until(() => has(find.text('编辑')) && !has(button('停止整理')));
    await shot('11-done');
    await pane('设置');
    await tester.ensureVisible(find.text('查看对照'));
    await shot('12-done-settings');
    await tap(find.text('查看对照'));
    await shot('13-compare');
    await tap(find.text('编辑'));
    await shot('14-edit');
    await tap(find.text('预览'));
    await pane('设置');
    await tap(find.text('Markdown').first);
    await pane('内容');
    await shot('15-format-markdown');
    await pane('设置');
    await tap(find.text('PDF').first);
    await pane('内容');
    await until(() => has(find.byKey(const ValueKey('web-conversion-pdf'))), seconds: 50);
    await idle(20);
    await shot('16-format-pdf');
    await pane('设置');
    await tap(find.text('阅读模式').first);
    await pane('内容');
    await tap(button('保存文档'));
    await idle(30);
    await shot('17-reader');

    session = await browse();
    await openSheet(session);
    await enable();
    script = _Script()
      ..failAt = 2
      ..failure = const ResearchFailure(ResearchFailureKind.rateLimited);
    await tap(button('开始整理'));
    await until(() => has(find.textContaining('没有整理成功')) && !has(button('停止整理')));
    await tester.ensureVisible(find.textContaining('没有整理成功'));
    await shot('18-section-failed');
    await tap(button('取消').first);
    await tap(button('放弃'));
    await idle(10);

    await openSheet(session);
    await enable();
    script = _Script()
      ..failAt = 3
      ..failure = const ResearchFailure(ResearchFailureKind.network);
    await tap(button('开始整理'));
    await until(() => has(find.byKey(const ValueKey('web-format-run-error'))));
    await shot('19-interrupted');
    await tap(button('取消').first);
    await tap(button('放弃'));
    await idle(10);

    final saved = container
        .read(workspaceProvider('demo-1').notifier)
        .content
        .documents
        .firstWhere((d) => d.origin?.formatting != null);
    final refetch = await browse(documentId: saved.id);
    await openSheet(refetch);
    await shot('21-refetch');
    await tap(button('取消').first);
    await idle(10);

    final settingsContext = tester.element(find.byType(MMBrowserView));
    unawaited(
      showSettings(settingsContext, tab: SettingsTab.aiTasks, focus: const AiTaskFocusTask(TaskType.webFormat)),
    );
    await idle(25);
    await shot('20-settings-row');

    // ignore: avoid_print
    print('SCREEN_ERRORS:${errors.length}');
    await server.close(force: true);
  }, timeout: const Timeout(Duration(minutes: 12)));
}
