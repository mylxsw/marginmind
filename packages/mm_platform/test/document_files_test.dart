import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_platform/mm_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/file_selector');
  test('picker offers all supported formats and returns selected paths', () async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'openFile');
      final args = call.arguments as Map;
      expect(args['multiple'], isTrue);
      expect((args['acceptedTypeGroups'] as List).single['extensions'], DocumentFormat.extensions);
      return ['/selected.epub', '/notes.md'];
    });
    final files = await MMDocumentFiles.pick('Documents');
    expect(files.map((f) => f.name), ['selected.epub', 'notes.md']);
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await MMDocumentFiles.pick('Documents'), isEmpty);
  });

  testWidgets('desktop drop bridge preserves file records and clears hover; mobile skips the plugin', (tester) async {
    final hover = <bool>[];
    List<MMDocumentFile>? dropped;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MMFileDropTarget(
          onHover: hover.add,
          onDrop: (files) => dropped = files,
          child: const SizedBox(width: 100, height: 100),
        ),
      ),
    );
    if (defaultTargetPlatform == TargetPlatform.android) {
      expect(find.byType(DropTarget), findsNothing);
      return;
    }
    final target = tester.widget<DropTarget>(find.byType(DropTarget));
    final event = DropEventDetails(localPosition: Offset.zero, globalPosition: Offset.zero);
    target.onDragEntered!(event);
    target.onDragExited!(event);
    target.onDragDone!(
      DropDoneDetails(files: [DropItemFile('/book.epub')], localPosition: Offset.zero, globalPosition: Offset.zero),
    );
    expect(hover, [true, false, false]);
    expect(dropped, [(path: '/book.epub', name: 'book.epub')]);
  }, variant: TargetPlatformVariant({TargetPlatform.macOS, TargetPlatform.android}));

  test('relative resources stay under the source directory including symlinks', () async {
    final directory = await Directory.systemTemp.createTemp('mm_document_files');
    addTearDown(() => directory.delete(recursive: true));
    final child = await Directory('${directory.path}/child').create();
    final source = File('${child.path}/note.md');
    await source.writeAsString('# Test');
    await File('${child.path}/image.png').writeAsBytes([1, 2, 3]);
    expect(await MMDocumentFiles.readRelativeResource(source.path, 'image.png'), [1, 2, 3]);
    expect(await MMDocumentFiles.read(source.path), isNotEmpty);
    await expectLater(MMDocumentFiles.read(source.path, maxBytes: 1), throwsFormatException);
    await File('${directory.path}/private.png').writeAsBytes([9]);
    await Link('${child.path}/link.png').create('${directory.path}/private.png');
    for (final path in ['../private.png', 'link.png', 'file:///private.png', 'https://example.com/x', '/private.png']) {
      expect(await MMDocumentFiles.readRelativeResource(source.path, path), isNull);
    }
  });
}
