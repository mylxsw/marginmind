import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_book/mm_book.dart';
import 'package:mm_core/testing.dart';

import 'helpers.dart';
import 'reader_crop_test.dart' show drain;
import 'reflow_fixtures.dart';

void main() {
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('Capture GUL-633 visual evidence: $mode', (tester) async {
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
<p>把回忆安排在不同的时间，给自己留一点思考的空间。阅读、提问、建立联系，再回到原文。</p>
''');
        final doc = await storeBook(repo, book: Book('学习的底层逻辑', [chapter], {}, []));

        // 1. Library Screen Header Scene
        final container = await pumpApp(
          tester,
          size: const Size(393, 852),
          content: repo,
          prefs: {
            'settings.appearance': mode,
            'settings.readerStyle': dark ? 'dark' : 'white',
            'settings.language': 'zh',
          },
          overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(true)],
        );
        tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(MarginMindApp),
          matchesGoldenFile('../../../docs/evidence/gul-633/01-library-$mode.png'),
        );

        // 2. Open Study Set & Document to Reader View
        container.read(navigationProvider.notifier).openStudySet('demo-1');
        await drain(tester);
        final workspace = container.read(workspaceProvider('demo-1').notifier);
        workspace.openDocument(doc.id);
        await drain(tester);
        await tester.pumpAndSettle();

        // 3. Open "More" bottom sheet (Scene 06)
        await tester.tap(find.byKey(const ValueKey('phone-workspace-more')));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('phone-sheet-more')), findsOneWidget);
        await expectLater(
          find.byType(MarginMindApp),
          matchesGoldenFile('../../../docs/evidence/gul-633/06-more-$mode.png'),
        );

        // 4. Open "Reader Appearance" secondary panel (Scene 07)
        await tester.tap(find.byKey(const ValueKey('phone-tile-appearance')));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('phone-sheet-appearance')), findsOneWidget);
        await expectLater(
          find.byType(MarginMindApp),
          matchesGoldenFile('../../../docs/evidence/gul-633/07-appearance-$mode.png'),
        );

        await tester.pumpWidget(const SizedBox());
        await drain(tester);
      } finally {
        debugDisableShadows = true;
      }
    }, skip: Platform.environment['MM_SCREENSHOTS'] == null);
  }
}
