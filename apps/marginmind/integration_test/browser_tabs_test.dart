import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/workspace_browser.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../test/helpers.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.defaultTestTimeout = const Timeout(Duration(minutes: 5));
  testWidgets('native webpage tabs retain DOM and history; overflow protects actions', (tester) async {
    await DesktopWindow.initialize(title: 'Foliarc · 浏览器验证', minimumSize: MMSizes.windowMinSize);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final hits = <String, int>{};
    server.listen((request) async {
      hits.update(request.uri.path, (n) => n + 1, ifAbsent: () => 1);
      final path = request.uri.path;
      final title = path == '/agent' ? 'Super-agent 设计探索' : '阅读资料 ${path.split('-').last}';
      request.response.headers.contentType = ContentType.html;
      request.response.write('''<!doctype html><html lang="zh"><meta charset="utf-8"><title>$title</title>
<style>body{margin:0;background:#1c1c1e;color:#dedee3;font:17px/1.9 -apple-system,BlinkMacSystemFont,sans-serif}article{max-width:760px;margin:65px auto;padding:0 44px}h1{font-size:29px;line-height:1.5}h2{color:#579dff;font-size:22px}.by{font-size:14px;color:#999aa4}blockquote{border-left:3px solid #555;padding-left:18px;margin:36px 0;color:#aaa}p{margin:22px 0}a{color:#579dff}</style>
<article><h1>$title：迈向更自主的 Agent 系统</h1><div class="by">DeepSeek Harness 团队 · 2026年10月31日</div>
<blockquote>本文是一篇面向工程实践的架构思路探讨。</blockquote><h2>1. 理解与实践</h2>
${List.generate(10, (i) => '<p>阅读让我们连接知识，也让问题逐渐清晰。保留文章原来的上下文，随时在多个资料之间切换，再把重要内容整理成文档和脑图。每个网页都拥有独立的阅读位置与浏览记录。</p>').join()}
<a href="/next">下一页</a></article><script>document.body.dataset.tabMarker='retained-$path';</script></html>''');
      await request.response.close();
    });
    final c = await pumpApp(
      tester,
      size: const Size(1440, 960),
      settle: false,
      prefs: {'settings.language': 'zh', 'settings.appearance': 'dark'},
    );
    tester.view.reset();
    await binding.setSurfaceSize(const Size(1440, 960));
    c.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pump();
    final browser = c.read(workspaceBrowserProvider('demo-1').notifier);
    final workspace = c.read(workspaceProvider('demo-1').notifier);
    Uri url(String path) => Uri.parse('http://localhost:${server.port}$path');
    Future<void> ready(BrowserSession session) async {
      final deadline = DateTime.now().add(const Duration(seconds: 35));
      debugPrint('BROWSER_QA: waiting for ${session.url}');
      while (session.phase != BrowserPhase.ready && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 200));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(session.phase, BrowserPhase.ready, reason: '${session.url} ${session.lastErrorCode}');
      await tester.pump(const Duration(milliseconds: 350));
    }

    Future<void> shot(String name) async {
      const endpoint = String.fromEnvironment('BROWSER_TABS_SHOT_SERVER');
      if (endpoint.isEmpty) return;
      await tester.pump(const Duration(milliseconds: 350));
      final client = HttpClient();
      try {
        final response = await (await client.getUrl(Uri.parse('$endpoint/$name'))).close();
        expect(response.statusCode, 200);
        await response.drain<void>();
      } finally {
        client.close(force: true);
      }
    }

    debugPrint('BROWSER_QA: app mounted; opening page');
    browser.open(url('/agent'));
    final a = c.read(workspaceBrowserProvider('demo-1')).session!;
    await ready(a);
    expect(find.byKey(const ValueKey('browser-ready-prompt')), findsOneWidget);
    final prompt = tester.getRect(find.byKey(const ValueKey('browser-ready-prompt')));
    final convert = tester.getRect(find.byKey(const ValueKey('browser-convert')));
    expect(prompt.top, greaterThan(convert.bottom));
    expect((prompt.right - convert.right).abs(), lessThan(20));
    await shot('01-conversion-popover-dark');
    await tester.tap(find.widgetWithText(MMButton, '稍后'));
    await tester.pump();
    expect(find.byKey(const ValueKey('browser-ready-prompt')), findsNothing);
    await a.navigate(url('/next'));
    await ready(a);
    expect(a.canGoBack, isTrue);
    a.dismissPrompt();
    final aChannel = MethodChannel('marginmind/browser/${a.id}');
    final originalScroll = await aChannel.invokeMethod<String>('evaluate', {
      'script': 'window.scrollTo(0, 600); String(window.scrollY)',
    });
    expect(double.parse(originalScroll!), greaterThan(100));
    browser.open(url('/article-2'));
    final b = c.read(workspaceBrowserProvider('demo-1')).session!;
    await ready(b);
    b.dismissPrompt();
    final previousHits = hits['/next'];
    browser.show(a.id);
    await tester.pump(const Duration(milliseconds: 500));
    expect(hits['/next'], previousHits);
    final channel = MethodChannel('marginmind/browser/${a.id}');
    expect(
      await channel.invokeMethod<String>('evaluate', {'script': 'document.body.dataset.tabMarker'}),
      'retained-/next',
    );
    final scrollY = await channel.invokeMethod<String>('evaluate', {'script': 'String(window.scrollY)'});
    expect(double.parse(scrollY!), closeTo(double.parse(originalScroll), 1));
    await a.back();
    await ready(a);
    expect(a.url.path, '/agent');
    a.dismissPrompt();
    for (var i = 3; i <= 15; i++) {
      browser.open(url('/article-$i'));
    }
    await tester.pump(const Duration(milliseconds: 300));
    final last = c.read(workspaceBrowserProvider('demo-1')).session!;
    await ready(last);
    for (final p in c.read(workspaceBrowserProvider('demo-1')).pages) {
      p.session.dismissPrompt();
    }
    await tester.pump(const Duration(milliseconds: 500));
    final menu = find.byKey(const ValueKey('workspace-tab-overflow'));
    final controls = tester.getRect(find.byKey(const ValueKey('workspace-layout-controls')));
    expect(tester.getRect(menu).right, lessThanOrEqualTo(controls.left));
    await shot('02-many-tabs-dark');
    await tester.tap(menu);
    await tester.pump(const Duration(milliseconds: 300));
    await shot('03-all-tabs-dark');
    await tester.enterText(find.byKey(const ValueKey('workspace-tab-search')), 'Super-agent');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(ValueKey('workspace-tab-menu-browser:${a.id}')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.read(workspaceBrowserProvider('demo-1')).session, same(a));
    expect(b.disposed, isFalse);
    workspace.closeTab('browser:${b.id}');
    await tester.pump();
    expect(b.disposed, isTrue);
    expect(a.disposed, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
