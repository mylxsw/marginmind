import 'package:meta/meta.dart';

import 'document_format.dart';
import 'models.dart';
import 'reading.dart';
import 'research.dart';
import 'study_set_content.dart';

/// The one-tap choices of the export sheet.
enum DocumentExportPreset { everything, marksOnly, clean }

/// The file a copy is written to. Reflowable books have no writer for their
/// own container (MOBI, web captures), so their marked copies become EPUB.
enum DocumentExportTarget { pdf, epub, markdown }

/// What a copy keeps. [pages] are 1-based PDF pages; null keeps them all.
@immutable
class DocumentExportOptions {
  const DocumentExportOptions({
    this.highlights = true,
    this.underlines = true,
    this.notes = true,
    this.ink = true,
    this.hiddenColors = const {},
    this.pages,
  });

  factory DocumentExportOptions.preset(DocumentExportPreset preset) => switch (preset) {
    DocumentExportPreset.everything => const DocumentExportOptions(),
    DocumentExportPreset.marksOnly => const DocumentExportOptions(notes: false, ink: false),
    DocumentExportPreset.clean => const DocumentExportOptions(
      highlights: false,
      underlines: false,
      notes: false,
      ink: false,
    ),
  };

  final bool highlights, underlines, notes, ink;

  /// Highlight colors, as stored on [Annotation.colorIndex], left out of the copy.
  final Set<int> hiddenColors;
  final Set<int>? pages;

  DocumentExportOptions copyWith({
    bool? highlights,
    bool? underlines,
    bool? notes,
    bool? ink,
    Set<int>? hiddenColors,
    Set<int>? Function()? pages,
  }) => DocumentExportOptions(
    highlights: highlights ?? this.highlights,
    underlines: underlines ?? this.underlines,
    notes: notes ?? this.notes,
    ink: ink ?? this.ink,
    hiddenColors: hiddenColors ?? this.hiddenColors,
    pages: pages == null ? this.pages : pages(),
  );
}

/// How the marks and format of a document translate into a copy.
extension DocumentExportFormat on Document {
  /// PDFs and web pages saved as PDF have no content manifest.
  bool get exportsAsPdf => contentManifest == null;

  /// Fixed-layout books hold page images and only leave as the original file.
  bool get exportsMarks => exportsAsPdf || layout == DocumentLayout.reflow;

  bool get exportsInk => exportsAsPdf;

  DocumentExportTarget get markedExportTarget {
    if (exportsAsPdf) return DocumentExportTarget.pdf;
    return format == DocumentFormat.markdown ? DocumentExportTarget.markdown : DocumentExportTarget.epub;
  }

  /// The stored source file of a clean copy; web captures have none.
  String? get originalExportFile => exportsAsPdf ? fileName : sourceFileName;

  String get markedExportExtension => switch (markedExportTarget) {
    DocumentExportTarget.pdf => 'pdf',
    DocumentExportTarget.epub => 'epub',
    DocumentExportTarget.markdown => 'md',
  };

  String get cleanExportExtension {
    final file = originalExportFile;
    return file == null ? 'epub' : file.split('.').last;
  }
}

/// Everything a document has that a copy could keep, regardless of options.
@immutable
class DocumentExportInventory {
  const DocumentExportInventory({
    required this.highlights,
    required this.underlines,
    required this.notes,
    required this.ink,
    required this.unplaced,
    required this.unsupportedInk,
    required this.highlightColors,
  });

  final int highlights, underlines, notes, ink;

  /// Marks whose position is unconfirmed, or that belong to another version of
  /// the text. They are never written: their place in the copy could be wrong.
  final int unplaced;

  /// Strokes on text, which a reflowable copy has no place for.
  final int unsupportedInk;

  /// Highlight count per stored color, in first-use order.
  final Map<int, int> highlightColors;

  int get marks => highlights + underlines;
  bool get isEmpty => marks + notes + ink == 0;
}

/// The marks a copy writes. Previews, counts and writers read only this, so
/// what the sheet promises and what the file contains cannot drift apart.
@immutable
class DocumentExportPlan {
  DocumentExportPlan._(this.document, this.options, this.annotations, this.notes, this.strokes);

  factory DocumentExportPlan.build(StudySetContent content, Document document, DocumentExportOptions options) {
    final source = _Source(content, document);
    return DocumentExportPlan._(
      document,
      options,
      List.unmodifiable(
        source.annotations.where(
          (a) =>
              switch (a.kind) {
                AnnotationKind.highlight => options.highlights && !options.hiddenColors.contains(a.colorIndex),
                AnnotationKind.underline => options.underlines,
              } &&
              _inPages(options, a.isText ? null : a.pages.map((p) => p.page)),
        ),
      ),
      List.unmodifiable(
        source.notes.where(
          (n) => options.notes && _inPages(options, n.anchor?.textAnchors.isNotEmpty == true ? null : [n.page]),
        ),
      ),
      List.unmodifiable(source.strokes.where((s) => options.ink && _inPages(options, [s.page]))),
    );
  }

