import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/vocabulary/hint_card.dart';
import 'package:marginmind/features/vocabulary/hint_painter.dart';
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';

import 'assistant_quick_actions_test.dart' show screenshot;
import 'helpers.dart';
import 'reflow_fixtures.dart';
import 'vocabulary_screen_test.dart' show word;

void main() {
  setUpAll(() async {
    if (Platform.environment['MM_SCREENSHOTS'] == null) return;
    final bytes = ByteData.sublistView(
      File(Platform.environment['MM_FONT'] ?? '/System/Library/Fonts/Supplemental/Arial Unicode.ttf').readAsBytesSync(),
    );
    for (final family in [
      '.AppleSystemUIFont',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      'Roboto',
      'PingFang SC',
    ]) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
    await (FontLoader('Songti SC')..addFont(
          Future.value(ByteData.sublistView(File('/System/Library/Fonts/Supplemental/Songti.ttc').readAsBytesSync())),
        ))
        .load();
    final cache = Platform.environment['PUB_CACHE'] ?? '${Platform.environment['HOME']}/.pub-cache';
    final icons = Directory('$cache/hosted/pub.dev')
        .listSync()
        .whereType<Directory>()
        .lastWhere((d) => d.path.contains('cupertino_icons-'));
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
          Future.value(ByteData.sublistView(File('${icons.path}/assets/CupertinoIcons.ttf').readAsBytesSync())),
        ))
        .load();
    await (FontLoader(
      'packages/lucide_icons_flutter/Lucide',
    )..addFont(rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'))).load();
  });

  for (final dark in [false, true]) {
    testWidgets('reader hint screenshots ${dark ? 'dark' : 'light'}', (tester) async {
      final content = InMemoryStudySetContentRepository();
      final doc = await storeBook(content);
      final vocabulary = InMemoryVocabularyRepository([
        word('source').copyWith(
          gloss: '来源',
          ukPhonetic: '/sɔːs/',
          usPhonetic: '/sɔːrs/',
          senses: [const VocabularySense(partOfSpeech: 'n.', meaning: '来源；出处')],
        ),
        word('anchors').copyWith(gloss: '锚点'),
      ]);
      addTearDown(vocabulary.dispose);
      final c = await pumpApp(
        tester,
        content: content,
        vocabulary: vocabulary,
        prefs: {
          'settings.appearance': dark ? 'dark' : 'light',
          'settings.language': 'zh',
          'vocabulary.hintMode': 'gloss',
        },
      );
      c.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      c.read(workspaceProvider('demo-1').notifier).openDocument(doc.id);
      await tester.pumpAndSettle();
      await screenshot(tester, 'reader-hints-${dark ? 'dark' : 'light'}', target: find.byType(ReaderPane));
      final surface = find.byKey(const ValueKey('reflow-surface'));
      final hints =
          tester.widget<CustomPaint>(find.byKey(const ValueKey('vocabulary-hints-surface')).first).painter!
              as VocabularyHintPainter;
      await tester.tapAt(tester.getTopLeft(surface) + hints.hits.first.rects.first.center);
      await tester.pumpAndSettle();
      await screenshot(tester, 'hit-card-${dark ? 'dark' : 'light'}', target: find.byType(VocabularyHitCard));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }, skip: Platform.environment['MM_SCREENSHOTS'] == null);
  }
}
