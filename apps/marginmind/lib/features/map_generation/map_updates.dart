import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';

import '../../app/providers.dart';
import '../workspace/reader_ocr.dart';
import '../workspace/workspace_controller.dart';
import 'map_generation_controller.dart';

/// Header and sidebar share asynchronous fingerprints, invalidated by material
/// changes and OCR completion. Map-only edits do not reread document text.
final currentMapSourceProvider = FutureProvider.autoDispose.family<MapSource?, (String, String)>((ref, key) async {
  final (studySetId, documentId) = key;
  ref.watch(
    contentProvider(studySetId).select((value) {
      final c = value.value;
      return c == null
          ? null
          : mapContentHash({
              'document': (c.document(documentId)?.toJson())?..remove('lastReadAt'),
              'annotations': [
                for (final a in c.annotations)
                  if (a.documentId == documentId) a.toJson(),
              ],
              'notes': [
                for (final n in c.marginNotes)
                  if (n.documentId == documentId) n.toJson(),
              ],
              'attachments': [for (final a in c.noteAttachments) a.toJson()],
              'researchNotes': [for (final n in c.researchNotes) n.toJson()],
              'outlines': c.outlineOn(documentId)?.toJson(),
            });
    }),
  );
  final content = ref.read(contentProvider(studySetId)).value;
  final document = content?.document(documentId);
  if (content == null || document == null) return null;
  final workspace = ref.read(workspaceProvider(studySetId).notifier);
  ref.watch(readerOcrProvider(workspace.filePath(document)).select((s) => s.revision));
  final cancellation = CancellationToken();
  ref.onDispose(cancellation.cancel);
  final digest = await ref
      .read(documentDigestBuilderProvider(studySetId))
      .build(
        content,
        studySetId: studySetId,
        documentId: documentId,
        mapId: 'fingerprint',
        draftPrefix: 'fingerprint-',
        cancellation: cancellation,
      );
  return digest.source;
});

final mapHasUpdatesProvider = Provider.autoDispose.family<bool, (String, String)>((ref, key) {
  final (studySetId, mapId) = key;
  final content = ref.watch(contentProvider(studySetId)).value;
  final generation = content?.map(mapId)?.generation;
  if (generation == null) return false;
  for (final old in generation.sources) {
    if (content!.document(old.documentId) == null) return true;
    final current = ref.watch(currentMapSourceProvider((studySetId, old.documentId)));
    if (!current.hasValue) continue;
    final source = current.value;
    // Revisiting an earlier page does not introduce new material.
    if (source == null || source.fingerprint != old.fingerprint || source.readThrough > old.readThrough) return true;
  }
  return false;
});
