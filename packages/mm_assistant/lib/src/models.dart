import 'package:mm_core/mm_core.dart';

import 'citations.dart';
import 'permissions.dart';
import 'model_policy/routing.dart';
import 'providers.dart';

enum ContextKind { selection, node, branch, page, document, map }

class ContextItem {
  const ContextItem({
    required this.id,
    required this.kind,
    required this.displayText,
    this.documentId,
    this.page,
    this.mapId,
    this.nodeId,
    this.auto = false,
  });
  final String id, displayText;
  final ContextKind kind;
  final String? documentId, mapId, nodeId;
  final int? page;
  final bool auto;
  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'displayText': displayText,
    'documentId': documentId,
    'page': page,
    'mapId': mapId,
    'nodeId': nodeId,
    'auto': auto,
  };
  factory ContextItem.fromJson(Map<String, dynamic> j) => ContextItem(
    id: j['id'],
    kind: ContextKind.values.byName(j['kind']),
    displayText: j['displayText'],
    documentId: j['documentId'],
    page: j['page'],
    mapId: j['mapId'],
    nodeId: j['nodeId'],
    auto: j['auto'],
  );
}

/// The host supplies the study set's document IDs independently of the question's
/// focus. Selections and pages locate the question, without restricting document
/// reads to those pages. Callers without a document catalog retain scoped reads.
ReadScope scopeFromContexts(String studySetId, List<ContextItem> contexts, {Iterable<String> documentIds = const []}) {
  final pages = <String, Set<int>>{}, branches = <String, Set<String>>{};
  final docs = documentIds.toSet(), maps = <String>{}, selections = <String>{};
  for (final c in contexts) {
    switch (c.kind) {
      case ContextKind.selection:
        selections.add(c.id);
      case ContextKind.page:
        if (c.documentId != null && c.page != null) (pages[c.documentId!] ??= {}).add(c.page!);
      case ContextKind.document:
        if (c.documentId != null) docs.add(c.documentId!);
      case ContextKind.map:
        if (c.mapId != null) maps.add(c.mapId!);
      case ContextKind.node || ContextKind.branch:
        if (c.mapId != null && c.nodeId != null) (branches[c.mapId!] ??= {}).add(c.nodeId!);
    }
  }
  return ReadScope(
    studySetId: studySetId,
    pages: pages,
    documents: docs,
    maps: maps,
    selections: selections,
    branches: branches,
  );
}

enum MessageRole { user, agent }

enum MessageStatus { running, done, stopped, error, interrupted }

enum TraceStatus { running, done, error, denied }

class TraceStep {
  const TraceStep(this.id, this.toolName, this.status, {this.reason, this.narration, this.count = 1});
  final String id, toolName;
  final TraceStatus status;
  final String? reason, narration;
  final int count;
  Map<String, dynamic> toJson() => {
    'id': id,
    'toolName': toolName,
    'status': status.name,
    'reason': reason,
    'narration': narration,
    'count': count,
  };
  factory TraceStep.fromJson(Map<String, dynamic> j) => TraceStep(
    j['id'],
    j['toolName'],
    TraceStatus.values.byName(j['status']),
    reason: j['reason'],
    narration: j['narration'],
    count: j['count'] ?? 1,
  );
}

enum ProposalStatus { pending, applied, dismissed }

class ProposalView {
  ProposalView({required this.proposal, this.status = ProposalStatus.pending, Set<String>? selected, this.receipt})
    : selected = Set.unmodifiable(selected ?? proposal.operations.map((o) => o.id));
  final MapEditProposal proposal;
  final ProposalStatus status;
  final Set<String> selected;
  final MapEditReceipt? receipt;
  ProposalView copyWith({ProposalStatus? status, Set<String>? selected, MapEditReceipt? receipt}) => ProposalView(
    proposal: proposal,
    status: status ?? this.status,
    selected: selected ?? this.selected,
    receipt: receipt ?? this.receipt,
  );
  Map<String, dynamic> toJson() => {
    'proposal': proposal.toJson(),
    'status': status.name,
    'selected': selected.toList(),
    'receipt': receipt?.toJson(),
  };
  factory ProposalView.fromJson(Map<String, dynamic> j) => ProposalView(
    proposal: MapEditProposal.fromJson(Map<String, dynamic>.from(j['proposal'])),
    status: ProposalStatus.values.byName(j['status']),
    selected: Set<String>.from(j['selected']),
    receipt: j['receipt'] == null ? null : MapEditReceipt.fromJson(Map<String, dynamic>.from(j['receipt'])),
  );
}

