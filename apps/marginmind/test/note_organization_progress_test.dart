import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/study_notes/note_organization_progress.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

final _out = Platform.environment['MM_NOTE_PROGRESS_SCREENSHOTS'];
final _materials = NoteMaterials([
  NoteMaterial(
    ref: 'h1',
    sourceId: 'a1',
    text: '把复习安排在遗忘临界点，用成功回忆拉长保持时间。',
    groupKey: 'chapter',
    groupTitle: 'Sample chapter · p. 12',
    createdAt: DateTime.utc(2026, 11, 1),
  ),
], collectedAt: DateTime.utc(2026, 11, 1));
final _outline = [
  for (var i = 0; i < 17; i++) NoteOutlineSection(title: '第 ${i + 1} 节', refs: ['h1']),
];
final _draft = NoteDraftSection(
  title: '学习与记忆：间隔重复',
  blocks: [
    NoteDraftBlock.fromJson({'type': 'summary', 'text': '熟悉感只表示认得，不等于需要时能提取；间隔重复针对这一差距设计复习时机。'}),
    NoteDraftBlock.fromJson({'type': 'quote', 'ref': 'h1'}),
    NoteDraftBlock.fromJson({
      'type': 'points',
      'items': ['在记忆即将衰退前安排回忆练习。', '每次成功提取后，下次复习间隔可延长。'],
    }),
  ],
);

