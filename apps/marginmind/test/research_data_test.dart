import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_platform/mm_platform.dart';

import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late InMemoryStudySetContentRepository repo;
  late WorkspaceController controller;
  String? internal;
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    internal = null;
    repo = InMemoryStudySetContentRepository();
    final snapshot = await repo.writeResearchSnapshot('demo-1', '# Source');
    final hash = snapshot.split('/').last.split('.').first;
    final now = DateTime.utc(2026, 10, 26);
    final editor = StudySetEditor(newId: () => 'card', now: () => now);
    final note = ResearchNote(
      id: 'note',
      title: 'Finding',
      body: '**body**',
      sessionId: 'session',
      citations: [const EvidenceRef('evidence')],
      createdAt: now,
      updatedAt: now,
    );
    final content = editor.saveResearchNote(
      StudySetContent.empty,
      note,
      createCard: true,
      sources: [
        ResearchSource(
          id: 'source',
          url: 'https://example.com',
          canonicalUrl: 'https://example.com',
          kind: 'web',
          title: 'Source',
          fetchedAt: now,
          versions: [SourceVersion(version: 1, snapshotFile: snapshot, hash: hash)],
        ),
      ],
      evidence: [
        Evidence(
          id: 'evidence',
          sourceId: 'source',
          sourceVersion: 1,
          quote: 'text',
          locator: const EvidenceLocator.page(1),
          acquisition: EvidenceAcquisition.userPaste,
          capturedAt: now,
        ),
      ],
    );
    await repo.update('demo-1', (_) => content);
    await repo.saveResearchSession(
      'demo-1',
      ResearchSession(
        id: 'session',
        question: 'why?',
        history: [
          {'query': 'original'},
        ],
        createdAt: now,
        updatedAt: now,
      ),
    );
    container = ProviderContainer(overrides: await testOverrides(content: repo));
    container.listen(workspaceProvider('demo-1'), (_, _) {});
    await container.read(contentProvider('demo-1').future);
    controller = container.read(workspaceProvider('demo-1').notifier);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MMMapClipboard.channel, (
      call,
    ) async {
      if (call.method == 'write') {
        internal = (call.arguments as Map)['internal'] as String;
        return null;
      }
      return {'text': '', 'internal': internal};
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    container.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      MMMapClipboard.channel,
      null,
    );
  });

  test('controller hydrates snapshots before copy and paste, undo/redo retains evidence graph', () async {
    controller.selectCards(['card']);
    await controller.copySelection();
    final entries = MapClipboard.decode(internal!)!;
    expect(entries.single.snapshots.values.single, '# Source');
    expect(MapClipboard.toText(entries), 'Finding');
    controller.selectCard(null);
    await controller.pasteSelection();
    final after = controller.content.toJson();
    expect(controller.content.researchNotes.length, 2);
    expect(controller.content.evidence.length, 2);
    expect(controller.content.researchSources.length, 2);
    expect(controller.content.noteAttachments.length, 2);
    await controller.undo();
    expect(controller.content.researchNotes.single.id, 'note');
    expect(controller.content.evidence.single.id, 'evidence');
    await controller.redo();
    expect(controller.content.toJson(), after);
    final restored = (await repo.loadResearchSession('demo-1', 'session'))!;
    expect(restored.savedNoteIds, ['note']);
    expect(restored.history, [
      {'query': 'original'},
    ]);
  });

  test('controller cut retains note and paste rebuilds associations atomically', () async {
    controller.selectCards(['card']);
    await controller.copySelection(cut: true);
    expect(controller.content.cards, isEmpty);
    expect(controller.content.noteAttachments, isEmpty);
    expect(controller.content.researchNotes.single.id, 'note');
    await controller.undo();
    expect(controller.content.noteAttachments.single.target, isA<CardTarget>());
    expect(controller.content.cards.single.id, 'card');
  });
}
