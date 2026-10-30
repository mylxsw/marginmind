/// Local PNG previews: set MM_SCREENSHOTS to an output directory and MM_FONT
/// to a CJK font, then run vocabulary_screen_test.dart and vocabulary_hints_test.dart with --plain-name screenshot.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter/services.dart';

final _output = Platform.environment['MM_SCREENSHOTS'];
final _font = Platform.environment['MM_FONT'];
final vocabularyScreenshotsEnabled = _output != null && _font != null;

Future<void> loadVocabularyScreenshotFonts() async {
  if (!vocabularyScreenshotsEnabled) return;
  Directory(_output!).createSync(recursive: true);
  final bytes = ByteData.sublistView(await File(_font!).readAsBytes());
  for (final family in [
    '.AppleSystemUIFont',
    'CupertinoSystemText',
    'CupertinoSystemDisplay',
    'Roboto',
    'PingFang SC',
    'Songti SC',
  ]) {
    await (FontLoader(family)..addFont(Future.value(bytes))).load();
  }
  final cache = Platform.environment['PUB_CACHE'] ?? '${Platform.environment['HOME']}/.pub-cache';
  final icons = Directory('$cache/hosted/pub.dev')
      .listSync()
      .whereType<Directory>()
      .lastWhere((d) => d.path.contains('cupertino_icons-'));
  await (FontLoader(
        'packages/cupertino_icons/CupertinoIcons',
      )..addFont(Future.value(ByteData.sublistView(File('${icons.path}/assets/CupertinoIcons.ttf').readAsBytesSync()))))
      .load();
  await (FontLoader(
    'packages/lucide_icons_flutter/Lucide',
  )..addFont(rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'))).load();
}

Future<void> saveVocabularyHintScreenshot(WidgetTester tester, String name, Finder target) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(target);
  final image = (await tester.runAsync(() => boundary.toImage(pixelRatio: 2)))!;
  try {
    final png = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png)))!;
    await tester.runAsync(() => File('$_output/$name.png').writeAsBytes(png.buffer.asUint8List()));
  } finally {
    image.dispose();
  }
}
