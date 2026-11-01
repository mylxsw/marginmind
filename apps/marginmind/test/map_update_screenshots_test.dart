import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/map_generation/map_generation_controller.dart';
import 'package:marginmind/features/map_generation/widgets/update_map_sheet.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'map_generation_ui_test.dart' show openWorkspace, runGeneration;
import 'map_update_test.dart' show updateFixture, updateEngine;

final _out = Platform.environment['MM_SCREENSHOTS'];
final _font = Platform.environment['MM_FONT'];
final _skip = _out == null || _font == null;
Future<void> _loadFonts() async {
  final fontFile = File(_font!);
  if (fontFile.existsSync()) {
    final bytes = ByteData.sublistView(await fontFile.readAsBytes());
    for (final family in [
      '.AppleSystemUIFont',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      'Roboto',
      'PingFang SC',
      'Songti SC',
      'SF Mono',
    ]) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
  }
  final pub = Platform.environment['PUB_CACHE'] ?? '${Platform.environment['HOME']}/.pub-cache';
  final iconsDir = Directory('$pub/hosted/pub.dev')
      .listSync()
      .whereType<Directory>()
      .lastWhere((d) => d.path.contains('cupertino_icons-'), orElse: () => Directory(''));
  if (iconsDir.path.isNotEmpty) {
    final iconFile = File('${iconsDir.path}/assets/CupertinoIcons.ttf');
    if (iconFile.existsSync()) {
      await (FontLoader(
        'packages/cupertino_icons/CupertinoIcons',
      )..addFont(Future.value(ByteData.sublistView(iconFile.readAsBytesSync())))).load();
    }
  }
  final lucideDir = Directory('$pub/hosted/pub.dev')
      .listSync()
      .whereType<Directory>()
      .lastWhere((d) => d.path.contains('lucide_icons_flutter-'), orElse: () => Directory(''));
  if (lucideDir.path.isNotEmpty) {
    final lucideFile = File('${lucideDir.path}/assets/lucide.ttf');
    if (lucideFile.existsSync()) {
      final lucideBytes = ByteData.sublistView(lucideFile.readAsBytesSync());
      await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(Future.value(lucideBytes))).load();
      await (FontLoader('Lucide')..addFont(Future.value(lucideBytes))).load();
    }
  }
}

Future<void> _save(WidgetTester tester, String name) async {
  Directory(_out!).createSync(recursive: true);
  final image = (await tester.runAsync(() {
    final view = tester.binding.renderViews.first;
    return (view.debugLayer! as OffsetLayer).toImage(Offset.zero & view.size, pixelRatio: 1);
  }))!;
  final png = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png)))!;
  await tester.runAsync(() => File('$_out/$name.png').writeAsBytes(png.buffer.asUint8List()));
}

void main() {
  setUpAll(() async {
    if (!_skip) await _loadFonts();
  });
  for (final dark in [false, true]) {
    testWidgets('Scenes 11 and 12 ${dark ? 'dark' : 'light'}', skip: _skip, (tester) async {
      final before = updateFixture();
      final container = await openWorkspace(
        tester,
        content: InMemoryStudySetContentRepository({'demo-1': before}),
        prefs: {'settings.appearance': dark ? 'dark' : 'light'},
        overrides: [mapGeneratorProvider.overrideWithValue(() async => updateEngine())],
      );
      await tester.tap(find.byKey(const ValueKey('map-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('map-generate-menu-item')));
      await tester.pumpAndSettle();
      await _save(tester, 'scene_11_${dark ? 'dark' : 'light'}');
      Navigator.of(tester.element(find.byType(UpdateMapSheet))).pop();
      await tester.pumpAndSettle();
      await runGeneration(
        tester,
        () => container
            .read(mapGenerationControllerProvider('demo-1').notifier)
            .start(
              MapGenerationRequest(
                studySetId: 'demo-1',
                mapId: before.maps.first.id,
                title: '认知科学入门',
                sources: const [MapDocumentSelection(documentId: 'c1')],
                destination: MapGenerationDestination.update,
              ),
            ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byWidgetPredicate((w) => w is MMIconButton && w.icon == MMIcons.fitMap));
      await tester.pumpAndSettle();
      await _save(tester, 'scene_12_${dark ? 'dark' : 'light'}');
    });
  }
}