  final Document document;
  final DocumentExportOptions options;
  final List<Annotation> annotations;
  final List<MarginNote> notes;
  final List<InkStroke> strokes;

  bool get isEmpty => annotations.isEmpty && notes.isEmpty && strokes.isEmpty;

  /// True when the copy is byte-for-byte the stored source file.
  bool get isUnchangedOriginal => isEmpty && options.pages == null && document.originalExportFile != null;

  static DocumentExportInventory inventory(StudySetContent content, Document document) {
    final source = _Source(content, document);
    final colors = <int, int>{};
    var highlights = 0, underlines = 0;
    for (final a in source.annotations) {
      if (a.kind == AnnotationKind.highlight) {
        highlights++;
        colors[a.colorIndex] = (colors[a.colorIndex] ?? 0) + 1;
      } else {
        underlines++;
      }
    }
    return DocumentExportInventory(
      highlights: highlights,
      underlines: underlines,
      notes: source.notes.length,
      ink: source.strokes.length,
      unplaced: source.unplaced,
      unsupportedInk: source.unsupportedInk,
      highlightColors: Map.unmodifiable(colors),
    );
  }

  /// 1-based pages holding at least one mark of [options], ignoring its page
  /// filter: the "pages with marks" range is derived from this.
  static Set<int> markedPages(StudySetContent content, Document document, DocumentExportOptions options) {
    final all = DocumentExportPlan.build(content, document, options.copyWith(pages: () => null));
    return {
      for (final a in all.annotations)
        if (!a.isText) ...a.pages.map((p) => p.page),
      for (final n in all.notes)
        if (n.anchor?.textAnchors.isNotEmpty != true) n.page,
      for (final s in all.strokes) s.page,
    };
  }

  static bool _inPages(DocumentExportOptions options, Iterable<int>? pages) =>
      options.pages == null || pages == null || pages.any(options.pages!.contains);
}

class _Source {
  _Source(StudySetContent content, Document document) {
    final revision = document.revision;
    bool current(Iterable<String> revisions) => revisions.every((r) => r == revision);
    if (!document.exportsMarks) return;
    for (final a in content.annotationsOn(document.id)) {
      final placed =
          !a.needsReview && (a.isText ? current(a.textAnchors.map((t) => t.revision)) : document.exportsAsPdf);
      if (placed) {
        annotations.add(a);
      } else {
        unplaced++;
      }
    }
    for (final n in content.marginNotes.where((n) => n.documentId == document.id)) {
      final anchors = n.anchor?.textAnchors ?? const [];
      final placed = document.exportsAsPdf
          ? anchors.isEmpty
          : anchors.isNotEmpty && current(anchors.map((t) => t.revision));
      if (placed) {
        notes.add(n);
      } else {
        unplaced++;
      }
    }
    for (final stroke in content.inkStrokes.where((s) => s.documentId == document.id)) {
      if (document.exportsInk && stroke.textAnchor == null) {
        strokes.add(stroke);
      } else {
        unsupportedInk++;
      }
    }
  }

  final annotations = <Annotation>[];
  final notes = <MarginNote>[];
  final strokes = <InkStroke>[];
  var unplaced = 0, unsupportedInk = 0;
}

/// Parses "1-12, 20" into pages. Returns null for text that is not a valid
/// non-empty selection within 1…[pageCount].
Set<int>? parseDocumentPageRanges(String text, int pageCount) {
  final pages = <int>{};
  for (final part in text.split(RegExp(r'[,，、;；\s]+')).where((p) => p.isNotEmpty)) {
    final match = RegExp(r'^(\d{1,7})(?:[-–—~](\d{1,7}))?$').firstMatch(part);
    if (match == null) return null;
    final first = int.parse(match.group(1)!);
    final last = int.parse(match.group(2) ?? match.group(1)!);
    if (first < 1 || first > last || last > pageCount) return null;
    for (var page = first; page <= last; page++) {
      pages.add(page);
    }
  }
  return pages.isEmpty ? null : pages;
}

/// A file name for [title] that every platform's save panel and share sheet accepts.
String documentExportFileName(String title, String extension, {String suffix = ''}) {
  final stem = '$title$suffix'.replaceAll(RegExp(r'[/:\\\x00-\x1f]'), '-').trim();
  return '${stem.isEmpty ? 'document' : stem}.$extension';
}
