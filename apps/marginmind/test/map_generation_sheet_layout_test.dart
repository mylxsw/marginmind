import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/features/map_generation/map_generation_controller.dart';
import 'package:marginmind/features/map_generation/widgets/generate_map_sheet.dart';
import 'package:marginmind/features/map_generation/widgets/map_generation_structure_preview.dart';
import 'package:marginmind/features/map_generation/widgets/map_source_range.dart';
import 'package:mm_design/mm_design.dart';

import 'map_generation_ui_test.dart' as harness;

final _screenshots = Platform.environment['MM_SHEET_SCREENSHOTS'];

Future<void> _open(WidgetTester tester) async {
  unawaited(
    showMMSheet<void>(
      context: tester.element(find.byType(Overlay).first),
      width: MMSizes.mapGenerateSheetWidth,
      builder: (_) => const GenerateMapSheet(studySetId: 'demo-1'),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester, String name) async {
  if (_screenshots == null) return;
  final image = (await tester.runAsync(() {
    final view = tester.binding.renderViews.first;
    return (view.debugLayer! as OffsetLayer).toImage(Offset.zero & view.size, pixelRatio: 1);
  }))!;
  final png = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png)))!;
  await tester.runAsync(() async {
    await Directory(_screenshots!).create(recursive: true);
    await File('$_screenshots/$name.png').writeAsBytes(png.buffer.asUint8List());
  });
  image.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (_screenshots == null) return;
    for (final family in ['.AppleSystemUIFont', 'CupertinoSystemText', 'CupertinoSystemDisplay', 'Roboto']) {
      final bytes = ByteData.sublistView(await File('/System/Library/Fonts/SFNS.ttf').readAsBytes());
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
    final pingFang = Directory('/System/Library/AssetsV2/com_apple_MobileAsset_Font8')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('/PingFang.ttc'))
        .first;
    await (FontLoader('PingFang SC')..addFont(Future.value(ByteData.sublistView(await pingFang.readAsBytes())))).load();
    for (final asset in [
      ('packages/cupertino_icons/CupertinoIcons', 'packages/cupertino_icons/assets/CupertinoIcons.ttf'),
      ('packages/lucide_icons_flutter/Lucide', 'packages/lucide_icons_flutter/assets/lucide.ttf'),
    ]) {
      await (FontLoader(asset.$1)..addFont(rootBundle.load(asset.$2))).load();
    }
  });

  testWidgets('source drafts cannot generate and Escape preserves the applied source and instructions', (tester) async {
    final container = await harness.openWorkspace(tester);
    await _open(tester);
    final input = find.descendant(
      of: find.byKey(const ValueKey('map-generate-instructions')),
      matching: find.byType(TextField),
    );
    await tester.enterText(input, '梳理概念之间的关系');
    await tester.tap(find.byKey(const ValueKey('map-generate-change-sources')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('map-document-check-c1')));
    await tester.pumpAndSettle();
    expect(tester.widget<MMButton>(find.byKey(const ValueKey('map-generate-apply-sources'))).onPressed, isNull);
    await harness.key(tester, LogicalKeyboardKey.enter, primary: true);
    expect(container.read(mapGenerationControllerProvider('demo-1')), isNull);
    await harness.key(tester, LogicalKeyboardKey.escape);
    expect(find.byType(GenerateMapSheet), findsOneWidget);
    expect(find.descendant(of: find.byType(GenerateMapSheet), matching: find.text('学习的底层逻辑')), findsOneWidget);
    expect(tester.widget<TextField>(input).controller!.text, '梳理概念之间的关系');
    await harness.key(tester, LogicalKeyboardKey.escape);
    expect(find.byType(GenerateMapSheet), findsNothing);
  });

  testWidgets('leaving an invalid range restores the last usable selection', (tester) async {
    await harness.openWorkspace(tester);
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('map-range-toggle-c1')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(MapSourceRange), matching: find.byType(MMCheckbox)).first);
    await tester.pumpAndSettle();
    final generate = find.byKey(const ValueKey('map-generate-sheet-start-button'));
    expect(tester.widget<MMButton>(generate).onPressed, isNull);
    expect(tester.widget<MMButton>(find.byKey(const ValueKey('map-generate-range-done'))).onPressed, isNull);
    await harness.key(tester, LogicalKeyboardKey.escape);
    expect(tester.widget<MMButton>(generate).onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('map-range-toggle-c1')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<MMCheckbox>(find.descendant(of: find.byType(MapSourceRange), matching: find.byType(MMCheckbox)).first)
          .value,
      isTrue,
    );
  });

  for (final dark in [false, true]) {
    testWidgets('native ${dark ? 'dark' : 'light'} typography and progressively disclosed controls', (tester) async {
      await harness.openWorkspace(tester, prefs: {if (dark) 'settings.appearance': 'dark'});
      await _open(tester);
      final sheet = find.byType(GenerateMapSheet);
      expect(tester.getSize(sheet).width, MMSizes.mapGenerateSheetWidth);
      final heading = find.descendant(of: sheet, matching: find.text('生成脑图')).first;
      expect(tester.widget<Text>(heading).style, tester.element(sheet).mmText.title3);
      final field = find.descendant(
        of: find.byKey(const ValueKey('map-generate-instructions')),
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(field).style, tester.element(sheet).mmText.body);
      expect(find.descendant(of: sheet, matching: find.byType(MMSwitch)), findsNothing);
      expect(find.byType(MapGenerationStructurePreview), findsOneWidget);
      await _save(tester, 'sheet_${dark ? 'dark' : 'light'}');
      await tester.tap(find.byKey(const ValueKey('map-generate-organization-question')));
      await tester.tap(find.byKey(const ValueKey('map-generate-more-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('详细'));
      await tester.pumpAndSettle();
      await _save(tester, 'settings_${dark ? 'dark' : 'light'}');
      await harness.key(tester, LogicalKeyboardKey.escape);
      final preview = tester.widget<MapGenerationStructurePreview>(find.byType(MapGenerationStructurePreview));
      expect(preview.depth, 4);
      expect(preview.organization.name, 'question');
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [const Size(590, 620), const Size(390, 844)]) {
    testWidgets('compact sheet at $size keeps footer visible with a keyboard', (tester) async {
      await harness.openWorkspace(
        tester,
        overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(size.width < 600)],
      );
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      await _open(tester);
      final button = find.byKey(const ValueKey('map-generate-sheet-start-button'));
      expect(tester.getRect(button).bottom, lessThan(size.height));
      await _save(tester, 'compact_${size.width.toInt()}');
      await tester.tap(find.byKey(const ValueKey('map-generate-more-settings')));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();
      expect(tester.getRect(button).bottom, lessThanOrEqualTo(size.height - 260));
      await tester.ensureVisible(find.byKey(const ValueKey('map-generate-target-title')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await harness.key(tester, LogicalKeyboardKey.escape);
      await tester.tap(find.byKey(const ValueKey('map-range-toggle-c1')));
      await tester.pumpAndSettle();
      final checkbox = find.descendant(of: find.byType(MapSourceRange), matching: find.byType(MMCheckbox)).first;
      expect(tester.getSize(checkbox).height, greaterThanOrEqualTo(MMSizes.touchTarget));
      expect(tester.takeException(), isNull);
    });
  }
}
