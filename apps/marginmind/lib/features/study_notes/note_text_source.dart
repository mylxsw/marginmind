import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../app/providers.dart';
import '../workspace/reflow_document.dart';
import '../workspace/workspace_controller.dart';

/// Load only documents in scope. Failed/unavailable text leaves verbatim quotes intact.
Future<NoteTextSource> loadNoteTextSource(WidgetRef ref, String setId, StudySetContent content, NoteScope scope) async {
  final materials = const NoteMaterialCollector().collect(
    content,
    scope,
    NoteSettings(depth: NoteDepth.none),
    now: DateTime.now(),
  );
  final chapters = <String, Map<String, String>>{}, pages = <String, Map<int, String>>{};
  final repository = ref.read(contentRepositoryProvider);
  final controller = ref.read(workspaceProvider(setId).notifier);
  for (final id in materials.highlights.map((m) => m.documentId).whereType<String>().toSet()) {
    final document = content.document(id);
    if (document == null) continue;
    try {
      if (document.contentManifest != null && repository is DocumentRepository) {
        final book = await ReflowDocument.load(repository as DocumentRepository, setId, document);
        chapters[id] = {for (final chapter in book.chapters) chapter.id: chapter.canonicalText};
      } else if (document.format == DocumentFormat.pdf) {
        if (!await MMNoteFiles.exists(controller.filePath(document))) continue;
        final needed = materials.highlights
            .where((m) => m.documentId == id)
            .map((m) => content.annotation(m.sourceId)!)
            .where((a) => !a.isText)
            .map((a) => a.page)
            .toSet();
        pages[id] = {};
        final surrounding = {
          for (final page in needed) ...[page - 1, page, page + 1],
        }.where((page) => page > 0 && page <= document.pageCount);
        for (final page in surrounding) {
          final text = await MMPdfEngine.pageText(controller.filePath(document), page);
          if (text != null) pages[id]![page] = text;
        }
      }
    } catch (_) {
      /* Source can be unavailable; the note still works. */
    }
  }
  return NoteTextSource(chapters: chapters, pages: pages);
}
