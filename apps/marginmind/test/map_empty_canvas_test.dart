import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/map_generation/widgets/map_empty_state.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

const _title = '币安遭黑客攻击';
const _longTitle = '突发：币安遭黑客攻击，数十亿美元资产流出，或成历史金额最大被盗事件 - 吴说区块链';
final _out = Platform.environment['MM_SCREENSHOTS'];

Future<ProviderContainer> _open(
  WidgetTester tester, {
  Size size = const Size(1542, 1022),
  bool dark = true,
  String title = _title,
  String language = 'zh',
}) async {
  final document = Document(
    id: 'web-1',
    title: title,
    fileName: 'article.md',
    pageCount: 1,
    format: DocumentFormat.web,
    layout: DocumentLayout.reflow,
    importedAt: testNow,
    origin: DocumentOrigin(url: 'https://www.wublock123.com/article', capturedAt: testNow),
  );
  final container = await pumpApp(
    tester,
    size: size,
    content: InMemoryStudySetContentRepository({
      'demo-1': StudySetContent.empty.copyWith(documents: [document]),
    }),
    prefs: {
      'settings.language': language,
      'settings.appearance': dark ? 'dark' : 'light',
      'settings.betaFeaturesEnabled': true,
    },
    overrides: [assistantCredentialStateProvider.overrideWith((ref) async => AssistantCredentialState.ready)],
  );
  container.read(navigationProvider.notifier).openStudySet('demo-1');
  await tester.pumpAndSettle();
  final workspace = container.read(workspaceProvider('demo-1').notifier);
  await workspace.addMap('未命名脑图');
  workspace.setLayout(MMSplitMode.secondary);
  await tester.pumpAndSettle();
  return container;
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (_out == null) return;
  await tester.runAsync(() async {
    Directory(_out!).createSync(recursive: true);
    final view = tester.binding.renderViews.first;
    final image = await (view.debugLayer! as OffsetLayer).toImage(Offset.zero & view.size, pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$_out/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _loadFonts() async {
  // The same native font families as the application, with a CJK fallback.
  for (final entry in {
    '.AppleSystemUIFont': '/Library/Fonts/SF-Pro.ttf',
    'CupertinoSystemText': '/Library/Fonts/SF-Pro.ttf',
    'CupertinoSystemDisplay': '/Library/Fonts/SF-Pro.ttf',
    'Roboto': '/Library/Fonts/SF-Pro.ttf',
    'PingFang SC': '/System/Library/Fonts/PingFang.ttc',
  }.entries) {
    var file = File(entry.value);
    if (!file.existsSync()) file = File('/Library/Fonts/Arial Unicode.ttf');
    await (FontLoader(entry.key)..addFont(Future.value(ByteData.sublistView(await file.readAsBytes())))).load();
  }
  final pub = Platform.environment['PUB_CACHE'] ?? '${Platform.environment['HOME']}/.pub-cache';
  for (final directory in Directory('$pub/hosted/pub.dev').listSync().whereType<Directory>()) {
    final name = directory.uri.pathSegments.where((s) => s.isNotEmpty).last;
    final (String, String)? icon = name.startsWith('cupertino_icons-')
        ? ('packages/cupertino_icons/CupertinoIcons', 'CupertinoIcons.ttf')
        : name.startsWith('lucide_icons_flutter-')
        ? ('packages/lucide_icons_flutter/Lucide', 'lucide.ttf')
        : null;
    if (icon != null) {
      final data = ByteData.sublistView(await File('${directory.path}/assets/${icon.$2}').readAsBytes());
      await (FontLoader(icon.$1)..addFont(Future.value(data))).load();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (_out != null) await _loadFonts();
  });

  for (final dark in [true, false]) {
    testWidgets('canvas start ${dark ? 'dark' : 'light'} shows real source and creates a blank topic with plus', (
      tester,
    ) async {
      await _open(tester, dark: dark);
      expect(find.text('从资料生成脑图'), findsOneWidget);
      expect(find.byKey(const ValueKey('map-empty-state-source')), findsOneWidget);
      expect(find.text('来源：www.wublock123.com'), findsOneWidget);
      expect(find.byIcon(MMIcons.web), findsWidgets);
      final start = tester.widget<MMButton>(find.byKey(const ValueKey('map-empty-state-start-button')));
      expect(start.label, '生成脑图');
      final colors = tester.element(find.byType(MapEmptyState)).mmColors;
      expect(start.foregroundColor, colors.onResearch);
      await _capture(tester, 'workspace-${dark ? 'dark' : 'light'}');
      await tester.tap(find.byKey(const ValueKey('map-empty-state-source-add')));
      await tester.pumpAndSettle();
      expect(find.byType(MapEmptyState), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('long source title, narrow pane, expanded text and short window keep controls reachable', (tester) async {
    await _open(tester, size: const Size(760, 540), title: _longTitle);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('map-empty-state-instructions'));
    await tester.ensureVisible(field);
    await tester.enterText(field, '保留原文关键句');
    await tester.pumpAndSettle();
    final sourceText = find.descendant(
      of: find.byKey(const ValueKey('map-empty-state-source')),
      matching: find.text(_longTitle),
    );
    expect(tester.widget<Text>(sourceText).maxLines, 2);
    expect(find.byTooltip(_longTitle), findsOneWidget);
    final blank = find.byKey(const ValueKey('map-empty-state-blank-button'));
    await tester.ensureVisible(blank);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await _capture(tester, 'workspace-narrow');
    await tester.tap(blank);
    await tester.pumpAndSettle();
    expect(find.byType(MapEmptyState), findsNothing);
  });

  testWidgets('English layout and manual instructions keep suggestion selection in sync', (tester) async {
    await _open(tester, language: 'en');
    final field = find.byKey(const ValueKey('map-empty-state-instructions'));
    await tester.enterText(field, 'Keep Key Quotes');
    await tester.pumpAndSettle();
    final chip = find.text('Keep Key Quotes').last;
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    await _capture(tester, 'workspace-english');
    expect(tester.takeException(), isNull);
  });
}
