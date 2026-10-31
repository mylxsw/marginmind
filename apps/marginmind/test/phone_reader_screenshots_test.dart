/// MM_SCREENSHOTS=1 MM_FONT=/path/to/CJK.ttf flutter test test/phone_reader_screenshots_test.dart --update-goldens
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/phone_reader_controls_controller.dart';
import 'package:marginmind/features/workspace/workspace_chrome_controller.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_book/mm_book.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';
import 'reader_crop_test.dart' show drain;
import 'reflow_fixtures.dart';

void main() {
  final evidence = Platform.environment['MM_SCREENSHOTS'] != null;
  setUpAll(() async {
    if (!evidence) return;
    final data = ByteData.sublistView(File(Platform.environment['MM_FONT']!).readAsBytesSync());
    for (final family in [
      '.AppleSystemUIFont',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      'Roboto',
      'PingFang SC',
      'Songti SC',
      'Noto Sans',
    ]) {
      await (FontLoader(family)..addFont(Future.value(data))).load();
    }
    final cache = '${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev';
    for (final (package, family, asset) in [
      ('cupertino_icons-', 'packages/cupertino_icons/CupertinoIcons', 'assets/CupertinoIcons.ttf'),
      ('lucide_icons_flutter-', 'packages/lucide_icons_flutter/Lucide', 'assets/lucide.ttf'),
    ]) {
      final directory = Directory(cache)
          .listSync()
          .whereType<Directory>()
          .lastWhere((d) => d.path.split('/').last.startsWith(package));
      final file = File('${directory.path}/$asset');
      if (file.existsSync()) {
        await (FontLoader(family)..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())))).load();
      }
    }
  });
  for (final dark in [false, true]) {
    testWidgets('393x852 phone reader scenes ${dark ? 'dark' : 'light'}', (tester) async {
      debugDisableShadows = false;
      try {
        final repo = InMemoryStudySetContentRepository({'demo-1': demoContent()});
        final chapter = const EpubParser().parseHtml('memory', '''
<h1>第二章　遗忘曲线与间隔重复</h1>
<h2>一、记忆是怎样流失的</h2>
<p>人在学习新知识之后，记忆并不是匀速流失的。最初的几个小时里遗忘最快，之后速度逐渐放缓，剩下的部分会保持很长时间。</p>
<p>遗忘并不完全是坏事。大脑会主动筛选信息，把暂时没用的内容，让给更重要的知识和经验。</p>
<p>学习不是把信息放进去，而是在需要时能把它找回来。每次主动回忆，都让知识之间的联系更加牢固。</p>
<h2>二、间隔重复</h2>
<p>间隔重复利用的正是记忆的变化规律。在快要忘记时回顾，比连续重复阅读更有帮助。</p>
${List.filled(8, '<p>把回忆安排在不同的时间，给自己留一点思考的空间。阅读、提问、建立联系，再回到原文。</p>').join()}
''');
        final doc = await storeBook(repo, book: Book('学习的底层逻辑', [chapter], {}, []));
        final container = await pumpApp(
          tester,
          size: const Size(393, 852),
          content: repo,
          prefs: {
            'settings.appearance': dark ? 'dark' : 'light',
            'settings.readerStyle': dark ? 'dark' : 'white',
            'settings.language': 'zh',
          },
          overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(true)],
        );
        tester.view.padding = const FakeViewPadding(top: 54, bottom: 34);
        container.read(navigationProvider.notifier).openStudySet('demo-1');
        await drain(tester);
        final workspace = container.read(workspaceProvider('demo-1').notifier);
        workspace.openDocument(doc.id);
        await drain(tester);
        final element = tester.element(find.byType(ReaderPane));
        final slots = PhoneReaderControlsScope.maybeOf(element)!;
        final chrome = WorkspaceChromeScope.maybeOf(element)!;
        Future<void> capture(String scene) async {
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final directory = evidence
              ? '../../../docs/evidence/gul-631'
              : 'goldens/${Platform.isLinux ? 'linux' : 'other'}/phone-reader';
          await expectLater(
            find.byType(MarginMindApp),
            matchesGoldenFile('$directory/$scene-${dark ? 'dark' : 'light'}.png'),
          );
        }

        await capture('02-reading');
        expect(tester.getRect(find.byKey(const ValueKey('phone-reader-page'))).bottom, 852 - 34);
        slots.openTools();
        await workspace.setTool(AnnotationTool.highlight);
        await capture('03-tools');
        slots.collapseTools();
        await capture('03-orb');
        slots.openScrub();
        await capture('04-scrub');
        slots.closeScrub();
        chrome.onUserScroll(30, atStart: false, geometryKey: 'screenshot');
        await capture('05-immersive');
        chrome.reveal();
        workspace.setLayout(MMSplitMode.secondary);
        await drain(tester);
        await capture('09-map');
        await tester.pumpWidget(const SizedBox());
        await drain(tester);
      } finally {
        debugDisableShadows = true;
      }
    }, skip: !evidence);
  }
}
