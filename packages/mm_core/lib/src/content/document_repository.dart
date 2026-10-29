import 'dart:typed_data';

import 'models.dart';
import 'study_set_content.dart';

/// One immutable version, fully prepared before any references are published.
/// Keys use the package layout (documents/, books/, web/), on every platform.
class DocumentPackage {
  DocumentPackage({
    required this.document,
    required Map<String, List<int>> files,
    this.reconcile,
    this.expectedRevision,
    this.expectedSnapshotFile,
  }) : files = Map.unmodifiable(
         files.map((key, bytes) => MapEntry(key, Uint8List.fromList(bytes).asUnmodifiableView())),
       ) {
    if (files.isEmpty || files.values.fold<int>(0, (sum, b) => sum + b.length) > 256 * 1024 * 1024) {
      throw ArgumentError('Invalid document package size');
    }
    for (final key in files.keys) {
      validateDocumentPath(key);
    }
    for (final key in [
      document.fileName,
      document.sourceFileName,
      document.contentManifest,
      document.origin?.snapshotFile,
    ]) {
      if (key != null && !files.containsKey(key)) throw ArgumentError('Missing document resource: $key');
    }
  }
  final Document document;
  final Map<String, List<int>> files;

  /// Runs inside the repository write queue, against the latest content.
  /// Throwing aborts the complete version, including its resources.
  final StudySetContent Function(StudySetContent)? reconcile;

  /// Optimistic version guard for recapture, checked before any writes.
  final String? expectedRevision;

  /// Distinguishes repeated captures whose canonical content is identical.
  final String? expectedSnapshotFile;
}

void validateDocumentPath(String path) {
  if (!RegExp(r'^(documents|books|web)/[a-zA-Z0-9_./-]+$').hasMatch(path) ||
      path.split('/').any((p) => p.isEmpty || p == '.' || p == '..') ||
      path.endsWith('.tmp')) {
    throw ArgumentError.value(path, 'documentPath');
  }
}

abstract interface class DocumentRepository {
  /// Commits resources first, then publishes the document in the latest content.
  /// Failed/cancelled imports publish nothing; existing immutable files survive.
  Future<StudySetContent> importDocumentPackage(
    String studySetId,
    DocumentPackage package, {
    bool Function()? cancelled,
  });
  Future<List<int>> readDocumentFile(String studySetId, String fileName);
}
