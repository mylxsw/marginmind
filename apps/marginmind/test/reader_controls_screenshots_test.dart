/// Export the actual reader controls for comparison with the approved design.
/// MM_READER_SHOTS=/absolute/output MM_FONT=/path/to/CJK.ttf flutter test test/reader_controls_screenshots_test.dart
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/reader_compare.dart';
import 'package:marginmind/features/workspace/reader_crop.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import '../../../packages/mm_pdf/test/support/pdf_backend.dart';
import 'helpers.dart';
import 'reader_compare_test.dart' show compareFixture, CompareOcr;

import 'package:marginmind/features/workspace/reader_ocr.dart';

import 'reader_crop_test.dart' show drain;

final _out = Platform.environment['MM_READER_SHOTS'];
final _font = Platform.environment['MM_FONT'];

Future<void> _fonts() async {
  final cjk = ByteData.sublistView(File(_font!).readAsBytesSync());
  final latinPath = Platform.environment['MM_LATIN_FONT'];
  final latin = latinPath == null ? cjk : ByteData.sublistView(File(latinPath).readAsBytesSync());
  for (final family in ['.AppleSystemUIFont', 'CupertinoSystemText', 'CupertinoSystemDisplay', 'Roboto']) {
    await (FontLoader(family)
          ..addFont(Future.value(latin))
          ..addFont(Future.value(cjk)))
        .load();
  }
  await (FontLoader('PingFang SC')..addFont(Future.value(cjk))).load();
  final symbols = Platform.environment['MM_SYMBOL_FONT'];
  if (symbols != null) {
    // Use an existing fallback slot so shortcut symbols are visible in exports.
    await (FontLoader(
      'Noto Sans SC',
    )..addFont(Future.value(ByteData.sublistView(File(symbols).readAsBytesSync())))).load();
  }
  await (FontLoader(
    'packages/lucide_icons_flutter/Lucide',
  )..addFont(rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'))).load();
  final pub = Platform.environment['PUB_CACHE'] ?? '${Platform.environment['HOME']}/.pub-cache';
  final icons = Directory('$pub/hosted/pub.dev')
      .listSync()
      .whereType<Directory>()
      .lastWhere((d) => d.path.contains('cupertino_icons-'));
  await (FontLoader(
        'packages/cupertino_icons/CupertinoIcons',
      )..addFont(Future.value(ByteData.sublistView(File('${icons.path}/assets/CupertinoIcons.ttf').readAsBytesSync()))))
      .load();
}

Future<void> _save(WidgetTester tester, String name, {Rect? bounds}) async {
  final view = tester.binding.renderViews.first;
  final image = (await tester.runAsync(
    () => (view.debugLayer! as OffsetLayer).toImage(
      (bounds ?? Offset.zero & view.size).intersect(Offset.zero & view.size),
      pixelRatio: 2,
    ),
  ))!;
  final png = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png)))!;
  await tester.runAsync(() => File('$_out/$name.png').writeAsBytes(png.buffer.asUint8List()));
  image.dispose();
}

void main() {
  final skip = _out == null || _font == null;
  setUpAll(() async {
    if (skip) return;
    Directory(_out!).createSync(recursive: true);
    await _fonts();
  });
  for (final dark in [true, false]) {
    testWidgets(
      'reader chrome ${dark ? 'dark' : 'light'}',
      (tester) async {
        installTestPdfBackend();
        final base = compareFixture();
        final content = InMemoryStudySetContentRepository({
          'demo-1': base.copyWith(
            documents: [for (final doc in base.documents) doc.copyWith(cropSuggestionDismissed: true)],
          ),
        });
        final container = await pumpApp(
          tester,
          renderPdf: true,
          content: content,
          size: const Size(1280, 820),
          prefs: {
            'settings.appearance': dark ? 'dark' : 'light',
            'settings.language': 'zh',
            'settings.readerStyle': 'dark',
          },
          overrides: [
            pdfOcrServiceProvider.overrideWithValue(CompareOcr()),
            compareDocumentInfoProvider(('demo-1', 'c1')).overrideWith((ref) async => (language: 'zh', hasText: true)),
            compareDocumentInfoProvider(('demo-1', 'c2')).overrideWith((ref) async => (language: 'en', hasText: true)),
          ],
        );
        container.read(navigationProvider.notifier).openStudySet('demo-1');
        await drain(tester);
        await container.read(readerCompareProvider('demo-1').notifier).select('c2', readerWidth: 700);
        await drain(tester);
        final name = dark ? 'dark' : 'light';
        await _save(tester, 'workspace-$name');
        final reader = tester.getRect(find.byType(ReaderPane));
        await _save(tester, 'header-$name', bounds: Rect.fromLTWH(reader.left, reader.top, reader.width, 80));
        final controls = tester.getRect(find.byKey(const ValueKey('compare-floating-controls')));
        await _save(tester, 'divider-$name', bounds: Rect.fromCenter(center: controls.center, width: 100, height: 140));
        for (final (key, label) in [
          ('reader-more', 'zoom'),
          ('reader-crop', 'crop'),
          ('reader-appearance', 'appearance'),
          ('reader-compare', 'compare'),
        ]) {
          await tapReaderCommand(tester, find.byKey(ValueKey(key)));
          await tester.pumpAndSettle();
          final popup = find.byWidgetPredicate(
            (w) =>
                w is Material &&
                w.shape is RoundedRectangleBorder &&
                (w.shape as RoundedRectangleBorder).borderRadius == BorderRadius.circular(MMRadii.dropdown),
          );
          final rect = tester.getRect(label == 'crop' ? find.byKey(const ValueKey('crop-editor-toolbar')) : popup.last);
          await _save(tester, '$label-$name', bounds: rect.inflate(2));
          await _save(tester, '$label-$name-full');
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
        }
        tester.view.physicalSize = const Size(1000, 700);
        await drain(tester);
        await _save(tester, 'workspace-$name-narrow');
        await container.read(readerCompareProvider('demo-1').notifier).exit();
        tester.view.physicalSize = const Size(1280, 820);
        final workspace = container.read(workspaceProvider('demo-1').notifier);
        workspace.setLayout(MMSplitMode.split);
        if (!container.read(workspaceProvider('demo-1')).readerPanelVisible) workspace.toggleReaderPanel();
        workspace.setSplitFraction(.1);
        await drain(tester);
        await container.read(readerCropProvider('demo-1').notifier).adjust();
        await drain(tester);
        await _save(tester, 'crop-$name-narrow');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await drain(tester);
      },
      skip: skip,
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }
}
