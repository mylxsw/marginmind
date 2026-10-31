import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/map_generation/map_generation_controller.dart';
import 'package:marginmind/features/map_generation/widgets/map_generation_failure.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

final _screenshots = Platform.environment['MM_FAILURE_SCREENSHOTS'];

MapGenerationPreview preview({int failures = 1, bool long = false}) => MapGenerationPreview(
  request: const MapGenerationRequest(
    studySetId: 'set',
    mapId: 'map',
    title: '学习的底层逻辑',
    sources: [MapDocumentSelection(documentId: 'doc')],
  ),
  baseRevision: 0,
  proposalId: 'proposal',
  generation: MapGeneration(
    sources: [MapSource(documentId: 'doc', fingerprint: 'hash', readThrough: 2)],
    organization: MapOrganization.chapter,
    depth: 3,
    generatedAt: DateTime.utc(2026),
  ),
  skeletons: [for (var i = 0; i < failures; i++) MapSkeletonItem(id: 'chapter-$i', title: '第 ${i + 2} 页')],
  chapterFailures: {
    for (var i = 0; i < failures; i++)
      'chapter-$i': MapGenerationFailure(
        const ResearchFailure(ResearchFailureKind.protocol, 'noValidMapContent', 'private response body'),
        phase: MapLinePhase.chapter,
        model: long ? 'custom-provider/${'reasoning-model-' * 10}' : 'deepseek-flash',
        receivedLines: 27,
        acceptedLines: 0,
        rejections: {'unknownParent': 27},
        stopReason: 'stop',
        reasoningCharacters: 21832,
      ),
  },
);

Future<void> openFailure(
  WidgetTester tester, {
  Size size = const Size(960, 720),
  bool dark = true,
  bool phone = false,
  double scale = 1,
  String language = 'zh',
  MapGenerationPreview? data,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MMInput(
      touchPlatform: phone,
      phone: phone,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? MMTheme.dark() : MMTheme.light(),
        locale: Locale(language),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: MMButton(
                label: 'Open failure',
                onPressed: () => unawaited(showMapGenerationFailure(context, data ?? preview())),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open failure'));
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester, String name) async {
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

void failureTest(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (tester) async {
    final previousShadows = debugDisableShadows;
    try {
      if (_screenshots != null) debugDisableShadows = false;
      await body(tester);
    } finally {
      debugDisableShadows = previousShadows;
    }
  });
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
        .firstWhere((f) => f.path.endsWith('/PingFang.ttc'));
    await (FontLoader('PingFang SC')..addFont(Future.value(ByteData.sublistView(await pingFang.readAsBytes())))).load();
    await (FontLoader('SF Mono')
          ..addFont(Future.value(ByteData.sublistView(await File('/System/Library/Fonts/SFNSMono.ttf').readAsBytes()))))
        .load();
    for (final asset in [
      ('packages/cupertino_icons/CupertinoIcons', 'packages/cupertino_icons/assets/CupertinoIcons.ttf'),
      ('packages/lucide_icons_flutter/Lucide', 'packages/lucide_icons_flutter/assets/lucide.ttf'),
    ]) {
      await (FontLoader(asset.$1)..addFont(rootBundle.load(asset.$2))).load();
    }
  });

  failureTest('phone summary stays compact and copy includes hidden diagnostics', (tester) async {
    await openFailure(tester, size: const Size(390, 844), phone: true);
    expect(find.text('错误码'), findsNothing);
    expect(find.text('deepseek-flash'), findsOneWidget);
    await save(tester, '04-phone-summary');
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.tap(find.byKey(const ValueKey('map-generation-copy-error-button')));
    await tester.pumpAndSettle();
    expect(copied, contains('返回行数 / 通过校验行数: 27 / 0'));
    expect(copied, contains('模型思考字符数: 21832'));
    expect(copied, isNot(contains('private response body')));
    expect(find.text('已拷贝'), findsOneWidget);
    expect(find.text('错误码'), findsNothing);
    await save(tester, '05-phone-copied');
  });

  for (final dark in [true, false]) {
    failureTest('summary and expanded diagnostic layout in ${dark ? 'dark' : 'light'} mode', (tester) async {
      await openFailure(tester, dark: dark);
      expect(find.text('生成未完成'), findsOneWidget);
      expect(find.text('第 2 页'), findsOneWidget);
      expect(find.text('模型返回内容未通过脑图格式校验'), findsOneWidget);
      expect(find.text('错误码'), findsNothing);
      await save(tester, '02-${dark ? 'dark' : 'light'}-summary');
      await tester.ensureVisible(find.byKey(const ValueKey('map-generation-diagnostics-0')));
      await tester.tap(find.byKey(const ValueKey('map-generation-diagnostics-0')));
      await tester.pumpAndSettle();
      expect(find.text('protocol / noValidMapContent'), findsOneWidget);
      expect(find.text('27 / 0'), findsOneWidget);
      expect(find.text('private response body'), findsNothing);
      expect(tester.takeException(), isNull);
      await save(tester, '03-${dark ? 'dark' : 'light'}-diagnostics');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('map-generation-failure-dialog')), findsNothing);
    });
  }

  for (final spec in [
    (name: 'phone', size: const Size(390, 844), phone: true, scale: 1.0, language: 'zh'),
    (name: 'narrow-window', size: const Size(320, 640), phone: false, scale: 1.0, language: 'zh'),
    (name: 'large-text', size: const Size(390, 844), phone: true, scale: 2.0, language: 'en'),
    (name: 'short-window', size: const Size(844, 390), phone: false, scale: 1.0, language: 'en'),
  ]) {
    failureTest('${spec.name} keeps long diagnostics scrollable and actions reachable', (tester) async {
      await openFailure(
        tester,
        size: spec.size,
        phone: spec.phone,
        scale: spec.scale,
        language: spec.language,
        data: preview(failures: 12, long: true),
      );
      await tester.ensureVisible(find.byKey(const ValueKey('map-generation-diagnostics-0')));
      await tester.tap(find.byKey(const ValueKey('map-generation-diagnostics-0')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final close = find.byKey(const ValueKey('map-generation-close-error-button'));
      expect(close.hitTestable(), findsOneWidget);
      await save(tester, '04-${spec.name}');
      await tester.ensureVisible(find.text('第 13 页'));
      await tester.pumpAndSettle();
      expect(find.text('第 13 页').hitTestable(), findsOneWidget);
      expect(close.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('map-generation-failure-dialog')), findsNothing);
    });
  }
}
