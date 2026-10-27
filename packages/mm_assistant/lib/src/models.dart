import 'package:mm_core/mm_core.dart';

import 'citations.dart';
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

ReadScope scopeFromContexts(String studySetId, List<ContextItem> contexts) {
  final pages = <String, Set<int>>{}, branches = <String, Set<String>>{};
  final docs = <String>{}, maps = <String>{}, selections = <String>{};
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

enum TraceStatus { running, done, error }

class TraceStep {
  const TraceStep(this.id, this.toolName, this.status);
  final String id, toolName;
  final TraceStatus status;
  Map<String, dynamic> toJson() => {'id': id, 'toolName': toolName, 'status': status.name};
  factory TraceStep.fromJson(Map<String, dynamic> j) =>
      TraceStep(j['id'], j['toolName'], TraceStatus.values.byName(j['status']));
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
    this.skill,
    this.noteId,
    this.online = false,
  }) : contexts = List.unmodifiable(contexts),
       traces = List.unmodifiable(traces),
       citations = List.unmodifiable(citations),
       proposals = List.unmodifiable(proposals);
  final String id, requestId, text;
  final MessageRole role;
  final MessageStatus status;
  final ResearchFailureKind? errorKind;
  final List<ContextItem> contexts;
  final List<TraceStep> traces;
  final List<Citation> citations;
  final List<ProposalView> proposals;
  final String? skill, noteId;
  final bool online;
  Message copyWith({
    String? text,
    MessageStatus? status,
    ResearchFailureKind? errorKind,
    List<TraceStep>? traces,
    List<Citation>? citations,
    List<ProposalView>? proposals,
    String? noteId,
    bool? online,
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
    skill: skill,
    noteId: noteId ?? this.noteId,
    online: online ?? this.online,
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
    'skill': skill,
    'noteId': noteId,
    'online': online,
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
    skill: j['skill'],
    noteId: j['noteId'],
    online: j['online'] ?? false,
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
  }) : messages = List.unmodifiable(messages);
  final String id, studySetId, title;
  final AssistantModel model;
  final List<Message> messages;
  final bool online;
  final bool readOnly;
  bool get running => messages.any((m) => m.status == MessageStatus.running);
  Conversation copyWith({String? title, List<Message>? messages, AssistantModel? model, bool? online}) => Conversation(
    id: id,
    studySetId: studySetId,
    title: title ?? this.title,
    messages: messages ?? this.messages,
    model: model ?? this.model,
    online: online ?? this.online,
    readOnly: readOnly,
  );
  Map<String, dynamic> toJson() => {
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
  );
}