/// Explicit allowlist for UI details/copy. Never copies provider messages or arguments.
class AssistantDiagnostics {
  AssistantDiagnostics({
    required this.requestId,
    required this.model,
    required this.host,
    this.failure,
    this.httpStatus,
    this.fallback = false,
    List<TraceStep> tools = const [],
  }) : tools = List.unmodifiable(tools);
  final String requestId, model, host;
  final String? failure;
  final int? httpStatus;
  final bool fallback;
  final List<TraceStep> tools;
  Map<String, dynamic> toJson() => {
    'requestId': requestId,
    'model': model,
    'host': host,
    'failure': failure,
    'httpStatus': httpStatus,
    'fallback': fallback,
    'tools': [
      for (final t in tools) {'name': t.toolName, 'result': t.status.name, 'reason': t.reason},
    ],
  };
  factory AssistantDiagnostics.fromJson(Map<String, dynamic> j) => AssistantDiagnostics(
    requestId: j['requestId'],
    model: j['model'],
    host: j['host'],
    failure: j['failure'],
    httpStatus: j['httpStatus'],
    fallback: j['fallback'] ?? false,
    tools: [
      for (final t in j['tools'] as List? ?? [])
        TraceStep('', t['name'], TraceStatus.values.byName(t['result']), reason: t['reason']),
    ],
  );
}

class Message {
  Message({
    required this.id,
    required this.requestId,
    required this.role,
    this.text = '',
    this.status = MessageStatus.done,
    this.errorKind,
    List<ContextItem> contexts = const [],
    List<TraceStep> traces = const [],
    List<Citation> citations = const [],
    List<ProposalView> proposals = const [],
    List<ReadPermissionView> permissions = const [],
    this.skill,
    this.taskModel,
    this.summaryMessageIds,
    this.noteId,
    this.online = false,
    this.startedAt,
    this.endedAt,
    this.diagnostics,
  }) : contexts = List.unmodifiable(contexts),
       traces = List.unmodifiable(traces),
       citations = List.unmodifiable(citations),
       proposals = List.unmodifiable(proposals),
       permissions = List.unmodifiable(permissions);
  final String id, requestId, text;
  final MessageRole role;
  final MessageStatus status;
  final ResearchFailureKind? errorKind;
  final List<ContextItem> contexts;
  final List<TraceStep> traces;
  final List<Citation> citations;
  final List<ProposalView> proposals;
  final List<ReadPermissionView> permissions;
  bool get waitingForPermission => permissions.any((permission) => permission.status == ReadPermissionStatus.pending);
  final String? skill, noteId;
  final ModelReference? taskModel;
  final List<String>? summaryMessageIds;
  final bool online;
  final DateTime? startedAt, endedAt;
  final AssistantDiagnostics? diagnostics;
  int get elapsedSeconds =>
      startedAt == null ? 0 : ((endedAt ?? DateTime.now()).difference(startedAt!).inMilliseconds / 1000).ceil();
  List<TraceStep> get activity {
    final out = <TraceStep>[];
    for (final t in traces) {
      final last = out.lastOrNull;
      if (t.narration == null &&
          last != null &&
          last.narration == null &&
          last.toolName == t.toolName &&
          last.status == t.status &&
          last.reason == t.reason) {
        out[out.length - 1] = TraceStep(
          last.id,
          last.toolName,
          last.status,
          reason: last.reason,
          count: last.count + t.count,
        );
      } else {
        out.add(t);
      }
    }
    return List.unmodifiable(out);
  }

