import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/full_translation.dart';
import 'package:marginmind/features/workspace/widgets/full_translation_panel.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

import 'full_translation_test.dart' show MockFullTranslationController, testHost;
import 'helpers.dart';
import 'reader_compare_test.dart' show compareFixture;
import 'translation_lifecycle_test.dart' show job, paragraphs;

void main() {
  testWidgets('page grid includes empty trailing PDF pages and dims pages outside the task', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final content = compareFixture().copyWith(
      documents: [
        Document(id: 'c1', title: 'PDF with blank final pages', fileName: 'a.pdf', pageCount: 8, importedAt: testNow),
      ],
    );
    final overrides = await testOverrides(content: InMemoryStudySetContentRepository({'demo-1': content}));
    final state = FullTranslationState(
      studySetId: 'demo-1',
      documentId: 'c1',
      targetLang: 'zh',
      loading: false,
      job: job(),
      paragraphs: paragraphs,
    );
    await tester.pumpWidget(
      testHost(
        const SizedBox(
          width: MMSizes.fullTranslationPanelWidth,
          child: FullTranslationPanel(studySetId: 'demo-1', documentId: 'c1', targetLang: 'zh'),
        ),
        overrides: [
          ...overrides,
          fullTranslationProvider(('demo-1', 'c1', 'zh'))
              .overrideWith(() => MockFullTranslationController('demo-1', 'c1', 'zh', state)),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    final lastPage = find.byTooltip('第 8 页 · 无需翻译');
    expect(lastPage, findsOneWidget);
    expect(find.byTooltip(RegExp('第 9 页')), findsNothing);
    expect(tester.widget<Opacity>(find.descendant(of: lastPage, matching: find.byType(Opacity))).opacity, .35);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
