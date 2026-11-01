import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/features/map_generation/map_generation_controller.dart';
import 'package:marginmind/features/map_generation/widgets/update_map_sheet.dart';
import 'package:mm_core/mm_core.dart';
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
    for (final phone in [false, true]) {
      testWidgets('Update dialog with long sources dark=$dark phone=$phone', skip: _skip, (tester) async {
        var before = updateFixture();
        before = before.copyWith(
          documents: [
            before.documents.first.copyWith(title: 'Sample chapter: The forgetting curve'),
            before.documents.last.copyWith(title: '华为数字化转型：企业持续有效增长的新引擎'),
            for (final (i, title) in [
              (1, '7人团队敏捷管理手册'),
              (2, '158-爱上跑步'),
              (3, '突发：币安遭黑客攻击，数十亿美元资产流出，或成历史金额最大被盗事件 - 吴说区块链'),
            ])
              Document(
                id: 'extra-$i',
                title: title,
                fileName: 'extra-$i.pdf',
                pageCount: 20,
                importedAt: before.documents.first.importedAt,
              ),
          ],
        );
        await openWorkspace(
          tester,
          content: InMemoryStudySetContentRepository({'demo-1': before}),
          prefs: {'settings.appearance': dark ? 'dark' : 'light'},
          overrides: [touchPlatformProvider.overrideWithValue(phone)],
        );
        if (phone) {
          tester.view.physicalSize = const Size(402, 874);
          await tester.pumpAndSettle();
        }
        showUpdateMapSheet(tester.element(find.byType(Navigator).first), 'demo-1', before.maps.first.id);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _save(tester, 'update_${phone ? 'phone' : 'desktop'}_${dark ? 'dark' : 'light'}');
        if (phone) {
          final input = find.descendant(of: find.byType(UpdateMapSheet), matching: find.byType(TextField));
          await tester.ensureVisible(input);
          await tester.tap(input);
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('map-update-close')).hitTestable(), findsOneWidget);
          expect(find.byKey(const ValueKey('map-update-preview')).hitTestable(), findsOneWidget);
          await _save(tester, 'update_phone_keyboard_${dark ? 'dark' : 'light'}');
          tester.view.resetViewInsets();
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(const ValueKey('map-update-close')));
        await tester.pumpAndSettle();
        expect(find.byType(UpdateMapSheet), findsNothing);
      });
    }
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
