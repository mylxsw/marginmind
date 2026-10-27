// Native acceptance fixture: real widgets, isolated in-memory research data.
// flutter run -d macos -t benchmark/research_extensions.dart
import 'dart:async';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:mm_research/mm_research.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/research/research_controller.dart';
import 'package:marginmind/features/research/research_drafts.dart';
import 'package:marginmind/features/research/research_intents.dart';
import 'package:marginmind/features/research/research_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DesktopWindow.initialize(
    title: 'GUL-524 Research acceptance',
    minimumSize: const Size(900, 650),
    initialSize: const Size(1280, 820),
  );
  // Isolated acceptance fixture; never reads or writes personal preferences.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({'settings.language': 'zh', 'settings.appearance': 'light'});
  final prefs = await SharedPreferences.getInstance();
  final now = DateTime.now();
  var sequence = 0;
  final editor = StudySetEditor(newId: () => 'fixture-${sequence++}', now: () => now);
  final paragraph = markdownArticle(
    ReadableHtml(
      url: Uri.parse('https://doi.org/10.1126/science.185.4157.1124'),
      title: 'Judgment under Uncertainty',
      html: '<p>People rely on a limited number of heuristic principles.</p>',
    ),
  ).paragraphs;
  final repo = InMemoryStudySetContentRepository();
  final file = await repo.writeResearchSnapshot('acceptance', encodeSnapshot(paragraph));
  final source = ResearchSource(
    id: 'paper',
    url: 'https://doi.org/10.1126/science.185.4157.1124',
    canonicalUrl: 'https://doi.org/10.1126/science.185.4157.1124',
    kind: 'paper',
    title: 'Judgment under Uncertainty: Heuristics and Biases',
    authors: ['Amos Tversky', 'Daniel Kahneman'],
    publishedAt: DateTime(1974),
    doi: '10.1126/science.185.4157.1124',
    fetchedAt: now,
    readState: 'abstractOnly',
    versions: [SourceVersion(version: 1, snapshotFile: file, hash: file.split('/').last.split('.').first)],
  );
  final evidence = Evidence(
    id: 'quote',
    sourceId: source.id,
    sourceVersion: 1,
    quote: paragraph.values.first,
    locator: EvidenceLocator.paragraph(paragraph.keys.first),
    acquisition: EvidenceAcquisition.auto,
    capturedAt: now,
  );
  final note = ResearchNote(
    id: 'note',
    title: '锚定效应',
    question: '为什么最先看到的数字会影响判断？',
    body: '最初的信息会成为后续估计的参照。调整通常不充分，因此判断仍受起点影响。',
    citations: const [EvidenceRef('quote')],
    sessionId: 'research',
    createdAt: now,
    updatedAt: now,
  );
  var content = editor.saveResearchNote(
    StudySetContent.empty,
    note,
    evidence: [evidence],
    sources: [source],
    createCard: true,
  );
  content = editor.setResearchReview(content, note.id, enabled: true);
  await repo.update('acceptance', (_) => content);
  final video = videoSource(Uri.parse('https://youtu.be/dQw4w9WgXcQ'), now);
  await repo.saveResearchSession(
    'acceptance',
    ResearchSession(
      id: 'research',
      question: note.question,
      status: 'done',
      createdAt: now,
      updatedAt: now,
      sourceIds: [source.id, video.id],
      drafts: [
        ResearchDrafts(kinds: {ResearchSourceKind.paper, ResearchSourceKind.video}).toJson(),
        {
          'type': 'engine',
          'sources': [source.toJson(), video.toJson()],
          'evidence': [evidence.toJson()],
          'metadata': {
            source.id: {'openAccess': false},
          },
        },
      ],
    ),
  );
  await repo.saveResearchSession(
    'acceptance',
    ResearchSession(
      id: 'later',
      question: '检索练习为什么有助于长期记忆？',
      status: 'draft',
      createdAt: now,
      updatedAt: now,
      drafts: [
        const ResearchDrafts(later: true, kinds: {ResearchSourceKind.paper}, keywords: ['retrieval practice']).toJson(),
      ],
    ),
  );
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      studySetRepositoryProvider.overrideWithValue(
        InMemoryStudySetRepository(
          sets: [StudySet(id: 'acceptance', colorIndex: 0, title: '认知科学 · 研究', createdAt: now, lastOpenedAt: now)],
        ),
      ),
      contentRepositoryProvider.overrideWithValue(repo),
      pdfRenderingEnabledProvider.overrideWithValue(false),
      researchRecoveryProvider.overrideWithValue(ResearchRecovery(repo, () async => ['acceptance'])),
    ],
  );
  container.read(navigationProvider.notifier).openStudySet('acceptance');
  runApp(UncontrolledProviderScope(container: container, child: const MarginMindApp()));
  await Future<void>.delayed(const Duration(seconds: 2));
  container.read(researchPanelProvider('acceptance').notifier).showNote('note');
}
