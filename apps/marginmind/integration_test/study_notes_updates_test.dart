import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/study_notes/note_view.dart';
import 'package:marginmind/features/workspace/reflow_session.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/settings/app_settings.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../test/helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().defaultTestTimeout = const Timeout(Duration(minutes: 5));
  testWidgets('macOS incremental update preview and three templates', (tester) async {
    await DesktopWindow.initialize(title: 'MarginMind', minimumSize: MMSizes.windowMinSize);
    final directory = await Directory.systemTemp.createTemp('marginmind-study-notes-');
    addTearDown(() => directory.delete(recursive: true));
    final file = await File('${directory.path}/记忆与学习.md').writeAsString('''# 记忆与学习

## 主动回想

阅读带来熟悉感，但熟悉并不等于掌握。合上书，试着用自己的话复述，才能发现理解中的空白。主动回想让记忆更加牢固。

## 间隔练习

学习需要时间。把练习分散在几天里，比在同一晚反复阅读更有效。每次回想，都会重新建立通向知识的路径。

把一本书变成自己的知识，需要提问、练习与连接。
''');
    final container = await pumpApp(
      tester,
      size: const Size(1280, 820),
      prefs: {'settings.language': 'zh', 'settings.appearance': 'light'},
      content: InMemoryStudySetContentRepository(),
      clock: DateTime.now,
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final owner = container.read(workspaceProvider('demo-1').notifier);
    await owner.importDocuments([(path: file.path, name: '记忆与学习.md')]);
    await tester.pumpAndSettle();
    final doc = owner.content.documents.single;
    final session = container.read(reflowSessionProvider(('demo-1', doc.id)));
    await session.initialize();
    for (final passage in ['合上书，试着用自己的话复述，才能发现理解中的空白。', '把练习分散在几天里，比在同一晚反复阅读更有效。']) {
      final chapter = session.book!.chapters.firstWhere((c) => c.canonicalText.contains(passage));
      final start = chapter.canonicalText.indexOf(passage);
      final anchor = chapter.anchor(start, start + passage.length, revision: doc.revision!);
      await owner.excerptSource(doc.id, SourceSelection.text([anchor]), MMAnnotationColor.yellow);
    }
    await owner.addNote('读完一节，先合上书，再写出三个关键点。');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('toolbar-organize-note')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-generate')));
    await tester.pumpAndSettle();
    expect(find.byType(StudyNoteView), findsOneWidget);
    expect(owner.content.studyNotes, hasLength(1));

    Future<void> shot(String name) async {
      const server = String.fromEnvironment('GUL588_SHOT_SERVER');
      if (server.isEmpty) return;
      await tester.pumpAndSettle();
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse('$server/capture/$name?pid=$pid'));
        final response = await request.close();
        expect(response.statusCode, 200, reason: await response.transform(const SystemEncoding().decoder).join());
      } finally {
        client.close(force: true);
      }
    }

    final note = owner.content.studyNotes.single;
    await owner.changeStudyNote(
      note.id,
      (n) => n.copyWith(
        sections: [
          for (final section in n.sections)
            section == n.sections.first
                ? NoteSection(
                    id: section.id,
                    title: section.title,
                    question: '为什么合上书回想更有效？',
                    blocks: [
                      const TextBlock(
                        id: 'summary-demo',
                        text: '主动回想能帮助我们发现理解中的空白。',
                        kind: TextKind.summary,
                        origin: NoteOrigin.ai,
                      ),
                      ...section.blocks,
                    ],
                  )
                : section,
        ],
      ),
    );
    await owner.editStudyNoteBlock(note.id, 'summary-demo', text: '合上书，用自己的话复述，才能发现真正没懂的地方。');
    final passage = '主动回想让记忆更加牢固。';
    final chapter = session.book!.chapters.firstWhere((c) => c.canonicalText.contains(passage));
    final start = chapter.canonicalText.indexOf(passage);
    await owner.excerptSource(
      doc.id,
      SourceSelection.text([chapter.anchor(start, start + passage.length, revision: doc.revision!)]),
      MMAnnotationColor.green,
    );
    owner.openStudyNote(note.id);
    owner.setLayout(MMSplitMode.secondary);
    await tester.pumpAndSettle();
    await shot('update-banner');
    await tester.tap(find.byKey(const ValueKey('note-update-preview')));
    await tester.pumpAndSettle();
    await shot('update-preview');
    await tester.tap(find.byKey(const ValueKey('note-update-cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-update-preview')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-update-apply')));
    await settleHud(tester);
    await shot('reading');
    await owner.changeStudyNote(note.id, (n) => n.copyWith(template: NoteTemplate.cornell));
    await tester.pumpAndSettle();
    await shot('cornell');
    await owner.changeStudyNote(note.id, (n) => n.copyWith(template: NoteTemplate.review));
    await tester.pumpAndSettle();
    await shot('review');
    await container.read(settingsProvider.notifier).setAppearance(AppearancePreference.dark);
    await tester.pumpAndSettle();
    await shot('review-dark');
    expect(tester.takeException(), isNull);
    await settleHud(tester);
  });
}
