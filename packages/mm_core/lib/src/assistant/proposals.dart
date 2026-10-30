import '../content/research.dart';

/// Model fields are deliberately closed: no delete, raw document edits or map IDs.
enum MapEditKind { addTopic, addNote, addReviewCard, move, rename }

class MapEditOperation {
  const MapEditOperation({
    required this.id,
    required this.kind,
    this.nodeId,
    this.parentId,
    this.title,
    this.body,
    this.question,
    this.answer,
  });
  final String id;
  final MapEditKind kind;
  final String? nodeId, parentId, title, body, question, answer;
  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    if (nodeId != null) 'nodeId': nodeId,
    if (parentId != null) 'parentId': parentId,
    if (title != null) 'title': title,
    if (body != null) 'body': body,
    if (question != null) 'question': question,
    if (answer != null) 'answer': answer,
  };
  factory MapEditOperation.fromJson(Map<String, dynamic> j) {
    const keys = {'id', 'kind', 'nodeId', 'parentId', 'title', 'body', 'question', 'answer'};
    if (j.keys.any((k) => !keys.contains(k))) throw const FormatException('Unknown operation field');
    String? value(String key) {
      final v = j[key];
      if (v == null) return null;
      if (v is! String || v.trim().isEmpty || v.length > 12000) throw const FormatException('Invalid operation value');
      return v;
    }

    final op = MapEditOperation(
      id: value('id') ?? (throw const FormatException('Missing id')),
      kind: MapEditKind.values.byName(value('kind') ?? ''),
      nodeId: value('nodeId'),
      parentId: value('parentId'),
      title: value('title'),
      body: value('body'),
      question: value('question'),
      answer: value('answer'),
    );
    final requiredFields = switch (op.kind) {
      MapEditKind.addTopic => [op.parentId, op.title],
      MapEditKind.addNote => [op.parentId, op.title, op.body],
      MapEditKind.addReviewCard => [op.parentId, op.question, op.answer],
      MapEditKind.move => [op.nodeId, op.parentId],
      MapEditKind.rename => [op.nodeId, op.title],
    };
    final allowed = switch (op.kind) {
      MapEditKind.addTopic => {'id', 'kind', 'parentId', 'title'},
      MapEditKind.addNote => {'id', 'kind', 'parentId', 'title', 'body'},
      MapEditKind.addReviewCard => {'id', 'kind', 'parentId', 'question', 'answer'},
      MapEditKind.move => {'id', 'kind', 'nodeId', 'parentId'},
      MapEditKind.rename => {'id', 'kind', 'nodeId', 'title'},
    };
    if (j.keys.any((k) => !allowed.contains(k))) throw const FormatException('Field not allowed for operation');
    if (requiredFields.contains(null)) throw const FormatException('Missing operation field');
    return op;
  }
}

class MapEditProposal {
  MapEditProposal({
    required this.id,
    required this.studySetId,
    required this.mapId,
    required this.baseRevision,
    required List<MapEditOperation> operations,
  }) : isExpansion = false,
       operations = List.unmodifiable(operations);

  /// Host-only capability. JSON decoding deliberately cannot grant this exemption.
  MapEditProposal.expansion({
    required this.id,
    required this.studySetId,
    required this.mapId,
    required this.baseRevision,
    required List<MapEditOperation> operations,
  }) : isExpansion = true,
       operations = List.unmodifiable(operations);
  final bool isExpansion;
  final String id, studySetId, mapId;
  final int baseRevision;
  final List<MapEditOperation> operations;
  Map<String, Object?> toJson() => {
    'id': id,
    'studySetId': studySetId,
    'mapId': mapId,
    'baseRevision': baseRevision,
    'operations': [for (final op in operations) op.toJson()],
  };
  factory MapEditProposal.fromJson(Map<String, dynamic> j) => MapEditProposal(
    id: j['id'],
    studySetId: j['studySetId'],
    mapId: j['mapId'],
    baseRevision: j['baseRevision'],
    operations: [for (final o in j['operations']) MapEditOperation.fromJson(Map<String, dynamic>.from(o))],
  );
}

class MapEditReceipt {
  MapEditReceipt({
    required this.proposalId,
    required this.revision,
    required this.undoHandle,
    required List<String> operationIds,
    required List<String> nodeIds,
    Map<String, String> skipped = const {},
  }) : skipped = Map.unmodifiable(skipped),
       operationIds = List.unmodifiable(operationIds),
       nodeIds = List.unmodifiable(nodeIds);
  final Map<String, String> skipped;
  final String proposalId, undoHandle;
  final int revision;
  final List<String> operationIds, nodeIds;
  Map<String, Object?> toJson() => {
    'skipped': skipped,
    'proposalId': proposalId,
    'revision': revision,
    'undoHandle': undoHandle,
    'operationIds': operationIds,
    'nodeIds': nodeIds,
  };
  factory MapEditReceipt.fromJson(Map<String, dynamic> j) => MapEditReceipt(
    skipped: Map<String, String>.from(j['skipped'] ?? {}),
    proposalId: j['proposalId'],
    revision: j['revision'],
    undoHandle: j['undoHandle'],
    operationIds: List<String>.from(j['operationIds']),
    nodeIds: List<String>.from(j['nodeIds']),
  );
}

abstract interface class MapEditExecutor {
  /// Must check graph membership/cycles, all fields, revision and dependencies
  /// again inside ONE undo transaction. Receipt is committed in that transaction.
  Future<MapEditReceipt> apply(MapEditProposal proposal, Set<String> selectedIds);
  Future<MapEditReceipt?> receipt(String proposalId);
}

class SaveNoteRequest {
  const SaveNoteRequest({required this.title, this.mapId, this.parentId, this.anchor});
  final String title;
  final String? mapId, parentId;
  final SourceAnchor? anchor;
}

abstract interface class NoteSaver {
  Future<String> save({
    required String conversationId,
    required String messageId,
    required String body,
    required SaveNoteRequest request,
  });
}
