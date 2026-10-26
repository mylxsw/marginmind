import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_platform/mm_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('marginmind/pdf_ocr_test');
  final binding = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const metadata = {
    'path': '/documents/hash.ocr.pdf',
    'pageCount': 3,
    'textPages': [1, 2],
    'hasCopy': true,
  };
  late VisionPdfOcr service;
  setUp(() => service = VisionPdfOcr(channel: channel));
  tearDown(() {
    binding.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> emit(String method, Map<String, Object> arguments) async {
    final done = Completer<void>();
    binding.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments)),
      (_) => done.complete(),
    );
    await done.future;
  }

  test('platform support and metadata', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(service.supported, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(service.supported, isFalse);
    binding.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'inspect');
      expect(call.arguments, {'source': '/documents/hash.pdf'});
      return metadata;
    });
    final info = await service.inspect('/documents/hash.pdf');
    expect(info.path, '/documents/hash.ocr.pdf');
    expect(info.pageCount, 3);
    expect(info.textPages, {1, 2});
    expect(info.hasCopy, isTrue);
    expect(() => info.textPages.add(3), throwsUnsupportedError);
  });

  test('range, languages, scoped progress, cancellation and callback cleanup', () async {
    final result = Completer<Map<String, Object>>();
    final calls = <MethodCall>[];
    binding.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'recognize') return result.future;
      return null;
    });
    final progress = <(int, int)>[];
    final future = service.recognize(
      '/documents/hash.pdf',
      id: 'job',
      first: 2,
      last: 3,
      language: PdfOcrLanguage.chineseEnglish,
      onProgress: (done, total) => progress.add((done, total)),
    );
    await Future<void>.delayed(Duration.zero);
    expect(calls.single.arguments, {
      'source': '/documents/hash.pdf',
      'id': 'job',
      'first': 2,
      'last': 3,
      'languages': ['zh-Hans', 'en-US'],
    });
    await emit('unknown', {});
    await emit('progress', {'id': 'old', 'done': 2, 'total': 2});
    await emit('progress', {'id': 'job', 'done': 1, 'total': 2});
    expect(progress, [(1, 2)]);
    await service.cancel('job');
    expect(calls.last.method, 'cancel');
    expect(calls.last.arguments, {'id': 'job'});
    result.complete({...metadata, 'cancelled': true});
    final recognized = await future;
    expect(recognized.cancelled, isTrue);
    expect(recognized.document.textPages, {1, 2});
    await emit('progress', {'id': 'job', 'done': 2, 'total': 2});
    expect(progress, [(1, 2)]);
    expect(PdfOcrLanguage.chinese.codes, ['zh-Hans']);
    expect(PdfOcrLanguage.english.codes, ['en-US']);
  });

  test('invalid requests and platform failures propagate and release jobs', () async {
    Future<void> request({int first = 1, int last = 1, String id = 'job'}) async {
      await service.recognize(
        '/sample.pdf',
        id: id,
        first: first,
        last: last,
        language: PdfOcrLanguage.english,
        onProgress: (_, _) {},
      );
    }

    await expectLater(request(first: 0), throwsArgumentError);
    await expectLater(request(first: 2, last: 1), throwsArgumentError);
    await expectLater(request(id: ''), throwsArgumentError);
    final gate = Completer<void>();
    binding.setMockMethodCallHandler(channel, (call) async {
      await gate.future;
      throw PlatformException(code: 'failed');
    });
    final pending = request();
    await expectLater(request(), throwsArgumentError);
    final assertion = expectLater(pending, throwsA(isA<PlatformException>()));
    gate.complete();
    await assertion;
    binding.setMockMethodCallHandler(channel, (_) async => {...metadata, 'cancelled': false});
    await request();
  });
}
