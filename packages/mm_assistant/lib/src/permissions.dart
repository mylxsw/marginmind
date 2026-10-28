import 'package:mm_core/mm_core.dart';

enum ReadPermissionKind { pages, selection, branch, map }

enum ReadPermissionStatus { pending, allowed, denied, cancelled }

/// A concrete read target, resolved by the host rather than described by the
/// model. Permission applies only to the current run and the displayed target.
class ReadPermissionRequest {
  const ReadPermissionRequest({
    this.id = '',
    required this.kind,
    required this.title,
    required this.targetId,
    this.documentId,
    this.mapId,
    this.from,
    this.to,
  });
  final String id, title, targetId;
  final ReadPermissionKind kind;
  final String? documentId, mapId;
  final int? from, to;
  String get key => '${kind.name}:$documentId:$mapId:$targetId:$from:$to';
  ReadPermissionRequest identified(String id) => ReadPermissionRequest(
    id: id,
    kind: kind,
    title: title,
    targetId: targetId,
    documentId: documentId,
    mapId: mapId,
    from: from,
    to: to,
  );

  ReadScope grant(ReadScope scope) => ReadScope(
    studySetId: scope.studySetId,
    documents: scope.documents,
    pages: {
      ...scope.pages,
      if (kind == ReadPermissionKind.pages)
        documentId!: {...?scope.pages[documentId], for (var p = from!; p <= to!; p++) p},
    },
    selections: {...scope.selections, if (kind == ReadPermissionKind.selection) targetId},
    maps: {...scope.maps, if (kind == ReadPermissionKind.map) mapId!},
    branches: {
      ...scope.branches,
      if (kind == ReadPermissionKind.branch) mapId!: {...?scope.branches[mapId], targetId},
    },
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'title': title,
    'targetId': targetId,
    'documentId': documentId,
    'mapId': mapId,
    'from': from,
    'to': to,
  };
  factory ReadPermissionRequest.fromJson(Map<String, dynamic> j) => ReadPermissionRequest(
    id: j['id'],
    kind: ReadPermissionKind.values.byName(j['kind']),
    title: j['title'],
    targetId: j['targetId'],
    documentId: j['documentId'],
    mapId: j['mapId'],
    from: j['from'],
    to: j['to'],
  );
}

class ReadPermissionView {
  const ReadPermissionView(this.request, {this.status = ReadPermissionStatus.pending});
  final ReadPermissionRequest request;
  final ReadPermissionStatus status;
  ReadPermissionView withStatus(ReadPermissionStatus status) => ReadPermissionView(request, status: status);
  Map<String, dynamic> toJson() => {'request': request.toJson(), 'status': status.name};
  factory ReadPermissionView.fromJson(Map<String, dynamic> j) => ReadPermissionView(
    ReadPermissionRequest.fromJson(Map<String, dynamic>.from(j['request'])),
    status: ReadPermissionStatus.values.byName(j['status']),
  );
}

/// Only real targets in the owning study set are eligible for a user decision.
/// Missing targets, invalid arguments and other study sets return null.
abstract interface class ReadPermissionResolver {
  ReadPermissionRequest? describeReadPermission(String tool, Map<String, dynamic> arguments);
}

class ReadPermissionDenied implements Exception {
  const ReadPermissionDenied();
}

class ReadPermissionRequired implements Exception {
  const ReadPermissionRequired();
}

class AssistantPermissions {
  AssistantPermissions(this.cancel);
  final CancellationToken cancel;
  Future<bool> Function(ReadPermissionRequest request)? onRequest;
  void Function(bool waiting)? onWaitingChanged;
  final _denied = <String>{};
  final _pending = <String, Future<bool>>{};
  int _sequence = 0, _waiting = 0;

  Future<bool> request(ReadPermissionRequest request) {
    cancel.check();
    if (_denied.contains(request.key)) return Future.value(false);
    if (onRequest == null) throw const ReadPermissionRequired();
    return _pending.putIfAbsent(
      request.key,
      () => _ask(request).whenComplete(() {
        _pending.remove(request.key);
      }),
    );
  }

  Future<bool> _ask(ReadPermissionRequest request) async {
    if (++_waiting == 1) onWaitingChanged?.call(true);
    try {
      final allowed = await cancel.bind(onRequest!(request.identified('read-permission-${_sequence++}')));
      cancel.check();
      if (!allowed) _denied.add(request.key);
      return allowed;
    } finally {
      if (--_waiting == 0) onWaitingChanged?.call(false);
    }
  }
}
