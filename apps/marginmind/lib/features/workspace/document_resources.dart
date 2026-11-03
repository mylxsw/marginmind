import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';

import '../../app/providers.dart';

// Resource-version fields only: turning a page must not hash the whole PDF.
typedef DocumentResourceKey = (String, String, String?, String, String?, String?);
DocumentResourceKey documentResourceKey(String studySetId, Document document) => (
  studySetId,
  document.id,
  document.revision,
  document.fileName,
  document.contentManifest,
  document.origin?.snapshotFile,
);

class DocumentResourcesUnavailable implements Exception {
  const DocumentResourcesUnavailable(this.availability);
  final DocumentResourceAvailability availability;
}

final documentResourcesProvider = StreamProvider.autoDispose.family<DocumentResourceAvailability, DocumentResourceKey>((
  ref,
  key,
) {
  final repo = ref.watch(contentRepositoryProvider);
  return repo is DocumentResourceRepository
      ? (repo as DocumentResourceRepository).watchDocumentResources(key.$1, key.$2)
      : Stream.value(DocumentResourceAvailability.ready);
});
