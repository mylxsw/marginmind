import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_platform/mm_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.macOS);
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  const channel = MethodChannel('plugins.flutter.io/file_selector');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test('system save supports cancellation and writes Markdown with relative image assets', () async {
    final directory = await Directory.systemTemp.createTemp('mm-note-export-');
    addTearDown(() => directory.delete(recursive: true));
    final bytes = Uint8List.fromList([35, 32, 65]);
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await MMNoteFiles.save('note.md', bytes), isFalse);
    final destination = '${directory.path}/note.md';
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getSavePath');
      expect((call.arguments as Map)['suggestedName'], 'note.md');
      return destination;
    });
    expect(await MMNoteFiles.save('note.md', bytes, attachments: {'attachments/image.png': bytes}), isTrue);
    expect(await MMNoteFiles.read(destination), bytes);
    expect(await MMNoteFiles.exists(destination), isTrue);
    expect(await MMNoteFiles.exists('$destination-missing'), isFalse);
    expect(await File('${directory.path}/attachments/image.png').readAsBytes(), bytes);
    for (final path in [
      '../secret',
      'attachments/../../secret',
      'attachments/../secret',
      'attachments/x/y',
      r'attachments/..\secret',
    ]) {
      await expectLater(MMNoteFiles.save('note.md', bytes, attachments: {path: bytes}), throwsArgumentError);
    }
  });
  test('PDF, DOCX and PNG use their own save-panel extensions', () async {
    for (final extension in ['pdf', 'docx', 'png', 'html']) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(
          (call.arguments as Map)['acceptedTypeGroups'],
          contains(predicate((dynamic group) => (group as Map)['extensions'].contains(extension))),
        );
        return null;
      });
      expect(await MMNoteFiles.save('note.$extension', Uint8List.fromList([1])), isFalse);
    }
  });
  test('mobile output invokes the system sharing bridge', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const share = MethodChannel('marginmind/file_share');
    messenger.setMockMethodCallHandler(share, (call) async {
      expect(call.method, 'share');
      expect((call.arguments as Map)['name'], 'note.docx');
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(share, null));
    expect(await MMNoteFiles.save('note.docx', Uint8List.fromList([1])), isTrue);
  });
  test('export does not follow attachment directory or file symlinks', () async {
    final directory = await Directory.systemTemp.createTemp('mm-note-safe-');
    addTearDown(() => directory.delete(recursive: true));
    final outside = await Directory('${directory.path}/outside').create();
    final selected = await Directory('${directory.path}/selected').create();
    await Link('${selected.path}/attachments').create(outside.path);
    messenger.setMockMethodCallHandler(channel, (_) async => '${selected.path}/note.md');
    await expectLater(
      MMNoteFiles.save(
        'note.md',
        Uint8List.fromList([1]),
        attachments: {
          'attachments/image.png': Uint8List.fromList([2]),
        },
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await File('${outside.path}/image.png').exists(), isFalse);
    expect(await File('${selected.path}/note.md').exists(), isFalse);
  });
}
