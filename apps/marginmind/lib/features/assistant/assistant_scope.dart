import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart'
    show LegacyConversationMigration, assistantTitleModel, connectAssistant, generateAssistantTitle;
import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';
import '../workspace/workspace_controller.dart';
import 'assistant_controller.dart';
import 'assistant_network.dart';
import 'assistant_reader.dart';
import 'assistant_settings.dart';
import 'assistant_services.dart';
import 'assistant_writes.dart';

// ---- composition -------------------------------------------------------------------

/// One study set's saved conversations: the agent state storage and the IDs
/// in it.
class AssistantArchive {
  const AssistantArchive({required this.storage, required this.ids});

  final sdk.StateStorage storage;
  final Future<List<String>> Function() ids;
}

/// Conversations kept in memory, for repositories without files (tests,
/// samples). Nothing survives the process.
class MemoryConversationArchive implements sdk.StateStorage {
  final files = <String, String>{};
  @override
  Future<sdk.AgentState> loadOrCreate(String id, Map<String, dynamic>? metadata) async => files[id] == null
      ? sdk.AgentState(sessionId: id, metadata: metadata)
      : sdk.AgentState.fromJson(jsonDecode(files[id]!) as Map<String, dynamic>);
  @override
  Future<void> save(sdk.AgentState state) async => files[state.sessionId] = jsonEncode(state.toJson());
  @override
  Future<void> delete(String id) async => files.remove(id);
  @override
  Future<bool> exist(String id) async => files.containsKey(id);
  AssistantArchive get archive => AssistantArchive(storage: this, ids: () async => files.keys.toList());
}

/// `conversations/` inside the study set's package; in memory when the
/// repository does not keep files.
final assistantArchiveProvider = Provider.family<AssistantArchive, String>((ref, studySetId) {
  final directory = ref.watch(contentRepositoryProvider).resolveFile(studySetId, '');
  if (!p.isAbsolute(directory)) return MemoryConversationArchive().archive;
  final storage = ConversationStorage(Directory(directory));
  return AssistantArchive(storage: storage, ids: storage.list);
});

/// Optional network override for tests or alternate hosts. Production is built per request.
final assistantNetworkProvider = Provider<AssistantNetwork?>((ref) => null);

/// Text of a page of a PDF file, for the reader.
final assistantPageTextProvider = Provider<Future<String?> Function(String path, int page)>(
  (ref) => MMPdfEngine.pageText,
);

/// The dependencies a study set's assistant runs with. The window overrides
/// [assistantDependenciesProvider] with this value in its ProviderScope.
final assistantDependenciesForProvider = Provider.family<AssistantDependencies, String>((ref, studySetId) {
  return AssistantDependencies(
    studySetId: studySetId,
    model: unconfiguredAssistantModel,
    defaultModel: () => ref.read(assistantDefaultModelProvider),
    storage: ref.watch(assistantArchiveProvider(studySetId)).storage,
    executor: ref.watch(assistantMapEditExecutorProvider(studySetId)),
    notes: ref.watch(assistantNoteSaverProvider(studySetId)),
    online: assistantOnlineDefault(ref, studySetId),
    generateTitle: (current, question) async {
      final store = ref.read(assistantServicesStoreProvider);
      final resolved = await store.resolve(current);
      final model = assistantTitleModel(resolved, (await store.load()).enabledModels);
      final key = await ref.read(assistantSecretsProvider).read(AssistantServicesStore.account(model.serviceId!));
      final connection = connectAssistant(model, key ?? '');
      try {
        return await generateAssistantTitle(connection.client, model.model, question);
      } finally {
        connection.close();
      }
    },
    runFactory: (agent, conversation, question) async {
      final network = ref.read(assistantNetworkProvider) ?? await assistantNetworkFor(ref, studySetId, conversation);
      final workspace = ref.read(workspaceProvider(studySetId).notifier);
      final mapId = ref.read(workspaceProvider(studySetId)).activeMapId;
      // Revision and parents come from one snapshot, as the executor checks both.
      final snapshot = workspace.content;
      return assistantRunFactory(
        secrets: ref.read(assistantSecretsProvider),
        services: ref.read(assistantServicesStoreProvider),
        reader: WorkspaceReader(
          content: () => workspace.content,
          contexts: question.contexts,
          filePath: workspace.filePath,
          pageText: ref.read(assistantPageTextProvider),
        ),
        mapId: mapId,
        revision: () => assistantMapRevision(snapshot, mapId),
        parents: () => mapParents(snapshot, mapId),
        network: network,
      )(agent, conversation, question);
    },
  );
});

// ---- panel state ---------------------------------------------------------------------