  Message copyWith({
    String? text,
    MessageStatus? status,
    ResearchFailureKind? errorKind,
    List<TraceStep>? traces,
    List<Citation>? citations,
    List<ProposalView>? proposals,
    List<ReadPermissionView>? permissions,
    String? noteId,
    bool? online,
    DateTime? endedAt,
    AssistantDiagnostics? diagnostics,
  }) => Message(
    id: id,
    requestId: requestId,
    role: role,
    text: text ?? this.text,
    status: status ?? this.status,
    errorKind: errorKind ?? this.errorKind,
    contexts: contexts,
    traces: traces ?? this.traces,
    citations: citations ?? this.citations,
    proposals: proposals ?? this.proposals,
    permissions: permissions ?? this.permissions,
    skill: skill,
    taskModel: taskModel,
    summaryMessageIds: summaryMessageIds,
    noteId: noteId ?? this.noteId,
    online: online ?? this.online,
    startedAt: startedAt,
    endedAt: endedAt ?? this.endedAt,
    diagnostics: diagnostics ?? this.diagnostics,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'requestId': requestId,
    'role': role.name,
    'text': text,
    'status': status.name,
    'errorKind': errorKind?.name,
    'contexts': contexts.map((c) => c.toJson()).toList(),
    'traces': traces.map((t) => t.toJson()).toList(),
    'citations': citations.map((c) => c.toJson()).toList(),
    'proposals': proposals.map((p) => p.toJson()).toList(),
    'permissions': permissions.map((p) => p.toJson()).toList(),
    'skill': skill,
    'taskModel': taskModel?.toJson(),
    'summaryMessageIds': summaryMessageIds,
    'noteId': noteId,
    'online': online,
    'diagnostics': diagnostics?.toJson(),
    'startedAt': startedAt?.toIso8601String(),
    'endedAt': endedAt?.toIso8601String(),
  };
  factory Message.fromJson(Map<String, dynamic> j) => Message(
    id: j['id'],
    requestId: j['requestId'],
    role: MessageRole.values.byName(j['role']),
    text: j['text'],
    status: MessageStatus.values.byName(j['status']),
    errorKind: j['errorKind'] == null ? null : ResearchFailureKind.values.byName(j['errorKind']),
    contexts: [for (final v in j['contexts']) ContextItem.fromJson(Map<String, dynamic>.from(v))],
    traces: [for (final v in j['traces']) TraceStep.fromJson(Map<String, dynamic>.from(v))],
    citations: [for (final v in j['citations']) Citation.fromJson(Map<String, dynamic>.from(v))],
    proposals: [for (final v in j['proposals']) ProposalView.fromJson(Map<String, dynamic>.from(v))],
    permissions: [
      for (final v in j['permissions'] as List? ?? []) ReadPermissionView.fromJson(Map<String, dynamic>.from(v)),
    ],
    skill: j['skill'],
    taskModel: j['taskModel'] == null ? null : ModelReference.fromJson(Map<String, dynamic>.from(j['taskModel'])),
    summaryMessageIds: j['summaryMessageIds'] == null ? null : List<String>.from(j['summaryMessageIds']),
    noteId: j['noteId'],
    online: j['online'] ?? false,
    diagnostics: j['diagnostics'] == null
        ? null
        : AssistantDiagnostics.fromJson(Map<String, dynamic>.from(j['diagnostics'])),
    startedAt: DateTime.tryParse(j['startedAt'] ?? ''),
    endedAt: DateTime.tryParse(j['endedAt'] ?? ''),
  );
}

class Conversation {
  Conversation({
    required this.id,
    required this.studySetId,
    required this.model,
    this.title = '',
    List<Message> messages = const [],
    this.online = true,
    this.readOnly = false,
    this.archiveFields = const {
      'taskRouting': {'version': 1, 'assistantChat': null},
    },
  }) : messages = List.unmodifiable(messages);
  final String id, studySetId, title;
  final AssistantModel model;
  final List<Message> messages;
  final bool online;
  final bool readOnly;
  final Map<String, dynamic> archiveFields;
  bool get running => messages.any((m) => m.status == MessageStatus.running);
  Conversation copyWith({
    String? title,
    List<Message>? messages,
    AssistantModel? model,
    bool? online,
    Map<String, dynamic>? archiveFields,
  }) => Conversation(
    id: id,
    studySetId: studySetId,
    title: title ?? this.title,
    messages: messages ?? this.messages,
    model: model ?? this.model,
    online: online ?? this.online,
    readOnly: readOnly,
    archiveFields: archiveFields ?? this.archiveFields,
  );
  Map<String, dynamic> toJson() => {
    ...archiveFields,
    'id': id,
    'studySetId': studySetId,
    'title': title,
    'model': model.toJson(),
    'messages': messages.map((m) => m.toJson()).toList(),
    'online': online,
    'readOnly': readOnly,
  };
  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
    id: j['id'],
    studySetId: j['studySetId'],
    title: j['title'],
    model: AssistantModel.fromJson(Map<String, dynamic>.from(j['model'])),
    messages: [for (final m in j['messages']) Message.fromJson(Map<String, dynamic>.from(m))],
    online: j['online'],
    readOnly: j['readOnly'] ?? false,
    archiveFields: migrateConversationRouting(j),
  );
}
