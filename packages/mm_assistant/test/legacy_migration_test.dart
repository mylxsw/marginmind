import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:test/test.dart';

class Storage implements sdk.StateStorage {
  final files = <String, String>{};
  bool fail = false;
  @override
  Future<void> save(sdk.AgentState state) async {
    if (fail) throw StateError('disk');
    files[state.sessionId] = jsonEncode(state.toJson());
  }

  @override
  Future<sdk.AgentState> loadOrCreate(String id, Map<String, dynamic>? data) async => files.containsKey(id)
      ? sdk.AgentState.fromJson(jsonDecode(files[id]!))
      : sdk.AgentState(sessionId: id, metadata: data);
  @override
  Future<bool> exist(String id) async => files.containsKey(id);
  @override
  Future<void> delete(String id) async {
    files.remove(id);
  }
}

class FailingContent extends InMemoryStudySetContentRepository {
  bool fail = true;
  @override
  Future<StudySetContent> update(String id, StudySetContent Function(StudySetContent) change) async {
    if (fail) throw StateError('disk');
    return super.update(id, change);
  }
}

void main() {
  final time = DateTime(2026, 10, 27);
  const model = AssistantModel(
    provider: AssistantProvider.claude,
    model: 'old',
    endpoint: 'https://api.anthropic.com/v1/messages',
  );
  test('lossless legacy archive, citations, multiple turns and note association survive round trip', () async {
    final source = ResearchSource(
      id: 's',
      url: 'https://example.com/paper',
      canonicalUrl: 'https://example.com/paper',
      kind: 'web',
      title: 'Paper',
      fetchedAt: time,
    );
    final evidence = Evidence(
      id: 'e',
      sourceId: 's',
      sourceVersion: 1,
      quote: 'Quote',
      locator: const EvidenceLocator.paragraph('p'),
      acquisition: EvidenceAcquisition.auto,
      capturedAt: time,
    );
    final note = ResearchNote(
      id: 'n',
      title: 'Note',
      body: 'Answer',
      sessionId: 'old',
      origin: NoteOrigin.ai,
      createdAt: time,
      updatedAt: time,
    );
    final repo = InMemoryStudySetContentRepository({
      'set': StudySetContent(researchNotes: [note]),
    });
    final session = ResearchSession(
      id: 'old',
      question: 'Q',
      createdAt: time,
      updatedAt: time,
      history: [
        {
          'question': 'Q1',
          'answer': 'A1',
          'cites': [
            {'evidence': 'e', 'at': 2},
          ],
        },
        {'question': 'Q2', 'answer': 'A2'},
      ],
      drafts: [
        {
          'type': 'engine',
          'evidence': [evidence.toJson()],
          'sources': [source.toJson()],
        },
      ],
      savedNoteIds: ['n'],
    );
    await repo.saveResearchSession('set', session);
    final storage = Storage();
    final migration = LegacyConversationMigration(
      studySetId: 'set',
      sessions: repo,
      content: repo,
      storage: storage,
      model: model,
    );
    expect(await migration.migrate(), ['legacy-old']);
    final stored = await storage.loadOrCreate('legacy-old', null);
    final view = Conversation.fromJson(Map<String, dynamic>.from(stored.metadata['assistant.view']));
    expect(view.readOnly, isTrue);
    expect(view.copyWith(title: 'copy').readOnly, isTrue);
    expect(view.messages.map((m) => m.text), ['Q1', 'A1[source:1]', 'Q2', 'A2']);
    expect(view.messages[1].citations.single.quote, 'Quote');
    expect(view.messages[1].citations.single.url, source.url);
    expect(view.messages[1].citations.single.paragraphId, 'p');
    expect(view.messages.last.noteId, 'n');
    final roundTrip = ResearchSession.fromJson(Map<String, Object?>.from(stored.metadata['assistant.legacySession']));
    expect(roundTrip.toJson(), session.toJson());
    expect((await repo.load('set')).researchNote('n')!.conversationId, 'legacy-old');
    expect((await repo.loadResearchSession('set', 'old'))!.toJson(), session.toJson());
    final bytes = storage.files['legacy-old'];
    await migration.migrate();
    expect(storage.files['legacy-old'], bytes);
  });
  test('empty/partial history and save failure are retryable without losing old data', () async {
    final repo = InMemoryStudySetContentRepository();
    await repo.saveResearchSession(
      'set',
      ResearchSession(id: 'empty', question: 'Empty', createdAt: time, updatedAt: time),
    );
    await repo.saveResearchSession(
      'set',
      ResearchSession(
        id: 'partial',
        question: 'Q',
        history: [
          {
            'question': 'Partial',
            'cites': [
              {'evidence': 'missing'},
            ],
          },
        ],
        createdAt: time,
        updatedAt: time,
      ),
    );
    final storage = Storage()..fail = true;
    final migration = LegacyConversationMigration(
      studySetId: 'set',
      sessions: repo,
      content: repo,
      storage: storage,
      model: model,
    );
    await expectLater(migration.migrate(), throwsStateError);
    expect((await repo.listResearchSessions('set')).length, 2);
    storage.fail = false;
    expect((await migration.migrate()).length, 2);
    final data = await storage.loadOrCreate('legacy-empty', null);
    final view = Conversation.fromJson(Map<String, dynamic>.from(data.metadata['assistant.view']));
    expect(view.messages.first.text, 'Empty');
    expect(view.messages.last.text, '');
  });
  test('conversation commit followed by note failure resumes without rewriting the archive', () async {
    final repo = FailingContent();
    await repo.saveResearchSession(
      'set',
      ResearchSession(id: 'retry', question: 'Retry', createdAt: time, updatedAt: time),
    );
    final storage = Storage();
    final migration = LegacyConversationMigration(
      studySetId: 'set',
      sessions: repo,
      content: repo,
      storage: storage,
      model: model,
    );
    await expectLater(migration.migrate(), throwsStateError);
    final archive = storage.files['legacy-retry'];
    expect(archive, isNotNull);
    repo.fail = false;
    await migration.migrate();
    expect(storage.files['legacy-retry'], archive);
    final state = await storage.loadOrCreate('legacy-retry', null);
    state.metadata['assistant.view']['studySetId'] = 'another-set';
    await storage.save(state);
    await expectLater(migration.migrate(), throwsFormatException);
  });
}
