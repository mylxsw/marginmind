import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:mm_design/mm_design.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_book/mm_book.dart' as book;
import 'package:mm_core/mm_core.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:mm_pdf/mm_pdf.dart';

final documentImporterProvider = Provider<DocumentImporter>((ref) => const DocumentImporter());

/// Parses before writing. The repository commits the complete immutable version
/// and its metadata together, preserving concurrent edits and prior revisions.
class DocumentImporter {
  const DocumentImporter();
  Future<DocumentPackage> prepare(
    MMDocumentFile file, {
    required String id,
    required DateTime now,
    book.BookCancellationToken? cancellation,
  }) async {
    cancellation?.check();
    final format = DocumentFormat.fromFileName(file.name);
    if (format == DocumentFormat.unknown) {
      throw const book.BookParseException(book.BookErrorKind.unsupported, 'Unsupported document');
    }
    // Image-heavy Kindle books can exceed 64 MiB even with very little text.
    // Keep the file reader and parser on the same bounded import budget.
    final maxBytes = switch (format) {
      DocumentFormat.pdf || DocumentFormat.mobi || DocumentFormat.azw3 => 256 * 1024 * 1024,
      _ => 64 * 1024 * 1024,
    };
    final bytes = await MMDocumentFiles.read(file.path, maxBytes: maxBytes);
    cancellation?.check();
    final ext = file.name.split('.').last.toLowerCase();
    final original = 'documents/${sha256.convert(bytes)}.$ext';
    if (format == DocumentFormat.pdf) {
      final info = await MMPdfEngine.inspect(file.path);
      cancellation?.check();
      return DocumentPackage(
        document: Document(
          id: id,
          title: file.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
          fileName: original,
          sourceFileName: original,
          pageCount: info.pageCount,
          importedAt: now,
        ),
        files: {original: bytes},
      );
    }
    final parsed = await book.BookParser(maxBytes: maxBytes).parse(
      book.SourceBytes(file.name, bytes),
      cancellation: cancellation,
      resolver: (path) => MMDocumentFiles.readRelativeResource(file.path, path),
    );
    cancellation?.check();
    if (parsed.chapters.isEmpty || parsed.chapters.every((c) => c.canonicalText.trim().isEmpty)) {
      throw const FormatException('No readable content');
    }
    final revision = parsed.revision;
    final base = 'books/$id/$revision';
    final files = <String, List<int>>{original: bytes};
    final json = parsed.toJson();
    final spine = <Map<String, Object?>>[];
    for (final chapter in json['spine'] as List) {
      final encoded = utf8.encode(jsonEncode(chapter));
      final hash = sha256.convert(encoded).toString();
      final path = '$base/chapters/$hash.json';
      files[path] = encoded;
      spine.add({'id': (chapter as Map)['id'], 'path': path, 'sha256': hash});
    }
    final resources = <Map<String, Object?>>[];
    for (final resource in json['resources'] as List) {
      final entry = (resource as Map).cast<String, Object?>();
      final source = entry['path'] as String;
      final hash = entry['sha256'] as String;
      final extension = source.split('.').last.toLowerCase();
      final safeExtension = RegExp(r'^[a-z0-9]{1,8}$').hasMatch(extension) ? extension : 'bin';
      final path = '$base/resources/$hash.$safeExtension';
      files[path] = parsed.resources[source]!;
      resources.add({...entry, 'sourcePath': source, 'path': path});
    }
    final manifest = '$base/manifest.json';
    files[manifest] = utf8.encode(jsonEncode({...json, 'spine': spine, 'resources': resources}));
    return DocumentPackage(
      document: Document(
        id: id,
        title: parsed.title.isEmpty ? file.name.replaceFirst(RegExp(r'\.[^.]+$'), '') : parsed.title,
        fileName: manifest,
        sourceFileName: original,
        contentManifest: manifest,
        revision: revision,
        readingPosition: TextReadingPosition(revision: revision, chapterId: parsed.chapters.first.id, offset: 0),
        features: DocumentContentFeatures(
          text: parsed.chapters.any((c) => c.canonicalText.replaceAll('￼', '').trim().isNotEmpty),
          outline: parsed.toc.isNotEmpty,
        ),
        format: format,
        layout: parsed.fixedLayout ? DocumentLayout.fixed : DocumentLayout.reflow,
        pageCount: parsed.fixedLayout ? parsed.chapters.length : 0,
        importedAt: now,
      ),
      files: files,
    );
  }
}

class DocumentImportTask {
  DocumentImportTask(this.id, this.name);
  final String id, name;
  final cancellation = book.BookCancellationToken();
  bool cancelled = false;
  void cancel() {
    cancelled = true;
    cancellation.cancel();
  }
}

final documentImportsProvider = NotifierProvider.family<DocumentImports, List<DocumentImportTask>, String>(
  DocumentImports.new,
);

class DocumentImports extends Notifier<List<DocumentImportTask>> {
  DocumentImports(this.studySetId);
  final String studySetId;
  final _tasks = <DocumentImportTask>[];
  @override
  List<DocumentImportTask> build() {
    ref.onDispose(() {
      for (final task in _tasks) {
        task.cancel();
      }
    });
    return const [];
  }

  DocumentImportTask add(String name) {
    final task = DocumentImportTask(newId(), name);
    _tasks.add(task);
    state = List.unmodifiable(_tasks);
    return task;
  }

  void remove(DocumentImportTask task) {
    _tasks.remove(task);
    state = List.unmodifiable(_tasks);
  }

  void cancel(String id) {
    for (final task in _tasks.where((t) => t.id == id)) {
      task.cancel();
    }
  }
}

enum DocumentImportError { drm, damaged, unsupported, kfx, empty, limitExceeded, unavailable }

DocumentImportError documentImportError(Object error) {
  if (error is book.BookParseException) {
    if (error.message == 'Empty EPUB spine') return DocumentImportError.empty;
    return switch (error.kind) {
      book.BookErrorKind.drm => DocumentImportError.drm,
      book.BookErrorKind.unsupported =>
        error.message.contains('KFX') ? DocumentImportError.kfx : DocumentImportError.unsupported,
      book.BookErrorKind.limitExceeded => DocumentImportError.limitExceeded,
      _ => DocumentImportError.damaged,
    };
  }
  if (error is FormatException) {
    if (error.message == 'Document exceeds import limit') return DocumentImportError.limitExceeded;
    return error.message == 'No readable content' ? DocumentImportError.empty : DocumentImportError.damaged;
  }
  return DocumentImportError.unavailable;
}

final importedDocumentsProvider = NotifierProvider.autoDispose.family<ImportedDocuments, Set<String>, String>(
  ImportedDocuments.new,
);

class ImportedDocuments extends Notifier<Set<String>> {
  ImportedDocuments(this.setId);
  final String setId;
  final _timers = <String, Timer>{};
  @override
  Set<String> build() {
    ref.onDispose(() {
      for (final t in _timers.values) {
        t.cancel();
      }
    });
    return const {};
  }

  void flash(String id) {
    _timers.remove(id)?.cancel();
    state = {...state, id};
    _timers[id] = Timer(MMMotion.flash, () {
      _timers.remove(id);
      if (ref.mounted) state = {...state}..remove(id);
    });
  }
}
