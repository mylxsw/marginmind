import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/review/review_controller.dart';
import 'package:marginmind/features/workspace/phone_reader_controls_controller.dart';
import 'package:marginmind/features/workspace/widgets/phone_workspace_sidebar.dart';
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';
import 'package:marginmind/features/workspace/workspace_chrome_controller.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/settings/app_settings.dart';
import 'package:mm_book/mm_book.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:path_provider/path_provider.dart';

import '../test/helpers.dart';
import '../test/reader_crop_test.dart' show drain;
import '../test/reflow_fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('GUL-629 10 mobile scenes acceptance in light and dark', (tester) async {
    debugDisableShadows = false;
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    final repo = InMemoryStudySetContentRepository({'demo-1': demoContent()});
    final chapter = const EpubParser().parseHtml('memory', '''
<h1>第二章　遗忘曲线与间隔重复</h1>
<h2>一、记忆是怎样流失的</h2>
<p>人在学习新知识之后，记忆并不是匀速流失的。最初的几个小时里遗忘最快，之后速度逐渐放缓，剩下的部分会保持很长时间。</p>
<p>遗忘并不完全是坏事。大脑会主动筛选信息，把暂时没用的内容，让给更重要的知识和经验。</p>
<p>学习不是把信息放进去，而是在需要时能把它找回来。每次主动回忆，都让知识之间的联系更加牢固。</p>
<h2>二、间隔重复</h2>
<p>间隔重复利用的正是记忆的变化规律。在快要忘记时回顾，比连续重复阅读更有帮助。</p>
<p>把回忆安排在不同的时间，给自己留一点思考的空间。阅读、提问、建立联系，再回到原文。</p>
''');
    final doc = await storeBook(repo, id: 'c1', book: Book('学习的底层逻辑', [chapter], {}, []));

    final base = await testOverrides(
      prefs: {'settings.appearance': 'light', 'settings.readerStyle': 'white', 'settings.language': 'zh'},
      sets: DemoLibrary.studySets(testNow),
      content: repo,
      clock: () => testNow,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [...base, touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(true)],
        child: const MarginMindApp(),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(tester.element(find.byType(MarginMindApp)));
    final settings = container.read(settingsProvider.notifier);
    final navigation = container.read(navigationProvider.notifier);
    final workspace = container.read(workspaceProvider('demo-1').notifier);

    final marker = File('${(await getTemporaryDirectory()).path}/phone-gul629-shot');

    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await marker.writeAsString(name);
        // ignore: avoid_print
        print('PHONE_SHOT:$name:${marker.path}');
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (true) {
          if (marker.existsSync() && await marker.readAsString() == 'captured:$name') break;
          if (DateTime.now().isAfter(deadline)) throw TimeoutException('Host did not capture $name');
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      });
    }

    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';
      await settings.setAppearance(dark ? AppearancePreference.dark : AppearancePreference.light);
      await settings.setReaderStyle(dark ? MMReaderStyle.dark : MMReaderStyle.white);
      await settings.setLanguage(LanguagePreference.zh);
      await tester.pumpAndSettle();

      // Scene 01: 资料库
      navigation.showLibrary();
      await tester.pumpAndSettle();
      await capture('01-library-$mode');

      // Open Study Set & Document to Reader View
      navigation.openStudySet('demo-1');
      await drain(tester);
      workspace.openDocument(doc.id);
      await drain(tester);
      await tester.pumpAndSettle();

      final element = tester.element(find.byType(ReaderPane));
      final slots = PhoneReaderControlsScope.maybeOf(element)!;
      final chrome = WorkspaceChromeScope.maybeOf(element)!;

      // Scene 02: 阅读默认态
      chrome.reveal();
      slots.collapseTools();
      slots.closeScrub();
      await tester.pumpAndSettle();
      await capture('02-reading-$mode');

      // Scene 03: 工具栏展开态
      slots.openTools();
      await workspace.setTool(AnnotationTool.highlight);
      await tester.pumpAndSettle();
      await capture('03-tools-$mode');

      // Scene 04: 跳页滑块
      slots.collapseTools();
      slots.openScrub();
      await tester.pumpAndSettle();
      await capture('04-scrub-$mode');

      // Scene 05: 沉浸态
      slots.closeScrub();
      chrome.onUserScroll(30, atStart: false, geometryKey: 'screenshot');
      await tester.pumpAndSettle();
      await capture('05-immersive-$mode');

      // Scene 06: “更多”底部面板
      chrome.reveal();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('phone-workspace-more')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('phone-sheet-more')), findsOneWidget);
      await capture('06-more-$mode');

      // Scene 07: 阅读外观二级面板
      await tester.tap(find.byKey(const ValueKey('phone-tile-appearance')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('phone-sheet-appearance')), findsOneWidget);
      await capture('07-appearance-$mode');

      // Close appearance sheet
      await tester.tap(find.byKey(const ValueKey('phone-appearance-close')));
      await tester.pumpAndSettle();

      // Scene 08: 学习集抽屉
      await tester.dragFrom(const Offset(2, 400), const Offset(190, 0));
      await tester.pumpAndSettle();
      expect(find.byType(PhoneWorkspaceSidebar), findsOneWidget);
      await capture('08-drawer-$mode');

      // Close drawer (tap 完成)
      await tester.tap(find.text('完成').hitTestable());
      await tester.pumpAndSettle();

      // Scene 09: 脑图页
      workspace.setLayout(MMSplitMode.secondary);
      await drain(tester);
      await tester.pumpAndSettle();
      await capture('09-map-$mode');

      // Restore layout to primary (reader)
      workspace.setLayout(MMSplitMode.primary);
      await drain(tester);
      await tester.pumpAndSettle();

      // Scene 10: 复习页
      navigation.startReview('demo-1');
      await tester.pumpAndSettle();
      final review = container.read(reviewSessionProvider('demo-1').notifier);
      review.reveal();
      await tester.pumpAndSettle();
      await capture('10-review-$mode');

      // Return to library before next mode
      navigation.showLibrary();
      await tester.pumpAndSettle();
    }
  });
}
