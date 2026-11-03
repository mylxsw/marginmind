import 'package:mm_core/mm_core.dart';

import 'commit.dart';
import 'reconciliation.dart';

String readingDocumentVersion(Document doc) =>
    syncDigest([doc.id, doc.revision, doc.fileName, doc.contentManifest, doc.layout.name, doc.pageCount]);

String localReadingToken(Document doc) => syncDigest([
  readingDocumentVersion(doc),
  doc.lastPage,
  doc.lastReadAt?.toUtc().toIso8601String(),
  doc.readingPosition?.toJson(),
]);

class DeviceReading {
  DeviceReading(Iterable<DeviceReadingLocation> locations) : locations = List.unmodifiable(locations);
  final List<DeviceReadingLocation> locations;

  factory DeviceReading.fromContent(StudySetContent content) => DeviceReading([
    for (final doc in content.documents)
      if (doc.lastReadAt != null &&
          (doc.contentManifest == null
              ? doc.lastPage > 0 && doc.lastPage <= doc.pageCount
              : doc.readingPosition is TextReadingPosition &&
                    (doc.readingPosition! as TextReadingPosition).revision == doc.revision))
        DeviceReadingLocation(
          doc.id,
          readingDocumentVersion(doc),
          doc.lastReadAt!.toUtc(),
          doc.contentManifest == null
              ? PdfPosition(
                  doc.lastPage,
                  y: doc.readingPosition is PdfPosition && (doc.readingPosition! as PdfPosition).page == doc.lastPage
                      ? (doc.readingPosition! as PdfPosition).y
                      : null,
                )
              : doc.readingPosition!,
        ),
  ]);

  Map<String, Object?> toJson() => {
    'kind': 'device-reading',
    'version': 1,
    'documents': [for (final location in locations) location.toJson()],
  };

  factory DeviceReading.fromJson(Map<String, Object?> value) {
    if (value.length != 3 ||
        value['kind'] != 'device-reading' ||
        value['version'] != 1 ||
        value['documents'] is! List) {
      throw const FormatException('Unsupported device reading');
    }
    try {
      final seen = <String>{};
      final result = DeviceReading(
        (value['documents'] as List).map((v) {
          final j = (v as Map).cast<String, Object?>();
          if (j.length != 4 ||
              j['id'] is! String ||
              (j['id'] as String).isEmpty ||
              j['documentVersion'] is! String ||
              !RegExp(r'^[0-9a-f]{64}$').hasMatch(j['documentVersion'] as String) ||
              !seen.add(j['id'] as String)) {
            throw const FormatException('Invalid reading document');
          }
          final time = DateTime.parse(j['readAt'] as String);
          if (!time.isUtc) throw const FormatException('Reading time must include timezone');
          final position = ReadingPosition.fromJson((j['position'] as Map).cast());
          if (!contentValueEquals(position.toJson(), j['position'])) {
            throw const FormatException('Invalid reading position');
          }
          return DeviceReadingLocation(j['id'] as String, j['documentVersion'] as String, time, position);
        }),
      );
      return result;
    } on TypeError {
      throw const FormatException('Invalid device reading');
    } on ArgumentError {
      throw const FormatException('Invalid device reading');
    }
  }
}

class DeviceReadingLocation {
  const DeviceReadingLocation(this.documentId, this.documentVersion, this.readAt, this.position);
  final String documentId, documentVersion;
  final DateTime readAt;
  final ReadingPosition position;
  Map<String, Object?> toJson() => {
    'id': documentId,
    'documentVersion': documentVersion,
    'readAt': readAt.toUtc().toIso8601String(),
    'position': position.toJson(),
  };
  bool matches(Document doc) =>
      documentId == doc.id &&
      documentVersion == readingDocumentVersion(doc) &&
      switch (position) {
        PdfPosition(:final page) => doc.contentManifest == null && page <= doc.pageCount,
        TextReadingPosition(:final revision) => doc.contentManifest != null && revision == doc.revision,
      };
}

/// One writer per device scope. Time is presentation data, never a winner rule.
/// Old candidate snapshots can remain ancestors, but are not offered directly.
SyncMergePlan planDeviceReading(Map<String, SyncCommit> known, {required String remote, String? local}) {
  SyncMergePlan problem(String reason, [SyncMergeState state = SyncMergeState.conflict]) =>
      SyncMergePlan(remote: remote, local: local, state: state, reason: reason);
  final plan = planSyncMerge(known, remote: remote, local: local);
  if (plan.state != SyncMergeState.ready && plan.state != SyncMergeState.unchanged) return plan;
  if (plan.state == SyncMergeState.ready && !plan.adopt) return problem('invalidReading');
  final ancestry = syncAncestry(known, [remote, ?local]);
  final tip = known[remote]!, parts = tip.scope.split('/');
  if (parts.length != 3 || parts[0] != 'reading' || parts[1].isEmpty || parts[2].isEmpty) {
    return problem('invalidReading');
  }
  final contentScope = 'sets/${parts[1]}';
  try {
    for (final c in ancestry.values) {
      if (c.deviceId != parts[2] || c.parents.length > 1 || c.pending.isNotEmpty || c.resolves.isNotEmpty) {
        return problem('invalidReading');
      }
      if (c.deleted) continue;
      if (c.payload['kind'] != 'device-reading') {
        if (c.id == remote) return problem('unsupportedReading');
        continue; // Preserve pre-protocol local history without rewriting IDs.
      }
      final reading = DeviceReading.fromJson(c.payload);
      if (c.requires.length != 1 || !c.requires.containsKey(contentScope)) return problem('invalidReading');
      final source = known[c.requires[contentScope]];
      if (source == null) return problem('missingContent', SyncMergeState.waiting);
      if (source.scope != contentScope || source.libraryId != c.libraryId || source.deleted) {
        return problem('invalidReading');
      }
      final content = contentFromDocument((source.payload['content'] as Map).cast());
      if (reading.locations.any(
        (l) => content.document(l.documentId) == null || !l.matches(content.document(l.documentId)!),
      )) {
        return problem('invalidReading');
      }
    }
  } on FormatException {
    return problem('invalidReading');
  } on ArgumentError {
    return problem('invalidReading');
  } on TypeError {
    return problem('invalidReading');
  }
  return plan;
}