Future<void> _open(
  WidgetTester tester, {
  Size size = const Size(1280, 820),
  bool dark = true,
  double scale = 1,
  String language = 'zh',
  String? error,
  bool local = false,
  NoteOrganizationPhase phase = NoteOrganizationPhase.write,
  int completed = 3,
  ValueNotifier<int>? progress,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final notifier = progress ?? ValueNotifier(completed);
  if (progress == null) addTearDown(notifier.dispose);
  await tester.pumpWidget(
    MMInput(
      touchPlatform: size.width < 600,
      phone: size.width < 600,
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
                label: 'Open',
                onPressed: () {
                  showMMSheet<void>(
                    context: context,
                    width: MMSizes.noteProgressSheetWidth,
                    builder: (context) => MMSheet(
                      title: local
                          ? AppLocalizations.of(context).noteProgressLayoutTitle
                          : AppLocalizations.of(context).noteProgressTitle,
                      titleStyle: context.mmText.title2,
                      titleLeading: Icon(MMIcons.ai, color: context.mmColors.research, size: 24),
                      actions: [
                        MMButton(
                          label: AppLocalizations.of(context).noteStop,
                          icon: MMIcons.stop,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                      child: ValueListenableBuilder<int>(
                        valueListenable: notifier,
                        builder: (context, completed, _) => NoteOrganizationProgress(
                          phase: phase,
                          materials: _materials,
                          sections: phase == NoteOrganizationPhase.outline ? [] : _outline,
                          draft: List.generate(
                            completed,
                            (index) => index == 0
                                ? _draft
                                : NoteDraftSection(
                                    title: index == 1 ? '主动回忆：先测再读' : '复习计划：逐步拉长间隔',
                                    blocks: [
                                      NoteDraftBlock.fromJson({
                                        'type': 'summary',
                                        'text': index == 1 ? '先尝试回忆，再检查答案，能更准确地发现掌握程度。' : '根据回忆结果安排下次复习，逐步延长间隔。',
                                      }),
                                    ],
                                  ),
                          ),
                          local: local,
                          busy: error == null,
                          error: error,
                          quoteColors: {'h1': MMAnnotationColor.yellow.color},
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _save(WidgetTester tester, String name) async {
  if (_out == null) return;
  final picture = (await tester.runAsync(() {
    final view = tester.binding.renderViews.first;
    return (view.debugLayer! as OffsetLayer).toImage(Offset.zero & view.size, pixelRatio: 1);
  }))!;
  final png = (await tester.runAsync(() => picture.toByteData(format: ui.ImageByteFormat.png)))!;
  await tester.runAsync(() async {
    await Directory(_out!).create(recursive: true);
    await File('$_out/$name.png').writeAsBytes(png.buffer.asUint8List());
  });
  picture.dispose();
}

void main() {
  setUpAll(() async {
    if (_out == null) return;
    final latin = ByteData.sublistView(await File('/Library/Fonts/SF-Pro-Text-Regular.otf').readAsBytes());
    for (final family in ['.AppleSystemUIFont', 'CupertinoSystemText', 'CupertinoSystemDisplay', 'Roboto']) {
      await (FontLoader(family)..addFont(Future.value(latin))).load();
    }
    final sans = ByteData.sublistView(await File('/System/Library/Fonts/STHeiti Light.ttc').readAsBytes());
    await (FontLoader('PingFang SC')..addFont(Future.value(sans))).load();
    final serif = ByteData.sublistView(await File('/System/Library/Fonts/Supplemental/Songti.ttc').readAsBytes());
    await (FontLoader('Songti SC')..addFont(Future.value(serif))).load();
    final pub = Platform.environment['PUB_CACHE'] ?? '${Platform.environment['HOME']}/.pub-cache';
    final icons = Directory('$pub/hosted/pub.dev')
        .listSync()
        .whereType<Directory>()
        .lastWhere((d) => d.path.contains('cupertino_icons-'));
    final data = ByteData.sublistView(await File('${icons.path}/assets/CupertinoIcons.ttf').readAsBytes());
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(Future.value(data))).load();
  });

  for (final dark in [true, false]) {
    testWidgets('desktop steps and section progress (${dark ? 'dark' : 'light'})', (tester) async {
      await _open(tester, dark: dark);
      expect(find.byKey(const ValueKey('note-progress-steps')), findsOneWidget);
      expect(find.byKey(const ValueKey('note-progress-compact')), findsNothing);
      expect(find.text('已完成 3 / 17 节'), findsOneWidget);
      expect(find.text('正在撰写第 4 节'), findsOneWidget);
      expect(
        tester.widget<LinearProgressIndicator>(find.byKey(const ValueKey('note-section-progress'))).value,
        closeTo(3 / 17, .0001),
      );
      expect(find.text(_materials.highlights.first.text), findsOneWidget);
      expect(find.text('Sample chapter · p. 12'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _save(tester, dark ? 'desktop-dark' : 'desktop-light');
    });
  }

  testWidgets('outline has no invented section count or content', (tester) async {
    await _open(tester, phase: NoteOrganizationPhase.outline, completed: 0);
    expect(find.byKey(const ValueKey('note-section-progress')), findsNothing);
    expect(find.text('每完成一节，正文会显示在这里'), findsOneWidget);
    expect(find.text('AI'), findsNothing);
    await _save(tester, 'outline-dark');
  });

  testWidgets('failure keeps preview and stops the active spinner', (tester) async {
    await _open(tester, error: '连接中断，请稍后重试。');
    expect(find.text('连接中断，请稍后重试。'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(_materials.highlights.first.text), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _save(tester, 'failure-dark');
  });

  for (final scenario in [
    (const Size(390, 844), 1.0, 'zh', 'phone-dark'),
    (const Size(568, 320), 1.0, 'en', 'short-window'),
    (const Size(820, 700), 2.0, 'en', 'large-text'),
  ]) {
    testWidgets('progress and stop remain visible: ${scenario.$4}', (tester) async {
      await _open(tester, size: scenario.$1, scale: scenario.$2, language: scenario.$3);
      expect(find.byKey(const ValueKey('note-progress-compact')), findsOneWidget);
      final button = find.widgetWithText(MMButton, scenario.$3 == 'zh' ? '停止' : 'Stop');
      expect(button.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _save(tester, scenario.$4);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byType(NoteOrganizationProgress), findsNothing);
    });
  }

  testWidgets('new sections follow the bottom but preserve manual reading position', (tester) async {
    final progress = ValueNotifier(2);
    addTearDown(progress.dispose);
    await _open(tester, progress: progress);
    final scroll = tester
        .widget<SingleChildScrollView>(find.byKey(const ValueKey('note-progress-preview')))
        .controller!;
    scroll.jumpTo(scroll.position.maxScrollExtent);
    progress.value = 3;
    await tester.pump();
    await tester.pump();
    expect(scroll.offset, scroll.position.maxScrollExtent);
    scroll.jumpTo(0);
    progress.value = 4;
    await tester.pump();
    await tester.pump();
    expect(scroll.offset, 0);
    expect(find.text('正在撰写第 5 节').hitTestable(), findsOneWidget);
  });

  testWidgets('failure stays visible independently of the scrolled preview', (tester) async {
    await _open(tester, error: '连接中断，请稍后重试。');
    final scroll = tester
        .widget<SingleChildScrollView>(find.byKey(const ValueKey('note-progress-preview')))
        .controller!;
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    expect(find.text('连接中断，请稍后重试。').hitTestable(), findsOneWidget);
  });

  testWidgets('short-window failure text scrolls without hiding Stop', (tester) async {
    await _open(tester, size: const Size(568, 320), error: '连接中断，请稍后重试。' * 20);
    expect(find.widgetWithText(MMButton, '停止').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('local formatting omits AI stages and AI markers', (tester) async {
    await _open(tester, local: true);
    expect(find.text('归纳主题'), findsNothing);
    expect(find.text('核对引用'), findsNothing);
    expect(find.text('AI'), findsNothing);
    expect(find.text('正在排版第 4 节'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
