import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mm_book/mm_book.dart' as book;
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import 'reflow_document.dart';

/// A finished copy, ready for the save panel or share sheet.
typedef DocumentExportFile = ({String name, Uint8List bytes});

/// File-name suffixes and fixed text written into a copy.
class DocumentExportLabels {
  const DocumentExportLabels({required this.markedSuffix, required this.cleanSuffix, required this.notesHeading});
  final String markedSuffix, cleanSuffix, notesHeading;
}

/// Turns a study set's document and export options into a file. The stored
/// document is only ever read; all marks come from [DocumentExportPlan].
class DocumentExporter {
  const DocumentExporter({
    required this.repository,
    required this.studySetId,
    required this.content,
    required this.document,
    required this.labels,
  });

  final DocumentRepository repository;
  final String studySetId;
  final StudySetContent content;
  final Document document;
  final DocumentExportLabels labels;

  DocumentExportPlan plan(DocumentExportOptions options) => DocumentExportPlan.build(content, document, options);

  /// Whether this document may carry marks: its format, the platform and, for a
  /// PDF, the permissions set by its author all have to allow it.
  Future<bool> canWriteMarks() async {
    if (!document.exportsMarks) return false;
    if (!document.exportsAsPdf) return true;
    if (!MMPdfExport.canWriteMarks) return false;
    return MMPdfExport.allowsMarks(await _read(document.fileName));
  }

  Future<DocumentExportFile> write(
    DocumentExportOptions options, {
    void Function(double progress)? onProgress,
    bool Function()? cancelled,
  }) async {
    final plan = this.plan(options);
    final Uint8List bytes;
    final String extension;
    if (plan.isUnchangedOriginal) {
      bytes = await _read(document.originalExportFile!);
      extension = document.cleanExportExtension;
    } else if (document.exportsAsPdf) {
      bytes = await MMPdfExport.write(
        await _read(document.fileName),
        plan,
        const MMPdfExportColors(mark: _annotationRgb, note: _annotationRgb, ink: _inkRgb),
        onProgress: onProgress,
        cancelled: cancelled,
      );
      extension = 'pdf';
    } else if (plan.isEmpty) {
      // A web capture has no source file: its clean copy is built like a marked one.
      bytes = await _epub(plan, await _reflow());
      extension = 'epub';
    } else if (document.markedExportTarget == DocumentExportTarget.markdown) {
      bytes = await _markdown(plan);
      extension = 'md';
    } else {
      bytes = await _epub(plan, await _reflow());
      extension = 'epub';
    }
    return (
      name: documentExportFileName(
        document.title,
        extension,
        suffix: plan.isEmpty ? labels.cleanSuffix : labels.markedSuffix,
      ),
      bytes: bytes,
    );
  }

  Future<Uint8List> _read(String file) async => Uint8List.fromList(await repository.readDocumentFile(studySetId, file));

  Future<ReflowDocument> _reflow() => ReflowDocument.load(repository, studySetId, document);

  List<book.BookExportMark> _marks(DocumentExportPlan plan) => [
    for (final a in plan.annotations)
      for (final anchor in a.textAnchors)
        book.BookExportMark(anchor, rgb: _annotationRgb(a.colorIndex), underline: a.kind == AnnotationKind.underline),
  ];

  List<book.BookExportNote> _notes(DocumentExportPlan plan) => [
    for (final n in plan.notes) book.BookExportNote(n.anchor!.textAnchors.last, n.text),
  ];

  Future<Uint8List> _epub(DocumentExportPlan plan, ReflowDocument reflow) async {
    final resources = <String, ({Uint8List bytes, String mime})>{};
    final referenced = {
      for (final chapter in reflow.chapters)
        for (final block in chapter.blocks) ...[
          ...block.runs.map((r) => r.resource),
          for (final row in block.rows)
            for (final cell in row) ...cell.runs.map((r) => r.resource),
        ],
    };
    for (final source in referenced.nonNulls) {
      final mime = reflow.resources[source]?['mime'];
      // Missing images are left out rather than failing the whole export.
      if (mime is! String || !mime.startsWith('image/')) continue;
      resources[source] = (bytes: await reflow.resource(source), mime: mime);
    }
    final writer = book.BookEpubWriter(
      title: document.title,
      identifier: 'urn:foliarc:${document.id}',
      chapters: reflow.chapters,
      toc: reflow.toc,
      resources: resources,
      marks: _marks(plan),
      notes: _notes(plan),
    );
    return compute(_writeEpub, writer);
  }

  Future<Uint8List> _markdown(DocumentExportPlan plan) async {
    final source = document.originalExportFile;
    if (source == null) throw StateError('Markdown document without a source file');
    final reflow = await _reflow();
    final text = utf8.decode(await _read(source), allowMalformed: true);
    final annotator = book.BookMarkdownAnnotator(text, canonicalLength: reflow.length);
    return Uint8List.fromList(
      utf8.encode(annotator.write(marks: _marks(plan), notes: _notes(plan), unplacedHeading: labels.notesHeading)),
    );
  }
}

Uint8List _writeEpub(book.BookEpubWriter writer) => writer.write();

int _rgb(int argb) => argb & 0xFFFFFF;
int _annotationRgb(int colorIndex) => _rgb(MMAnnotationColor.fromIndex(colorIndex).color.toARGB32());
int _inkRgb(int colorIndex) => _rgb(MMInkColor.fromIndex(colorIndex).color.toARGB32());
