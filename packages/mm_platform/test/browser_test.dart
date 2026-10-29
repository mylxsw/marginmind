import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_platform/mm_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('address normalization and navigation safety', () {
    expect(BrowserPolicy.normalize(' example.com/a?q=1 ').toString(), 'https://example.com/a?q=1');
    expect(BrowserPolicy.normalize('localhost:8080/a').host, 'localhost');
    expect(BrowserPolicy.normalize('http://127.0.0.1:1234').port, 1234);
    expect(BrowserPolicy.normalize('https://[::1]/').host, '::1');
    for (final input in [
      '',
      '  ',
      'example',
      'https://',
      'https://a b.com',
      'https://user:pass@example.com',
      'file:///a',
      'javascript:alert(1)',
      'data:text/html,test',
      'marginmind://open',
      'https://example.com\\x',
    ]) {
      expect(() => BrowserPolicy.normalize(input), throwsA(isA<BrowserUrlException>()), reason: input);
    }
    expect(
      () => BrowserPolicy.normalize(''),
      throwsA(isA<BrowserUrlException>().having((e) => e.code, 'code', BrowserUrlError.empty)),
    );
    expect(BrowserPolicy.allowsNavigation(Uri.parse('https://example.com'), download: true), isFalse);
    for (final url in ['file:///a', 'custom://x', 'data:text/plain,a', 'about:blank', 'https:relative']) {
      expect(BrowserPolicy.allowsNavigation(Uri.parse(url)), isFalse);
    }
    for (final platform in TargetPlatform.values) {
      expect(MMPlatformCapabilities(platform, web: true).webBrowser, isFalse);
      expect(
        MMPlatformCapabilities(platform).webBrowser,
        !{TargetPlatform.linux, TargetPlatform.fuchsia}.contains(platform),
      );
    }
  });
  test('requires load + 800ms silence; 15s limit; errors stay failed', () {
    final state = BrowserReadiness(Duration.zero);
    state.activity(const Duration(seconds: 1));
    expect(state.tick(const Duration(seconds: 2)), BrowserPhase.loading);
    state.finish(const Duration(seconds: 2));
    expect(state.tick(const Duration(milliseconds: 2799)), BrowserPhase.loading);
    expect(state.tick(const Duration(milliseconds: 2800)), BrowserPhase.ready);
    state.activity(const Duration(seconds: 3));
    expect(state.tick(const Duration(milliseconds: 3500)), BrowserPhase.loading);
    expect(state.tick(const Duration(milliseconds: 3800)), BrowserPhase.ready);
    final slow = BrowserReadiness(Duration.zero);
    expect(slow.tick(const Duration(milliseconds: 14999)), BrowserPhase.loading);
    expect(slow.tick(const Duration(seconds: 15)), BrowserPhase.slow);
    slow.finish(const Duration(seconds: 16));
    expect(slow.tick(const Duration(milliseconds: 16800)), BrowserPhase.ready);
    slow.fail();
    expect(slow.tick(const Duration(seconds: 30)), BrowserPhase.failed);
  });
  Future<void> event(BrowserSession s, String kind, {int id = 1}) async {
    final data = const StandardMethodCodec().encodeMethodCall(
      MethodCall('event', {'kind': kind, 'navigationId': id, 'url': s.url.toString(), 'back': true, 'forward': false}),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      'marginmind/browser/${s.id}',
      data,
      (_) {},
    );
  }

  testWidgets('session: capture, SPA, stale responses, prompt and native errors', (tester) async {
    var elapsed = Duration.zero;
    final s = BrowserSession(Uri.parse('https://example.com/'), elapsed: () => elapsed);
    final calls = <String>[];
    var page = s.url.toString(), fail = false, windows = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      MethodChannel('marginmind/browser/${s.id}'),
      (call) async {
        calls.add(call.method);
        if (fail) throw PlatformException(code: 'test');
        if (call.method != 'evaluate') return null;
        final capture = ((call.arguments as Map)['script'] as String).contains('outerHTML');
        final value = jsonEncode(
          capture
              ? {
                  'url': page,
                  'title': 'Page',
                  'dom': '<html>saved</html>',
                  'resources': ['https://example.com/a.png'],
                }
              : {'url': page, 'title': 'Page', 'dom': 0, 'network': 0, 'complete': true},
        );
        return windows ? jsonEncode(value) : value;
      },
    );
    await s.attach();
    await s.attach();
    await event(s, 'start');
    await event(s, 'loaded');
    await tester.pump(const Duration(milliseconds: 200));
    elapsed += const Duration(milliseconds: 850);
    await tester.pump(const Duration(milliseconds: 200));
    expect(s.phase, BrowserPhase.ready);
    expect(s.prompt, isTrue);
    expect(s.canGoBack, isTrue);
    expect(s.canGoForward, isFalse);
    s.dismissPrompt();
    expect(s.prompt, isFalse);
    final generation = s.navigationId;
    final capture = await s.capture(navigationId: generation);
    expect(capture.dom, contains('saved'));
    expect(capture.resources.single.path, '/a.png');
    expect(capture.url, s.url);
    expect(capture.navigationId, generation);
    expect(capture.capturedAt.isUtc, isTrue);
    windows = true;
    expect((await s.capture(navigationId: generation)).title, 'Page');
    await s.back();
    await s.forward();
    await s.reload();
    expect(calls, containsAll(['navigate', 'back', 'forward', 'reload']));
    page = 'https://example.com/spa';
    await tester.pump(const Duration(milliseconds: 200));
    expect(s.navigationId, greaterThan(generation));
    await expectLater(s.capture(navigationId: generation), throwsStateError);
    await event(s, 'start', id: 2);
    await event(s, 'failed', id: 1);
    expect(s.phase, BrowserPhase.loading);
    await event(s, 'failed', id: 2);
    expect(s.phase, BrowserPhase.failed);
    await s.stop();
    fail = true;
    await s.reload();
    s.dispose();
    s.dispose();
    expect(s.disposed, isTrue);
    await s.back();
    await expectLater(s.capture(navigationId: s.navigationId), throwsStateError);
    await expectLater(s.navigate(Uri.parse('file:///a')), throwsArgumentError);
  });
  testWidgets('clearData disposes live tabs', (tester) async {
    final s = BrowserSession(Uri.parse('https://example.com/'));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('marginmind/browser'),
      (call) async => null,
    );
    await BrowserSession.clearData();
    expect(s.disposed, isTrue);
    expect(() => BrowserSession(Uri.parse('file:///a')), throwsArgumentError);
  });
  testWidgets('Windows native host uses physical bounds and hides with its tab', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final s = BrowserSession(Uri.parse('https://example.com/'));
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('marginmind/browser'),
      (call) async {
        calls.add(call);
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      MethodChannel('marginmind/browser/${s.id}'),
      (call) async {
        calls.add(call);
        return null;
      },
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MMBrowserView(session: s),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls.any((call) => call.method == 'create'), isTrue);
    expect(calls.any((call) => call.method == 'bounds' && (call.arguments as Map)['visible'] == true), isTrue);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MMBrowserView(session: s, visible: false),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect((calls.lastWhere((call) => call.method == 'bounds').arguments as Map)['visible'], isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    s.dispose();
    await BrowserSession.clearData();
    expect(calls.where((call) => call.method == 'create').length, 2);
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('unsupported platform never creates a native surface', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final s = BrowserSession(Uri.parse('https://example.com/'));
    await tester.pumpWidget(MMBrowserView(session: s));
    expect(find.byType(MMBrowserView), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    s.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('about:blank and old documents cannot mark a provisional load ready', (tester) async {
    var now = Duration.zero;
    var observedUrl = 'about:blank';
    final s = BrowserSession(Uri.parse('https://example.com/'), elapsed: () => now);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      MethodChannel('marginmind/browser/${s.id}'),
      (call) async => call.method == 'evaluate'
          ? jsonEncode({'url': observedUrl, 'title': '', 'dom': 0, 'network': 0, 'complete': true})
          : null,
    );
    await s.attach();
    await tester.pump(const Duration(milliseconds: 200));
    now = const Duration(seconds: 1);
    await tester.pump(const Duration(milliseconds: 200));
    expect(s.canCapture, isFalse);
    observedUrl = s.url.toString();
    await tester.pump(const Duration(milliseconds: 200));
    now = const Duration(seconds: 2);
    await tester.pump(const Duration(milliseconds: 200));
    expect(s.phase, BrowserPhase.loading);
    await event(s, 'loaded');
    now = const Duration(seconds: 3);
    await tester.pump(const Duration(milliseconds: 200));
    expect(s.phase, BrowserPhase.ready);
    s.dispose();
  });
}
