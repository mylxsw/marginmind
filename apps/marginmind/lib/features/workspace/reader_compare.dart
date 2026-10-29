import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../app/providers.dart';
import 'reader_margin.dart';
import 'workspace_controller.dart';

ComparePair reverseComparePair(ComparePair pair) => pair.copyWith(
  leftDocumentId: (pair.right as PdfCompareTarget).documentId,
  right: PdfCompareTarget(pair.leftDocumentId),
  alignPoints: [for (final p in pair.alignPoints) AlignPoint(left: p.right, right: p.left)],
);

/// Replace coincident anchors and validate strict order before persisting.
List<AlignPoint> insertCompareAlignment(ReadingAlignment mapping, List<AlignPoint> points, AlignPoint point) {
  final left = ReadingAlignment.scalar(point.left, mapping.leftHeights);
  final next =
      [
        for (final p in points)
          if ((ReadingAlignment.scalar(p.left, mapping.leftHeights) - left).abs() >= .001) p,
        point,
      ]..sort(
        (a, b) => ReadingAlignment.scalar(
          a.left,
          mapping.leftHeights,
        ).compareTo(ReadingAlignment.scalar(b.left, mapping.leftHeights)),
      );
  ReadingAlignment(leftHeights: mapping.leftHeights, rightHeights: mapping.rightHeights, points: next);
  return next;
}

final readerCompareProvider = NotifierProvider.family<ReaderCompareSession, ComparePair?, String>(
  ReaderCompareSession.new,
);

/// One session owns the pair, scroll driver and original positions across remounts.
class ReaderCompareSession extends Notifier<ComparePair?> {
  ReaderCompareSession(this.studySetId);
  final String studySetId;
  ReadingSync _sync = ReadingSync();
  final _positions = <String, PdfReadingPosition>{};
  final _restoring = <String>{};
  int _epoch = 0;
  int _transition = 0;
  int? _queuedSide;
  bool _scheduled = false;
  bool _writing = false;
  int? _driven;

  WorkspaceController get _workspace => ref.read(workspaceProvider(studySetId).notifier);
  MMPdfViewController pdf(String id) => ref.read(documentPdfProvider((studySetId, id)));
  String? document(int side) => side == 0 ? state?.leftDocumentId : (state?.right as PdfCompareTarget?)?.documentId;

  @override
  ComparePair? build() {
    ref.onDispose(() => _sync.dispose());
    ref.listen(workspaceContentProvider(studySetId), (_, content) {
      final pair = state;
      if (pair == null || content == null) return;
      if (content.document(pair.leftDocumentId) == null || content.document(document(1)!) == null) {
        unawaited(exit(force: true));
        return;
      }
      final stored = content.comparePairs.where((p) => p.id == pair.id).firstOrNull;
      if (stored != null && !_writing) {
        state = stored.leftDocumentId == pair.leftDocumentId ? stored : reverseComparePair(stored);
        _sync.enabled = state!.sync;
      }
    });
    ref.listen(workspaceProvider(studySetId).select((s) => s.activeDocumentId), (_, id) {
      if (state != null && id == null) {
        unawaited(exit(force: true));
      } else if (state != null && id != null && id != document(0)) {
        // Source links and the library's switcher keep working while comparing.
        unawaited(_openFromWorkspace(id));
      }
    });
    return null;
  }

  Future<void> _openFromWorkspace(String id) async {
    try {
      await select(id, left: true);
    } catch (_) {
      // The library/source-link command already changed the active document.
      // Keep tools and the visible left PDF together if saving the pair fails.
    }
    if (ref.mounted &&
        state != null &&
        state!.leftDocumentId != id &&
        ref.read(workspaceProvider(studySetId)).activeDocumentId == id) {
      _workspace.openDocument(state!.leftDocumentId);
    }
  }

  void remember() {
    _epoch++;
    _queuedSide = null;
    _driven = null;
    for (final id in {
      document(0),
      document(1),
      ref.read(workspaceProvider(studySetId)).activeDocumentId,
    }.whereType<String>()) {
      final position = pdf(id).readingPosition;
      if (position != null) _positions[id] = position;
    }
  }

  Future<bool> select(String id, {bool left = false, double readerWidth = 0}) async {
    if (_workspace.content.document(id) == null) return false;
    final current = state;
    if (current == null && left) return false;
    final leftId = current?.leftDocumentId ?? ref.read(workspaceProvider(studySetId)).activeDocumentId;
    if (leftId == null || (current == null && id == leftId)) return false;
    if (current != null && id == document(left ? 1 : 0)) {
      await swap();
      return false;
    }
    if (current != null && id == document(left ? 0 : 1)) return false;
    final transition = ++_transition;
    if (!await ref.read(readerMarginProvider(studySetId).notifier).finish() ||
        !ref.mounted ||
        transition != _transition) {
      return false;
    }
    remember();
    final l = left ? id : leftId;
    final r = left ? document(1)! : id;
    final saved = _workspace.content.comparePairs
        .where(
          (p) =>
              p.right is PdfCompareTarget &&
              ((p.leftDocumentId == l && (p.right as PdfCompareTarget).documentId == r) ||
                  (p.leftDocumentId == r && (p.right as PdfCompareTarget).documentId == l)),
        )
        .firstOrNull;
    final pair = saved == null
        ? ComparePair(id: ref.read(editorProvider).newId(), leftDocumentId: l, right: PdfCompareTarget(r))
        : saved.leftDocumentId == l
        ? saved
        : reverseComparePair(saved);
    if (saved == null) await _workspace.saveComparePair(pair);
    if (!ref.mounted || transition != _transition) return false;
    final hidden = current == null && _workspace.beginCompareLayout(readerWidth);
    _sync.dispose();
    _sync = ReadingSync()..enabled = pair.sync;
    state = pair;
    if (ref.read(workspaceProvider(studySetId)).activeDocumentId != l) _workspace.openDocument(l);
    return hidden;
  }

