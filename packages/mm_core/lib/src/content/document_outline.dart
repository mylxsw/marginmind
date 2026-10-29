import 'package:meta/meta.dart';

/// An editable copy of a PDF outline, kept inside the study set. An empty
/// copy intentionally hides every original entry; absence means use the PDF.
@immutable
class DocumentOutline {
  const DocumentOutline({required this.documentId, required this.items});
  final String documentId;
  final List<PdfOutlineEntry> items;

  Map<String, Object?> toJson() => {
    'documentId': documentId,
    'items': [for (final item in items) item.toJson()],
  };

  factory DocumentOutline.fromJson(Map<String, Object?> j) => DocumentOutline(
    documentId: j['documentId'] as String,
    items: [for (final item in j['items'] as List) PdfOutlineEntry.fromJson((item as Map).cast())],
  );
}

@immutable
class PdfOutlineEntry {
  const PdfOutlineEntry({required this.id, required this.title, required this.page, this.children = const []});
  final String id;
  final String title;

  /// 1-based page; 0 is a section without a destination.
  final int page;
  final List<PdfOutlineEntry> children;

  PdfOutlineEntry copyWith({String? title, int? page, List<PdfOutlineEntry>? children}) =>
      PdfOutlineEntry(id: id, title: title ?? this.title, page: page ?? this.page, children: children ?? this.children);
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'page': page,
    'children': [for (final child in children) child.toJson()],
  };
  factory PdfOutlineEntry.fromJson(Map<String, Object?> j) => PdfOutlineEntry(
    id: j['id'] as String,
    title: j['title'] as String,
    page: j['page'] as int,
    children: [
      for (final child in (j['children'] as List?) ?? const []) PdfOutlineEntry.fromJson((child as Map).cast()),
    ],
  );
}

enum OutlineDrop { before, inside, after }

enum ReaderEntrySort { pageAscending, pageDescending, title }

/// Pure tree operations. IDs stay stable through edits and whole subtrees move
/// together. Invalid moves (including a parent into its child) do nothing.
abstract final class OutlineTree {
  static Iterable<PdfOutlineEntry> flatten(List<PdfOutlineEntry> roots) sync* {
    for (final entry in roots) {
      yield entry;
      yield* flatten(entry.children);
    }
  }

  static PdfOutlineEntry? find(List<PdfOutlineEntry> roots, String id) =>
      flatten(roots).where((e) => e.id == id).firstOrNull;

  static List<PdfOutlineEntry> update(
    List<PdfOutlineEntry> roots,
    String id,
    PdfOutlineEntry Function(PdfOutlineEntry) edit,
  ) => [for (final e in roots) e.id == id ? edit(e) : e.copyWith(children: update(e.children, id, edit))];

  static List<PdfOutlineEntry> remove(List<PdfOutlineEntry> roots, String id) => [
    for (final e in roots)
      if (e.id != id) e.copyWith(children: remove(e.children, id)),
  ];

  static List<PdfOutlineEntry> insert(
    List<PdfOutlineEntry> roots,
    PdfOutlineEntry entry, {
    String? targetId,
    OutlineDrop drop = OutlineDrop.after,
  }) {
    if (find(roots, entry.id) != null) return roots;
    if (targetId == null) return [...roots, entry];
    return [
      for (final e in roots) ...[
        if (e.id == targetId && drop == OutlineDrop.before) entry,
        e.id == targetId && drop == OutlineDrop.inside
            ? e.copyWith(children: [...e.children, entry])
            : e.copyWith(
                children: insert(e.children, entry, targetId: targetId, drop: drop),
              ),
        if (e.id == targetId && drop == OutlineDrop.after) entry,
      ],
    ];
  }

  static bool canMove(List<PdfOutlineEntry> roots, String id, String targetId) {
    final entry = find(roots, id);
    return entry != null && find(roots, targetId) != null && find([entry], targetId) == null;
  }

  static List<PdfOutlineEntry> move(List<PdfOutlineEntry> roots, String id, String targetId, OutlineDrop drop) {
    if (!canMove(roots, id, targetId)) return roots;
    return insert(remove(roots, id), find(roots, id)!, targetId: targetId, drop: drop);
  }

  static List<PdfOutlineEntry> sort(List<PdfOutlineEntry> roots, ReaderEntrySort order) {
    final result = [for (final e in roots) e.copyWith(children: sort(e.children, order))];
    final positions = {for (final (index, entry) in roots.indexed) entry.id: index};
    result.sort((a, b) {
      final value = switch (order) {
        ReaderEntrySort.pageAscending => a.page.compareTo(b.page),
        ReaderEntrySort.pageDescending => b.page.compareTo(a.page),
        ReaderEntrySort.title => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      };
      return value != 0 ? value : positions[a.id]!.compareTo(positions[b.id]!);
    });
    return result;
  }
}
