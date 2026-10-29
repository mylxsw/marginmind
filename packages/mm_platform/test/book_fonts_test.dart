import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:mm_platform/src/book_fonts.dart' show BookFontRegistry;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('deduplicates concurrent and completed faces and retries failures', () async {
    var calls = 0;
    final gate = Completer<void>();
    final registry = BookFontRegistry((_, bytes) async {
      calls++;
      expect(bytes.first, 1);
      await gate.future;
    });
    final bytes = Uint8List.fromList([1, 2]);
    final first = registry.load('family', bytes);
    expect(registry.load('family', Uint8List.fromList([1, 2])), same(first));
    bytes[0] = 9;
    gate.complete();
    await first;
    await registry.load('family', Uint8List.fromList([1, 2]));
    expect(calls, 1);
    await registry.load('family', Uint8List.fromList([1, 3]));
    await registry.load('other-family', Uint8List.fromList([1, 2]));
    expect(calls, 3);
    var attempts = 0;
    final retry = BookFontRegistry((_, _) async {
      if (attempts++ == 0) throw StateError('Unavailable');
    });
    await expectLater(retry.load('retry', bytes), throwsStateError);
    await retry.load('retry', bytes);
    expect(attempts, 2);
  });
  test('registers a real font with an isolated alias and rejects invalid inputs', () async {
    // Flutter distributes this font in its SDK artifacts on every test host.
    final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
    final bytes = await File('${artifacts.path}/material_fonts/Roboto-Regular.ttf').readAsBytes();
    await MMBookFonts.load('mmbook-test-publisher', bytes);
    final painter = TextPainter(
      text: const TextSpan(
        text: 'Publisher font',
        style: TextStyle(fontFamily: 'mmbook-test-publisher', fontSize: 16),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    expect(painter.width, isPositive);
    expect(painter.height, isPositive);
    painter.dispose();
    await expectLater(MMBookFonts.load('', bytes), throwsArgumentError);
    await expectLater(MMBookFonts.load('empty', Uint8List(0)), throwsArgumentError);
    await expectLater(MMBookFonts.load('oversized', Uint8List(16 * 1024 * 1024 + 1)), throwsArgumentError);
  });
}