  Future<void> swap() async {
    final transition = ++_transition;
    if (state == null ||
        !await ref.read(readerMarginProvider(studySetId).notifier).finish() ||
        !ref.mounted ||
        transition != _transition ||
        state == null) {
      return;
    }
    remember();
    state = reverseComparePair(state!);
    _workspace.openDocument(state!.leftDocumentId);
  }

  Future<void> exit({bool force = false}) async {
    final transition = ++_transition;
    if (state == null) return;
    if (!force && !await ref.read(readerMarginProvider(studySetId).notifier).finish()) return;
    if (!ref.mounted || transition != _transition || state == null) return;
    remember();
    _sync.dispose();
    state = null;
    _workspace.endCompareLayout();
  }

  Future<void> ready(String id) async {
    final position = _positions.remove(id);
    if (position == null) return;
    _restoring.add(id);
    try {
      await pdf(id).jumpToReadingPosition(position);
      await SchedulerBinding.instance.endOfFrame;
    } finally {
      _restoring.remove(id);
    }
  }

  Future<void> _save(ComparePair next, {bool undoable = false}) async {
    if (_writing) return;
    final before = state;
    state = next;
    _sync.enabled = next.sync;
    _writing = true;
    try {
      await _workspace.saveComparePair(next, undoable: undoable);
    } catch (_) {
      if (ref.mounted && state?.id == next.id) {
        state = before == null || state!.leftDocumentId == before.leftDocumentId ? before : reverseComparePair(before);
        _sync.enabled = before?.sync ?? false;
      }
      rethrow;
    } finally {
      _writing = false;
    }
  }

  Future<void> toggleSync() async {
    if (state == null) return;
    _epoch++;
    _driven = null;
    await _save(state!.copyWith(sync: !state!.sync));
  }

  ReadingAlignment? get mapping {
    if (state == null) return null;
    final l = pdf(document(0)!).pageHeights, r = pdf(document(1)!).pageHeights;
    if (l.isEmpty || r.isEmpty) return null;
    return ReadingAlignment(leftHeights: l, rightHeights: r, points: state!.alignPoints);
  }

  Future<bool> align() async {
    final map = mapping;
    if (map == null || _writing) return false;
    final point = AlignPoint(left: pdf(document(0)!).readingPosition!, right: pdf(document(1)!).readingPosition!);
    if (state!.sync &&
        state!.alignPoints.any(
          (p) =>
              p.left.page == point.left.page &&
              p.left.y == point.left.y &&
              p.right.page == point.right.page &&
              p.right.y == point.right.y,
        )) {
      return false;
    }
    final points = insertCompareAlignment(map, state!.alignPoints, point);
    _epoch++;
    _driven = null;
    await _save(state!.copyWith(alignPoints: points, sync: true), undoable: true);
    return true;
  }

  void userInput(int side) {
    _epoch++;
    _queuedSide = null;
    _driven = null;
    _sync.userInput(side);
  }

  void changed(int side) {
    if (state == null) return;
    if (_driven != side && _restoring.isEmpty) _queuedSide = side;
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      final source = _queuedSide;
      _queuedSide = null;
      if (!ref.mounted || state == null) return;
      for (final id in [document(0)!, document(1)!]) {
        final position = pdf(id).readingPosition;
        if (position != null) _workspace.recordPage(id, position.page);
      }
      if (source != null) unawaited(_drive(source));
    });
  }

  Future<void> _drive(int side) async {
    if (state?.sync != true || _restoring.isNotEmpty) return;
    final map = mapping;
    if (map == null) return;
    final source = pdf(document(side)!).readingPosition;
    final target = pdf(document(1 - side)!);
    final current = target.readingPosition;
    if (source == null || current == null) return;
    final position = map.map(source, reverse: side == 1);
    final heights = side == 0 ? map.rightHeights : map.leftHeights;
    if ((ReadingAlignment.scalar(position, heights) - ReadingAlignment.scalar(current, heights)).abs() < .001) return;
    final epoch = _epoch;
    await _sync.drive(side, () async {
      _driven = 1 - side;
      try {
        await target.jumpToReadingPosition(position);
        await SchedulerBinding.instance.endOfFrame;
      } finally {
        if (epoch == _epoch) _driven = null;
      }
    });
  }
}

/// The content format has no language metadata yet; unknown stays unlabelled.
String? compareLanguage(String text) {
  final chinese = RegExp(r'[\u3400-\u9fff]').allMatches(text).length;
  final latin = RegExp(r'[a-zA-Z]').allMatches(text).length;
  if (chinese > 0 && chinese * 3 >= latin) return 'zh';
  return latin >= 3 ? 'en' : null;
}

/// Sample text locally; never send PDF text to a model for menu metadata.
final compareDocumentInfoProvider = FutureProvider.family<({String? language, bool? hasText}), (String, String)>((
  ref,
  key,
) async {
  final workspace = ref.watch(workspaceProvider(key.$1).notifier);
  final doc = workspace.content.documents.where((d) => d.id == key.$2).firstOrNull;
  if (doc == null) return (language: null, hasText: null);
  final fallback = compareLanguage(doc.title);
  if (!ref.read(pdfRenderingEnabledProvider)) return (language: fallback, hasText: null);
  try {
    final text = await MMPdfEngine.pageText(workspace.filePath(doc), 1);
    return (language: compareLanguage(text ?? '') ?? fallback, hasText: text?.trim().isNotEmpty == true);
  } catch (_) {
    return (language: fallback, hasText: null);
  }
});
