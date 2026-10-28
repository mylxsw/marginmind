import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_platform/mm_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  test('capabilities reflect shipped implementations, never viewport or web host', () {
    for (final platform in TargetPlatform.values) {
      final c = MMPlatformCapabilities(platform);
      final mobile = platform == TargetPlatform.iOS || platform == TargetPlatform.android;
      final mac = platform == TargetPlatform.macOS;
      expect(c.mobile, mobile);
      expect(c.assistant, isTrue);
      expect(c.externalCredentials, isTrue);
      expect(c.secretStore, mobile || mac);
      expect(c.externalLink, mobile || mac);
      expect(c.shareFile, mobile);
      expect(c.desktopDrop, !mobile && platform != TargetPlatform.fuchsia);
      expect([c.articleParser, c.pdfOcr, c.mapExport, c.nativeMapClipboard], everyElement(mac));
      final web = MMPlatformCapabilities(platform, web: true);
      expect([
        web.mobile,
        web.assistant,
        web.externalCredentials,
        web.secretStore,
        web.externalLink,
        web.shareFile,
        web.desktopDrop,
        web.articleParser,
        web.pdfOcr,
        web.mapExport,
        web.nativeMapClipboard,
      ], everyElement(false));
    }
  });
  test('mobile parser returns unsupported before loading script or calling native', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(MMPlatformCapabilities.current.shareFile, isTrue);
    final parser = WebKitArticleParser(script: () => throw StateError('must not load'));
    await expectLater(
      parser.parse(Uri.parse('https://example.com'), '', CancellationToken()),
      throwsA(isA<ResearchFailure>().having((e) => e.kind, 'kind', ResearchFailureKind.unsupported)),
    );
  });
  test('sharing handles successful handoff, cancellation, invalid data and native failure', () async {
    const channel = MethodChannel('marginmind/file_share');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    Object? answer = true;
    MethodCall? seen;
    messenger.setMockMethodCallHandler(channel, (call) async {
      seen = call;
      return answer;
    });
    const share = MobileFileShare();
    final data = Uint8List.fromList([1, 2]);
    expect(await share.share('notes.md', data), isTrue);
    expect(seen!.method, 'share');
    expect(seen!.arguments, {'name': 'notes.md', 'bytes': data});
    for (final value in [false, null]) {
      answer = value;
      expect(await share.share('notes.opml', data), isFalse);
    }
    for (final name in ['', '../x', 'a\\b', 'a\n']) {
      await expectLater(share.share(name, data), throwsArgumentError);
    }
    await expectLater(share.share('x', Uint8List(0)), throwsArgumentError);
    messenger.setMockMethodCallHandler(channel, (_) async => throw PlatformException(code: 'share_failed'));
    await expectLater(share.share('x', data), throwsA(isA<PlatformException>()));
  });
}
