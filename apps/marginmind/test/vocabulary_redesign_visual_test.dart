import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/vocabulary/vocabulary_screen.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';

import 'helpers.dart';
import 'vocabulary_screenshots.dart';

// In-memory sample only; never opens or edits the installed app's library.
VocabularyEntry _sample() => VocabularyEntry(
  id: 'link',
  term: 'LINK',
  language: 'en',
  kind: VocabularyKind.word,
  createdAt: testNow.subtract(const Duration(days: 2)),
  updatedAt: testNow,
  forms: ['link', 'chainlink', 'link 代币', 'link币'],
  ukPhonetic: '/lɪŋk/',
  usPhonetic: '/lɪŋk/',
  senses: const [
    VocabularySense(partOfSpeech: '专有名词（代币代码）', meaning: 'Chainlink（链环）网络的原生代币，用于支付预言机服务、质押及在交易所和 DeFi 场景中流通。'),
    VocabularySense(partOfSpeech: '名词', meaning: '链环；链接；联系。'),
    VocabularySense(partOfSpeech: '动词', meaning: '连接；联系；把……连接起来。'),
  ],
  gloss: '链环代币',
  contexts: [
    VocabularyContext(
      id: 'example',
      studySetId: 'demo-1',
      documentId: 'c1',
      studySetTitle: 'Sample: Forgetting & Spaced Repetition',
      documentTitle: '示例文章',
      sentence: '过 DEX 抛售山寨币（如 PEPE、UNI、LINK 等），部分资金还被用于 Aave 借贷。',
      sentenceTranslation: '通过 DEX 抛售山寨币（如 PEPE、UNI、LINK 等），部分资金还被用于 Aave 借贷。',
      hit: 'LINK',
      addedAt: testNow,
      page: 1,
      rects: [const PageRect(10, 100, 200, 88)],
    ),
  ],
);

void main() {
  for (final dark in [true, false]) {
    testWidgets(
      'vocabulary redesign visual ${dark ? 'dark' : 'light'}',
      (tester) async {
        await tester.runAsync(loadVocabularyScreenshotFonts);
        final repo = InMemoryVocabularyRepository([_sample()]);
        addTearDown(repo.dispose);
        final c = await pumpApp(
          tester,
          size: const Size(1575, 1000),
          vocabulary: repo,
          prefs: {'settings.language': 'zh', 'settings.appearance': dark ? 'dark' : 'light'},
        );
        c.read(navigationProvider.notifier).openStudySet('demo-1');
        await tester.pumpAndSettle();
        c.read(workspaceProvider('demo-1').notifier).activateTab(WorkspaceTab.vocabulary);
        await tester.pumpAndSettle();
        Future<void> capture(String name) async {
          final view = tester.binding.renderViews.first;
          final image = (await tester.runAsync(
            () => (view.debugLayer! as OffsetLayer).toImage(Offset.zero & view.size, pixelRatio: 2),
          ))!;
          final png = await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png));
          image.dispose();
          await tester.runAsync(
            () => File('${Platform.environment['MM_SCREENSHOTS']}/$name.png').writeAsBytes(png!.buffer.asUint8List()),
          );
        }

        final suffix = dark ? 'dark' : 'light';
        await capture('desktop-$suffix');
        await tester.tap(find.byKey(const ValueKey('vocabulary-more')));
        await tester.pumpAndSettle();
        await capture('desktop-more-$suffix');
        await tester.tapAt(const Offset(550, 850));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('vocabulary-scope')));
        await tester.pumpAndSettle();
        await capture('desktop-scope-$suffix');
        await tester.tapAt(const Offset(550, 850));
        await tester.pumpAndSettle();
        tester.view.physicalSize = const Size(600, 900);
        await tester.pumpAndSettle();
        await capture('narrow-$suffix');
        expect(find.byType(VocabularyDetail), findsNothing);
        await tester.tap(find.byKey(const ValueKey('vocabulary-row-link')));
        await tester.pumpAndSettle();
        expect(find.byType(VocabularyDetail), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('vocabulary-more')),
          200,
          scrollable: find.descendant(of: find.byType(VocabularyDetail), matching: find.byType(Scrollable)).first,
        );
        await tester.pumpAndSettle();
        await capture('narrow-detail-$suffix');
        expect(tester.takeException(), isNull);
      },
      skip: !vocabularyScreenshotsEnabled,
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }
}
