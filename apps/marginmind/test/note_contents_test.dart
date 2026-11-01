import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/study_notes/note_contents.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import 'study_notes_ui_test.dart' show noteFixture, openNote;

final _output = Platform.environment['MM_NOTE_CONTENTS_SCREENSHOTS'];
const _titles = [
  '学习与记忆：间隔重复',
  '数字化企业：四特征总框架',
  '连接：泛在互联与数据共享',
  '在线：业务在线与组织在线',
  '数字化组织定位与转型路径',
  'IPD变革与产品开发管理',
  '流程简化：日常工作的改进方法',
  '服务流程优化与客户体验',
  '流程管理长效机制',
  '组织在线：从协同到持续学习',
  '华为变革支撑体系与管理实践',
  '敏捷管理：Scrum团队的工作方式',
  '跑步心态：孤独与坚持',
  '跑步营养：蛋白质与碳水化合物',
  '跑前饮食与补水策略',
  '跑步赛事：马拉松训练计划',
  '待分类与空笔记',
];

StudySetContent _content() {
  final fixture = noteFixture();
  return fixture.copyWith(
    studyNotes: [
      fixture.studyNotes.single.copyWith(
        title: 'Sample: Forgetting & Spaced Repetition',
        sections: [
          for (final (i, title) in _titles.indexed)
            NoteSection(
              id: 's$i',
              title: title,
              blocks: [
                if (i == 0) fixture.studyNotes.single.sections.single.blocks.first,
                for (var j = 0; j < 4; j++)
                  TextBlock(
                    id: 'text-$i-$j',
                    text: j.isEven
                        ? '熟悉感只表示认得，不等于需要时能提取；间隔重复针对这一差距设计复习时机。'
                        : '复习时机：在记忆即将衰退前安排回忆练习。\n反馈：每次成功提取后，下次复习间隔可延长。',
                    origin: NoteOrigin.ai,
                  ),
              ],
            ),
        ],
      ),
    ],
  );
}

Finder _item(int index) => find.byKey(ValueKey('note-contents-s$index'));
SingleChildScrollView _body(WidgetTester tester) =>
    tester.widget<SingleChildScrollView>(find.byKey(const ValueKey('note-scroll')));

Future<void> _save(WidgetTester tester, String name) async {
  if (_output == null) return;
  final image = (await tester.runAsync(() {
    final view = tester.binding.renderViews.first;
    return (view.debugLayer! as OffsetLayer).toImage(Offset.zero & view.size, pixelRatio: 1.5);
  }))!;
  final png = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png)))!;
  await tester.runAsync(() async {
    await Directory(_output!).create(recursive: true);
    await File('$_output/$name.png').writeAsBytes(png.buffer.asUint8List());
  });
  image.dispose();
}

void main() {
  setUpAll(() async {
    if (_output == null) return;
    for (final family in ['.AppleSystemUIFont', 'CupertinoSystemText', 'CupertinoSystemDisplay', 'Roboto']) {
      final data = ByteData.sublistView(await File('/System/Library/Fonts/SFNS.ttf').readAsBytes());
      await (FontLoader(family)..addFont(Future.value(data))).load();
    }
    final pingFang = Directory('/System/Library/AssetsV2/com_apple_MobileAsset_Font8')
        .listSync(recursive: true)
        .whereType<File>()
        .firstWhere((f) => f.path.endsWith('/PingFang.ttc'));
    await (FontLoader('PingFang SC')..addFont(Future.value(ByteData.sublistView(await pingFang.readAsBytes())))).load();
    await (FontLoader('Songti SC')..addFont(
          Future.value(ByteData.sublistView(await File('/System/Library/Fonts/Supplemental/Songti.ttc').readAsBytes())),
        ))
        .load();
    for (final asset in [
      ('packages/cupertino_icons/CupertinoIcons', 'packages/cupertino_icons/assets/CupertinoIcons.ttf'),
      ('packages/lucide_icons_flutter/Lucide', 'packages/lucide_icons_flutter/assets/lucide.ttf'),
    ]) {
      await (FontLoader(asset.$1)..addFont(rootBundle.load(asset.$2))).load();
    }
  });

  for (final appearance in ['dark', 'light']) {
    testWidgets('17 chapters stay readable beside the document in $appearance mode', (tester) async {
      await openNote(tester, content: _content(), language: 'zh', appearance: appearance);
      final rail = find.byType(NoteContents);
      expect(rail, findsOneWidget);
      expect(tester.widget<MMInteractive>(_item(0)).selected, isTrue);
      final body = tester.getRect(find.byKey(const ValueKey('note-scroll')));
      expect(body.right, lessThan(tester.getRect(rail).left));
      final title = tester.widget<Text>(find.descendant(of: _item(1), matching: find.text(_titles[1])));
      expect(title.maxLines, 2);
      await _save(tester, 'desktop-$appearance');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('chapter jumps, manual reading and return to start keep the rail synchronized', (tester) async {
    await openNote(tester, content: _content(), language: 'zh', size: const Size(1400, 650));
    await tester.ensureVisible(_item(10));
    await tester.pumpAndSettle();
    await tester.tap(_item(10));
    await tester.pumpAndSettle();
    expect(tester.widget<MMInteractive>(_item(10)).selected, isTrue);
    expect(_body(tester).controller!.offset, greaterThan(1000));
    await _save(tester, 'chapter-selected');

    _body(tester).controller!.jumpTo(_body(tester).controller!.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.widget<MMInteractive>(_item(16)).selected, isTrue);
    expect(_item(16).hitTestable(), findsOneWidget);
    _body(tester).controller!.jumpTo(0);
    await tester.pumpAndSettle();
    expect(tester.widget<MMInteractive>(_item(0)).selected, isTrue);
    expect(_item(0).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short windows scroll the directory without moving the document', (tester) async {
    await openNote(tester, content: _content(), language: 'zh', size: const Size(1280, 520));
    final bodyOffset = _body(tester).controller!.offset;
    await tester.drag(find.byKey(const ValueKey('note-contents-scroll')), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(_body(tester).controller!.offset, bodyOffset);
    expect(tester.takeException(), isNull);
    await _save(tester, 'short-window');
  });

  testWidgets('narrow windows keep the document full width and offer chapter navigation in the menu', (tester) async {
    await openNote(tester, content: _content(), size: const Size(900, 650));
    expect(find.byType(NoteContents), findsNothing);
    await tester.tap(find.byKey(const ValueKey('note-more')));
    await tester.pumpAndSettle();
    expect(find.text('Table of Contents'), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text wraps and keyboard activation can select a chapter', (tester) async {
    final active = ValueNotifier('s0');
    addTearDown(active.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: MMTheme.dark(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: SizedBox(
                width: MMNoteLayout.tocWidth,
                height: 260,
                child: ValueListenableBuilder<String>(
                  valueListenable: active,
                  builder: (context, id, _) => NoteContents(
                    title: '目录',
                    sections: _content().studyNotes.single.sections,
                    activeId: id,
                    onSelected: (id) => active.value = id,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final gesture = find.descendant(of: _item(1), matching: find.byType(GestureDetector)).first;
    Focus.of(tester.element(gesture)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(active.value, 's1');
    expect(tester.widget<MMInteractive>(_item(1)).selected, isTrue);
    expect(_item(1).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
