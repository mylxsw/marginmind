import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/study_notes/note_session.dart';
import 'package:marginmind/features/workspace/reflow_session.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../test/helpers.dart';

class EvidenceOrganizer implements NoteOrganizer {
  @override
  Future<NoteOutline> outline(NoteMaterials materials, NoteSettings settings) async => NoteOutline([
    for (final (i, h) in materials.highlights.indexed)
      NoteOutlineSection(title: i == 0 ? '主动回想' : '间隔练习', refs: [h.ref], why: i == 0 ? '通过复述发现理解中的空白' : '分散练习，让记忆更牢固'),
  ]);
  @override
  Future<NoteDraft> write(NoteMaterials m, NoteOutline outline, NoteSettings settings) async => NoteDraft([
    for (final (i, s) in outline.sections.indexed)
      NoteDraftSection(
        title: s.title,
        question: i == 0 ? '主动回想为什么比反复阅读更有效？' : '如何安排一次间隔练习？',
        blocks: [
          NoteDraftBlock.fromJson({
            'type': 'summary',
            'text': i == 0 ? '用自己的话复述，才能发现理解中的空白。' : '把练习分散在几天里，让每次回想重新建立记忆的路径。',
          }),
          for (final r in s.refs) NoteDraftBlock.fromJson({'type': 'quote', 'ref': r}),
          NoteDraftBlock.fromJson({
            'type': 'points',
            'items': i == 0 ? ['合上书，写出三个关键点。', '对照原文，补上遗漏。'] : ['隔一天再回想。', '逐步拉长两次练习的间隔。'],
          }),
          if (i == 0) NoteDraftBlock.fromJson({'type': 'xref', 'to': 1, 'text': '与「间隔练习」关联：让回想成为持续的习惯。'}),
        ],
      ),
  ]);
  @override
  Future<NotePlacements> place(NoteMaterials m, StudyNote note) async => NotePlacements([]);
}

class EvidenceSession extends NoteSession {
  EvidenceSession(this.gate) : super(EvidenceOrganizer());
  final Completer<void> gate;
  @override
  Stream<NoteDraftSection> write(NoteMaterials m, NoteOutline outline, NoteSettings settings, int startAt) async* {
    final draft = await organizer.write(m, outline, settings);
    for (final (i, s) in draft.sections.indexed) {
      if (i < startAt) continue;
      if (i == 1) await gate.future;
      yield s;
    }
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().defaultTestTimeout = const Timeout(Duration(minutes: 5));
  testWidgets('macOS AI outline, streaming progress and AI markers', (tester) async {
    await DesktopWindow.initialize(title: 'MarginMind', minimumSize: MMSizes.windowMinSize);
    final directory = await Directory.systemTemp.createTemp('marginmind-ai-notes-');
    addTearDown(() => directory.delete(recursive: true));
    final file = await File('${directory.path}/记忆与学习.md').writeAsString('''# 记忆与学习

## 主动回想

阅读带来熟悉感，但熟悉并不等于掌握。合上书，试着用自己的话复述，才能发现理解中的空白。主动回想让记忆更加牢固。

## 间隔练习

学习需要时间。把练习分散在几天里，比在同一晚反复阅读更有效。每次回想，都会重新建立通向知识的路径。
''');
    final gate = Completer<void>();
    final container = await pumpApp(
      tester,
      size: const Size(1280, 820),
      prefs: {'settings.language': 'zh', 'settings.appearance': 'light'},
      content: InMemoryStudySetContentRepository(),
      overrides: [
        assistantConfiguredProvider.overrideWith((ref) async => true),
        noteSessionFactoryProvider.overrideWithValue(() async => EvidenceSession(gate)),
      ],
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
      await owner.excerptSource(
        doc.id,
        SourceSelection.text([chapter.anchor(start, start + passage.length, revision: doc.revision!)]),
        MMAnnotationColor.yellow,
      );
    }
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

    await tester.tap(find.byKey(const ValueKey('toolbar-organize-note')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-preview-outline')));
    await tester.pumpAndSettle();
    await shot('outline');
    await tester.tap(find.byKey(const ValueKey('outline-generate')));
    await tester.pumpAndSettle();
    await shot('generating');
    gate.complete();
    await tester.pumpAndSettle();
    expect(owner.content.studyNotes.single.sections, hasLength(2));
    await settleHud(tester);
    await shot('ai-on');
    final marker = find.byKey(const ValueKey('note-ai-markers'));
    if (marker.evaluate().isNotEmpty) {
      await tester.tap(marker);
    } else {
      await tester.tap(find.byKey(const ValueKey('note-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('显示 AI 标记'));
    }
    await tester.pumpAndSettle();
    await shot('ai-off');
    expect(tester.takeException(), isNull);
  });
}
