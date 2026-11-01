import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../app/providers.dart';
import '../../settings/app_settings.dart';
import 'reader_margin.dart';
import 'reader_ocr.dart';
import 'reader_paragraphs.dart';
import 'reader_translation.dart';
import 'reflow_session.dart';
import 'workspace_controller.dart';

ComparePair reverseComparePair(ComparePair pair) => pair.copyWith(
  leftDocumentId: (pair.right as PdfCompareTarget).documentId,
  right: PdfCompareTarget(pair.leftDocumentId),
  alignPoints: [for (final p in pair.alignPoints) AlignPoint(left: p.right, right: p.left)],
  sourceAlignPoints: [for (final p in pair.sourceAlignPoints) SourceAlignPoint(left: p.right, right: p.left)],
);

/// The newest explicit alignment replaces older anchors that contradict it.
List<AlignPoint> insertCompareAlignment(ReadingAlignment mapping, List<AlignPoint> points, AlignPoint point) {
  final left = ReadingAlignment.scalar(point.left, mapping.leftHeights);
  final right = ReadingAlignment.scalar(point.right, mapping.rightHeights);
  final next =
      [
        for (final p in points)
          if ((ReadingAlignment.scalar(p.left, mapping.leftHeights) - left).abs() >= .001 &&
              (ReadingAlignment.scalar(p.right, mapping.rightHeights) - right).abs() >= .001 &&
              (ReadingAlignment.scalar(p.left, mapping.leftHeights) < left) ==
                  (ReadingAlignment.scalar(p.right, mapping.rightHeights) < right))
            p,
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
  dependencies: [
    compareDocumentInfoProvider,
    documentPdfProvider,
    readerMarginProvider,
    reflowSessionProvider,
    translationParagraphsProvider,
    workspaceContentProvider,
    workspaceProvider,
  ],
);

/// One session owns the pair, scroll driver and original positions across remounts.
class ReaderCompareSession extends Notifier<ComparePair?> {
  ReaderCompareSession(this.studySetId);
  final String studySetId;
  ReadingSync _sync = ReadingSync();
  final _positions = <String, PdfReadingPosition>{};
  final _restoring = <String>{};
  final _readings = <String, ReadingSettings>{};
  final _sourcePositions = <String, ReadingPosition>{};
  final _paragraphs = <String, List<TranslationParagraph>>{};
  final _scrollPositions = <String, PdfScrollPosition>{};
  int _epoch = 0;
  int _transition = 0;
  int? _queuedSide;
  bool _scheduled = false;
  bool _writing = false;
  int? _driven;
  int? _driver;

  WorkspaceController get _workspace => ref.read(workspaceProvider(studySetId).notifier);
  MMPdfViewController pdf(String id) => ref.read(documentPdfProvider((studySetId, id)));
  String? document(int side) => side == 0
      ? state?.leftDocumentId
      : switch (state?.right) {
          PdfCompareTarget(:final documentId) => documentId,
          _ => null,
        };

  @override
  ComparePair? build() {
    ref.onDispose(() => _sync.dispose());
    ref.listen(workspaceContentProvider(studySetId), (_, content) {
      final pair = state;
      if (pair == null || content == null) return;
      if (content.document(pair.leftDocumentId) == null ||
          (document(1) != null && content.document(document(1)!) == null)) {
        unawaited(exit(force: true));
        return;
      }
      final stored = content.comparePairs.where((p) => p.id == pair.id).firstOrNull;
      if (stored != null && !_writing) {
        state = stored.leftDocumentId == pair.leftDocumentId
            ? stored
            : stored.right is PdfCompareTarget
            ? reverseComparePair(stored)
            : stored;
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
    _scrollPositions.clear();
    _driver = null;
    _queuedSide = null;
    _driven = null;
    for (final id in {
      document(0),
      document(1),
      ref.read(workspaceProvider(studySetId)).activeDocumentId,
    }.whereType<String>()) {
      if (_workspace.content.document(id)?.contentManifest != null) {
        final position = ref.read(reflowSessionProvider((studySetId, id))).position;
        if (position != null) _sourcePositions[id] = position;
        continue;
      }
      final position = pdf(id).readingPosition;
      if (position != null) _positions[id] = position;
      final scroll = pdf(id).scrollPosition;
      if (scroll != null) _scrollPositions[id] = scroll;
    }
  }

  Future<bool> select(String id, {bool left = false, double readerWidth = 0}) async {
    if (_workspace.content.document(id) == null) return false;
    final current = state;
    if (current == null && left) return false;
    final leftId = current?.leftDocumentId ?? ref.read(workspaceProvider(studySetId)).activeDocumentId;
    if (leftId == null || (current == null && id == leftId)) return false;
    if (current?.right is AiCompareTarget && left) {
      final language =
          ref.read(compareDocumentInfoProvider((studySetId, id))).value?.language ??
          compareLanguage(_workspace.content.document(id)!.title);
      return openAi(language == 'zh' ? 'en' : 'zh', documentId: id);
    }
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
    final prepared = await _prepareSourcePair(pair);
    if (!ref.mounted || transition != _transition) return false;
    if (saved == null || prepared != pair) await _workspace.saveComparePair(prepared);
    if (!ref.mounted || transition != _transition) return false;
    final hidden = current == null && _workspace.beginCompareLayout(readerWidth);
    _sync.dispose();
    _sync = ReadingSync()..enabled = prepared.sync;
    for (final id in [l, r]) {
      final doc = _workspace.content.document(id)!;
      _readings.putIfAbsent(id, () => ref.read(settingsProvider).reading(doc.format));
    }
    state = prepared;
    if (ref.read(workspaceProvider(studySetId)).activeDocumentId != l) _workspace.openDocument(l);
    return hidden;
  }

  ReadingSettings reading(String id, DocumentFormat format) =>
      _readings[id] ?? ref.read(settingsProvider).reading(format);
  void setReading(String id, ReadingSettings value) {
    if (state == null) return;
    _readings[id] = value;
    state = state!.copyWith();
  }

  bool get canAlignSource => usesSourceAlignment && state?.right is PdfCompareTarget;
  bool get usesSourceAlignment =>
      state != null &&
      [
        document(0),
        document(1),
      ].whereType<String>().any((id) => _workspace.content.document(id)?.contentManifest != null);

  Future<ComparePair> _prepareSourcePair(ComparePair pair) async {
    if (pair.right is! PdfCompareTarget) return pair;
    final l = pair.leftDocumentId, r = (pair.right as PdfCompareTarget).documentId;
    if (![l, r].any((id) => _workspace.content.document(id)?.contentManifest != null)) return pair;
    final lists = await Future.wait([
      for (final id in [l, r]) ref.read(translationParagraphsProvider((studySetId, id)).future),
    ]);
    if (!ref.mounted) return pair;
    _paragraphs[l] = lists[0];
    _paragraphs[r] = lists[1];
    final valid = pair.sourceAlignPoints
        .where(
          (p) =>
              lists[0].any((a) => sameSourcePosition(paragraphPosition(a), p.left)) &&
              lists[1].any((a) => sameSourcePosition(paragraphPosition(a), p.right)),
        )
        .toList();
    if (valid.isNotEmpty) {
      return valid.length == pair.sourceAlignPoints.length ? pair : pair.copyWith(sourceAlignPoints: valid);
    }
    // Persist the initial paragraph-order pairing as an editable table. Extra
    // paragraphs remain unpaired; no document percentage fallback is used.
    return pair.copyWith(
      alignPoints: [],
      sourceAlignPoints: [
        for (var i = 0; i < lists[0].length && i < lists[1].length; i++)
          SourceAlignPoint(left: paragraphPosition(lists[0][i]), right: paragraphPosition(lists[1][i])),
      ],
    );
  }

  ReadingPosition? sourcePosition(String id) {
    if (_workspace.content.document(id)?.contentManifest != null) {
      return ref.read(reflowSessionProvider((studySetId, id))).position;
    }
    final p = pdf(id).readingPosition;
    return p == null ? null : PdfPosition(p.page, y: p.y);
  }

  Future<void> jumpSource(String id, ReadingPosition position) async {
    if (position is TextReadingPosition) {
      await ref.read(reflowSessionProvider((studySetId, id))).jump(position, remember: false);
    } else if (position is PdfPosition) {
      await pdf(id).jumpToReadingPosition(
        PdfReadingPosition(page: position.page, y: position.y ?? pdf(id).pageSize(position.page)?.height ?? 0),
      );
    }
  }

  Future<bool> openAi(String language, {String? documentId, double readerWidth = 0}) async {
    final transition = ++_transition;
    final id = documentId ?? state?.leftDocumentId ?? ref.read(workspaceProvider(studySetId)).activeDocumentId;
    if (id == null ||
        _workspace.content.document(id) == null ||
        !await ref.read(readerMarginProvider(studySetId).notifier).finish() ||
        !ref.mounted ||
        transition != _transition) {
      return false;
    }
    remember();
    final saved = _workspace.content.comparePairs
        .where(
          (p) =>
              p.leftDocumentId == id &&
              p.right is AiCompareTarget &&
              (p.right as AiCompareTarget).targetLang == language,
        )
        .firstOrNull;
    final pair =
        saved ??
        ComparePair(id: ref.read(editorProvider).newId(), leftDocumentId: id, right: AiCompareTarget(language));
    if (saved == null) await _workspace.saveComparePair(pair);
    if (!ref.mounted || transition != _transition) return false;
    final hidden = state == null && _workspace.beginCompareLayout(readerWidth);
    _sync.dispose();
    _sync = ReadingSync()..enabled = pair.sync;
    final doc = _workspace.content.document(id)!;
    _readings.putIfAbsent(id, () => ref.read(settingsProvider).reading(doc.format));
    state = pair;
    if (ref.read(workspaceProvider(studySetId)).activeDocumentId != id) _workspace.openDocument(id);
    return hidden;
  }

  Future<void> swap() async {
    if (state?.right is! PdfCompareTarget) return;
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
    _readings.clear();
    _workspace.endCompareLayout();
  }

  Future<void> ready(String id) async {
    final source = _sourcePositions.remove(id);
    if (source != null) {
      await jumpSource(id, source);
      return;
    }
    // A new viewer/document may have identical dimensions but a new origin.
    _scrollPositions.remove(id);
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
    _driver = null;
    _driven = null;
    await _save(state!.copyWith(sync: !state!.sync));
  }

  ReadingAlignment? get mapping {
    if (state?.right is! PdfCompareTarget) return null;
    final l = pdf(document(0)!).pageHeights, r = pdf(document(1)!).pageHeights;
    if (l.isEmpty || r.isEmpty) return null;
    return ReadingAlignment(leftHeights: l, rightHeights: r, points: state!.alignPoints);
  }

  Future<bool> align() async {
    if (usesSourceAlignment) {
      if (_writing || state?.right is! PdfCompareTarget) return false;
      final l = document(0)!, r = document(1)!;
      final lp = sourcePosition(l), rp = sourcePosition(r);
      if (lp == null || rp == null) return false;
      final left = paragraphAt(_paragraphs[l] ?? [], lp), right = paragraphAt(_paragraphs[r] ?? [], rp);
      if (left == null || right == null) return false;
      final point = SourceAlignPoint(left: paragraphPosition(left), right: paragraphPosition(right));
      final points = insertParagraphAlignment(state!.sourceAlignPoints, point, _paragraphs[l]!, _paragraphs[r]!);
      _epoch++;
      _driver = null;
      _driven = null;
      await _save(state!.copyWith(sourceAlignPoints: points, alignPoints: [], sync: true), undoable: true);
      return true;
    }
    final map = mapping;
    if (map == null || _writing) return false;
    final left = pdf(document(0)!).readingPosition, right = pdf(document(1)!).readingPosition;
    if (left == null || right == null) return false;
    final point = AlignPoint(left: left, right: right);
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
    _driver = null;
    _driven = null;
    await _save(state!.copyWith(alignPoints: points, sync: true), undoable: true);
    return true;
  }

  void userInput(int side) {
    _epoch++;
    if (_driver != side && document(1 - side) != null) pdf(document(1 - side)!).stopScroll();
    _driver = side;
    _queuedSide = side;
    _driven = null;
    _sync.userInput(side);
    // The child viewer may update its matrix before this outer pointer
    // listener runs. Retain that update and give this gesture ownership.
    changed(side);
  }

  void changed(int side) {
    if (state == null) return;
    // Only the pane the user is driving may lead. Layout, a clamped target,
    // and late programmatic notifications cannot take ownership back.
    if (_driver == side && _driven != side && _restoring.isEmpty) _queuedSide = side;
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.ensureVisualUpdate();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      final source = _queuedSide;
      _queuedSide = null;
      if (!ref.mounted || state == null) return;
      if (usesSourceAlignment) {
        if (source != null) unawaited(_driveSource(source));
        return;
      }
      for (final id in [document(0), document(1)].whereType<String>()) {
        final position = pdf(id).readingPosition;
        if (position != null) _workspace.recordPage(id, position.page);
      }
      final previous = Map.of(_scrollPositions);
      for (final id in [document(0), document(1)].whereType<String>()) {
        final position = pdf(id).scrollPosition;
        if (position != null) _scrollPositions[id] = position;
      }
      if (source != null && document(source) != null && document(1 - source) != null) {
        final id = document(source)!, targetId = document(1 - source)!;
        final before = previous[id], current = _scrollPositions[id];
        final targetBefore = previous[targetId], targetNow = _scrollPositions[targetId];
        if (before != null &&
            current != null &&
            current.sameGeometry(before) &&
            targetBefore != null &&
            targetNow != null &&
            targetNow.sameGeometry(targetBefore)) {
          unawaited(_drive(source, current.offset - before.offset));
        }
      }
    });
  }

  Future<void> _driveSource(int side) async {
    if (state?.sync != true || _restoring.isNotEmpty || _driver != side || _driven != null) return;
    final id = document(side), targetId = document(1 - side);
    if (id == null || targetId == null) return;
    final position = sourcePosition(id);
    final paragraph = position == null ? null : paragraphAt(_paragraphs[id] ?? [], position);
    if (paragraph == null) return;
    final start = paragraphPosition(paragraph);
    final pair = state!.sourceAlignPoints
        .where((p) => sameSourcePosition(side == 0 ? p.left : p.right, start))
        .firstOrNull;
    if (pair == null) return;
    final target = side == 0 ? pair.right : pair.left;
    final current = sourcePosition(targetId);
    if (current != null && sameSourcePosition(current, target)) return;
    final epoch = _epoch;
    _driven = 1 - side;
    try {
      await jumpSource(targetId, target);
      await SchedulerBinding.instance.endOfFrame;
    } finally {
      if (ref.mounted && epoch == _epoch) {
        _driven = null;
        final latest = sourcePosition(id);
        final paragraph = latest == null ? null : paragraphAt(_paragraphs[id] ?? [], latest);
        if (paragraph != null && !sameSourcePosition(paragraphPosition(paragraph), start)) changed(side);
      }
    }
  }

  Future<void> _drive(int side, double distance) async {
    if (state?.sync != true || _restoring.isNotEmpty || _driver != side || distance.abs() < .001) return;
    final targetId = document(1 - side)!;
    final target = pdf(targetId);
    final epoch = _epoch;
    await _sync.drive(side, () async {
      _driven = 1 - side;
      try {
        await target.scrollByScreenDistance(distance);
        // The follower's movement is the baseline if the user takes over next.
        // Discard distance blocked at an edge, so reversal follows immediately.
        final position = target.scrollPosition;
        if (epoch == _epoch && position != null) _scrollPositions[targetId] = position;
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
  if (doc.contentManifest != null) return (language: fallback, hasText: doc.features.text);
  final path = workspace.filePath(doc);
  final recognized = ref.watch(readerOcrProvider(path).select((s) => s.document));
  if (!ref.read(pdfRenderingEnabledProvider)) return (language: fallback, hasText: null);
  try {
    var text = await MMPdfEngine.pageText(recognized?.path ?? path, 1);
    var hasText = recognized?.textPages.isNotEmpty ?? (text?.trim().isNotEmpty == true);
    // A cover can be an image even when the remaining document has text.
    if (!hasText && recognized == null) {
      final paragraphs = await MMPdfEngine.translationParagraphs(path, doc.id);
      hasText = paragraphs.isNotEmpty;
      text = paragraphs.firstOrNull?.text;
    }
    return (language: compareLanguage(text ?? '') ?? fallback, hasText: hasText);
  } catch (_) {
    return (language: fallback, hasText: null);
  }
}, dependencies: [workspaceProvider]);
