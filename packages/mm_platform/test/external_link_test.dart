import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_platform/mm_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/external_link');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('only web pages leave the app', () async {
    expect(ExternalLinks.canOpen(Uri.parse('https://example.com/a')), isTrue);
    expect(ExternalLinks.canOpen(Uri.parse('http://example.com')), isTrue);
    for (final url in ['file:///etc/hosts', 'javascript:alert(1)', 'mailto:a@b.c', 'https:///path', '/relative']) {
      expect(ExternalLinks.canOpen(Uri.parse(url)), isFalse, reason: url);
    }
    final calls = <Object?>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.arguments);
      return true;
    });
    const links = ExternalLinks(channel);
    expect(await links.open(Uri.parse('file:///etc/hosts')), isFalse);
    expect(calls, isEmpty);
    expect(await links.open(Uri.parse('https://example.com/?q=锚定')), isTrue);
    expect((calls.single! as Map)['url'], 'https://example.com/?q=%E9%94%9A%E5%AE%9A');
  });

  test('a refusing or missing browser channel reports false', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => throw PlatformException(code: 'invalid_arguments'));
    expect(await const ExternalLinks(channel).open(Uri.parse('https://example.com')), isFalse);
    messenger.setMockMethodCallHandler(channel, null);
    expect(await const ExternalLinks(channel).open(Uri.parse('https://example.com')), isFalse);
  });
}