/// A question an entry point asks: sent by the window's assistant host.
class AssistantRequest {
  const AssistantRequest(this.id, this.text, {this.skill});

  final int id;
  final String text;
  final String? skill;
}

/// What the assistant panel shows and holds besides the conversation.
class AssistantUi {
  const AssistantUi({
    this.contexts = const [],
    this.suppressed = const {},
    this.history = false,
    this.source,
    this.focusTick = 0,
    this.request,
    this.anchors = const {},
  });

  /// Context the user attached; cleared by sending.
  final List<ContextItem> contexts;

  /// Automatic contexts left out of the next message only.
  final Set<String> suppressed;

  /// The conversation list replaces the messages.
  final bool history;

  /// The external source the drawer shows.
  final Citation? source;

  /// Bumped when the input should take focus.
  final int focusTick;
  final AssistantRequest? request;

  /// Where attached selections are in the source, for notes and jumps.
  final Map<String, SourceAnchor> anchors;

  AssistantUi copyWith({
    List<ContextItem>? contexts,
    Set<String>? suppressed,
    bool? history,
    Citation? source,
    bool clearSource = false,
    int? focusTick,
    AssistantRequest? request,
    bool clearRequest = false,
    Map<String, SourceAnchor>? anchors,
  }) => AssistantUi(
    contexts: contexts ?? this.contexts,
    suppressed: suppressed ?? this.suppressed,
    history: history ?? this.history,
    source: clearSource ? null : (source ?? this.source),
    focusTick: focusTick ?? this.focusTick,
    request: clearRequest ? null : (request ?? this.request),
    anchors: anchors ?? this.anchors,
  );
}

final assistantUiProvider = NotifierProvider.family<AssistantUiController, AssistantUi, String>(
  AssistantUiController.new,
);

class AssistantUiController extends Notifier<AssistantUi> {
  AssistantUiController(this.studySetId);

  final String studySetId;
  int _requests = 0;

  @override
  AssistantUi build() => const AssistantUi();

  /// Attaches [item]; a selection keeps where it is in the source.
  void addContext(ContextItem item, {SourceAnchor? anchor}) => state = state.copyWith(
    contexts: [
      for (final c in state.contexts)
        if (c.id != item.id) c,
      item,
    ],
    anchors: anchor == null ? null : {...state.anchors, item.id: anchor},
  );

  void removeContext(String id) => state = state.copyWith(
    contexts: [
      for (final c in state.contexts)
        if (c.id != id) c,
    ],
  );

  /// Leaves an automatic context out of the next message, or brings it back.
  void toggleAuto(String id) {
    final next = {...state.suppressed};
    if (!next.remove(id)) next.add(id);
    state = state.copyWith(suppressed: next);
  }

  /// After sending: attached contexts go, automatic ones come back.
  void sent() => state = state.copyWith(contexts: const [], suppressed: const {});

  void showHistory(bool value) => state = state.copyWith(history: value, clearSource: true);
  void openSource(Citation citation) => state = state.copyWith(source: citation);
  void closeSource() => state = state.copyWith(clearSource: true);
  void focus() => state = state.copyWith(focusTick: state.focusTick + 1);
  void ask(String text, {String? skill}) =>
      state = state.copyWith(request: AssistantRequest(++_requests, text, skill: skill), history: false);
  void handled(int id) {
    if (state.request?.id == id) state = state.copyWith(clearRequest: true);
  }
}

/// Map nodes the hovered proposal items point at, outlined on the map.
final assistantPreviewProvider = NotifierProvider.family<AssistantPreview, Set<String>, String>(AssistantPreview.new);

class AssistantPreview extends Notifier<Set<String>> {
  AssistantPreview(this.studySetId);

  final String studySetId;

  @override
  Set<String> build() => const {};

  void show(Set<String> ids) => state = ids;
  void clear() {
    if (ref.mounted && state.isNotEmpty) state = const {};
  }
}

// ---- conversation list ------------------------------------------------------------------

enum ConversationState { idle, running, unfinished, failed }

/// A row of the conversation list and the sidebar.
class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.title,
    required this.questions,
    required this.notes,
    required this.state,
    required this.stamp,
  });

  /// [running] is true only for the live conversation; a saved running
  /// answer was interrupted.
  factory ConversationSummary.of(Conversation c, {bool live = false}) {
    final last = c.messages.lastOrNull;
    return ConversationSummary(
      id: c.id,
      title: c.title,
      questions: c.messages.where((m) => m.role == MessageRole.user).length,
      notes: c.messages.where((m) => m.noteId != null).length,
      state: switch (last?.status) {
        MessageStatus.running => live ? ConversationState.running : ConversationState.unfinished,
        MessageStatus.interrupted => ConversationState.unfinished,
        MessageStatus.error => ConversationState.failed,
        _ => ConversationState.idle,
      },
      stamp: _stamp(last?.id ?? c.id),
    );
  }

  final String id, title;
  final int questions, notes;
  final ConversationState state;

  /// Microseconds since the epoch of the last message (IDs start with it).
  final int stamp;

  static int _stamp(String id) => int.tryParse(id.split('-').first) ?? 0;
}

