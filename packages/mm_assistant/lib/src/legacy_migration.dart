import 'package:dart_agent_core/dart_agent_core.dart' show AgentState, StateStorage;
import 'package:mm_core/mm_core.dart';

import 'citations.dart';
import 'models.dart';
import 'providers.dart';

/// Non-destructive and resumable: write the conversation before updating note
/// links. Existing conversations are never overwritten, including on retry.
class LegacyConversationMigration {
  LegacyConversationMigration({
    required this.studySetId,
    required this.sessions,
    required this.content,
    required this.storage,
    required this.model,
  });
  final String studySetId;
  final ResearchSessionRepository sessions;
  final StudySetContentRepository content;
  final StateStorage storage;
  final AssistantModel model;

  Future<List<String>> migrate() async {
    final ids = <String>[];
    for (final session in await sessions.listResearchSessions(studySetId)) {
      // Session IDs use the same path-safe UUID convention as conversations.
      final id = 'legacy-${session.id}';
      ids.add(id);
      if (!await storage.exist(id)) {
        final snapshot = await content.load(studySetId);
        final messages = <Message>[];
        final engine = session.drafts.where((d) => d['type'] == 'engine').firstOrNull;
        final sources = <String, ResearchSource>{for (final source in snapshot.researchSources) source.id: source};
        for (final raw in engine?['sources'] as List? ?? []) {
          final source = ResearchSource.fromJson((raw as Map).cast<String, Object?>());
          sources[source.id] = source;
        }
        final evidence = <String, Evidence>{for (final e in snapshot.evidence) e.id: e};
        for (final raw in engine?['evidence'] as List? ?? []) {
          final e = Evidence.fromJson((raw as Map).cast<String, Object?>());
          evidence[e.id] = e;
        }
        final turns = session.history.isEmpty
            ? [
                {'question': session.question, 'answer': ''},
              ]
            : session.history;
        for (var i = 0; i < turns.length; i++) {
          final turn = turns[i];
          final requestId = '$id-$i';
          final citations = <Citation>[];
          var answer = turn['answer'] as String? ?? '';
          final markers = <(int, String)>[];
          for (final raw in turn['cites'] as List? ?? []) {
            final cite = raw as Map;
            final e = evidence[cite['evidence']];
            if (e == null) continue;
            citations.add(
              Citation(
                marker: '[source:${citations.length + 1}]',
                sourceId: e.sourceId,
                version: e.sourceVersion,
                paragraphId: e.locator.paragraphId,
                page: e.locator.page,
                quote: e.quote,
                url: sources[e.sourceId]?.url,
              ),
            );
            final offset = cite['at'] is int ? (cite['at'] as int).clamp(0, answer.length) : answer.length;
            markers.add((offset, citations.last.marker));
          }
          markers.sort((a, b) => b.$1.compareTo(a.$1));
          for (final marker in markers) {
            answer = answer.substring(0, marker.$1) + marker.$2 + answer.substring(marker.$1);
          }
          final notes = snapshot.researchNotes.where((n) => n.sessionId == session.id).toList();
          messages.add(
            Message(
              id: '$requestId-user',
              requestId: requestId,
              role: MessageRole.user,
              text: turn['question'] as String? ?? session.question,
            ),
          );
          messages.add(
            Message(
              id: '$requestId-agent',
              requestId: requestId,
              role: MessageRole.agent,
              text: answer,
              citations: citations,
              noteId: i == turns.length - 1 ? notes.firstOrNull?.id : null,
            ),
          );
        }
        final view = Conversation(
          id: id,
          studySetId: studySetId,
          model: model,
          title: session.question,
          messages: messages,
          online: false,
          readOnly: true,
        );
        await storage.save(
          AgentState(
            sessionId: id,
            metadata: {
              'assistant.view': view.toJson(),
              // Preserve all original citation positions, notes, source metadata and
              // status for lossless archival export. The old session also survives.
              'assistant.legacySession': session.toJson(),
            },
          ),
        );
      }
      final existing = await storage.loadOrCreate(id, null);
      final view = Conversation.fromJson(Map<String, dynamic>.from(existing.metadata['assistant.view']));
      if (view.id != id ||
          view.studySetId != studySetId ||
          !view.readOnly ||
          existing.metadata['assistant.legacySession']?['id'] != session.id) {
        throw const FormatException('Legacy conversation identity mismatch');
      }
      await content.update(
        studySetId,
        (c) => c.copyWith(
          researchNotes: [
            for (final note in c.researchNotes)
              if (note.sessionId == session.id && note.conversationId == null)
                ResearchNote.fromJson({...note.toJson(), 'conversationId': id})
              else
                note,
          ],
        ),
      );
    }
    return ids;
  }
}