/// Old research sessions become read-only conversations, once per study set
/// and window session. Their files stay as they are.
final assistantLegacyMigrationProvider = FutureProvider.family<void, String>((ref, studySetId) async {
  final repository = ref.watch(contentRepositoryProvider);
  if (repository is! ResearchSessionRepository) return;
  await LegacyConversationMigration(
    studySetId: studySetId,
    sessions: repository as ResearchSessionRepository,
    content: repository,
    storage: ref.watch(assistantArchiveProvider(studySetId)).storage,
    model: ref.read(assistantDefaultModelProvider) ?? unconfiguredAssistantModel,
  ).migrate();
});

/// Saved conversations, newest first. Unreadable files are left out.
final assistantConversationsProvider = FutureProvider.family<List<ConversationSummary>, String>((
  ref,
  studySetId,
) async {
  try {
    await ref.watch(assistantLegacyMigrationProvider(studySetId).future);
  } catch (_) {
    // A session that cannot be migrated is retried next time; the rest list.
  }
  final archive = ref.watch(assistantArchiveProvider(studySetId));
  final out = <ConversationSummary>[];
  for (final id in await archive.ids()) {
    try {
      final view = (await archive.storage.loadOrCreate(id, null)).metadata['assistant.view'];
      if (view is! Map) continue;
      final c = Conversation.fromJson(Map<String, dynamic>.from(view));
      if (c.studySetId == studySetId && c.messages.isNotEmpty) out.add(ConversationSummary.of(c));
    } catch (_) {
      // A corrupt file is reported where it is opened, not in the list.
    }
  }
  return out..sort((a, b) => b.stamp.compareTo(a.stamp));
});

/// [saved] with the live conversations, the open one and the one answering
/// out of view ([background]), in place of their saved copies.
List<ConversationSummary> mergeLive(List<ConversationSummary> saved, Conversation live, {Conversation? background}) {
  final lives = [
    for (final c in [live, ?background])
      if (c.messages.isNotEmpty) c,
  ];
  final rest = [
    for (final s in saved)
      if (s.id != live.id && s.id != background?.id) s,
  ];
  if (lives.isEmpty) return rest;
  return [for (final c in lives) ConversationSummary.of(c, live: true), ...rest]
    ..sort((a, b) => b.stamp.compareTo(a.stamp));
}

/// Renames a conversation that is not open.
Future<void> renameSavedConversation(AssistantArchive archive, String id, String title) async {
  final state = await archive.storage.loadOrCreate(id, null);
  final view = state.metadata['assistant.view'];
  if (view is! Map) return;
  state.metadata['assistant.view'] = {...view, 'title': title.trim()};
  await archive.storage.save(state);
}

// ---- contexts -----------------------------------------------------------------------------

/// A passage of a document; its text goes with the question.
ContextItem selectionContext({required String documentId, required int page, required String quote}) => ContextItem(
  id: 'sel-${documentId.hashCode.toUnsigned(32)}-$page-${quote.hashCode.toUnsigned(32)}',
  kind: ContextKind.selection,
  documentId: documentId,
  page: page,
  displayText: quote.trim(),
);

ContextItem nodeContext({
  required String mapId,
  required String nodeId,
  required String title,
  bool branch = false,
  bool auto = false,
}) => ContextItem(
  id: '${auto ? 'auto-' : ''}${branch ? 'branch' : 'node'}-$mapId-$nodeId',
  kind: branch ? ContextKind.branch : ContextKind.node,
  mapId: mapId,
  nodeId: nodeId,
  displayText: title,
  auto: auto,
);

ContextItem pageContext({required Document document, required int page, bool auto = false}) => ContextItem(
  id: '${auto ? 'auto-' : ''}page-${document.id}-$page',
  kind: ContextKind.page,
  documentId: document.id,
  page: page,
  displayText: document.title,
  auto: auto,
);

ContextItem documentContext(Document document) => ContextItem(
  id: 'doc-${document.id}',
  kind: ContextKind.document,
  documentId: document.id,
  displayText: document.title,
);

ContextItem mapContext({required String mapId, required String title}) =>
    ContextItem(id: 'map-$mapId', kind: ContextKind.map, mapId: mapId, displayText: title);
