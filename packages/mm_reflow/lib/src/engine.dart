part of '../mm_reflow.dart';

/// Cancellation is normal when a reader changes settings or closes a book.
class LayoutCancelled implements Exception {
  const LayoutCancelled();
  @override
  String toString() => 'Layout generation was superseded';
}

/// Recoverable image admission failure. Re-decode at a lower pixel limit or
/// replace some image handles with placeholders, then request layout again.
class ImageBudgetExceeded implements Exception {
  const ImageBudgetExceeded({required this.decodedPixels, required this.budget});
  final int decodedPixels;
  final int budget;

  @override
  String toString() => 'ImageBudgetExceeded: $decodedPixels decoded pixels exceed the $budget pixel budget';
}

class _CacheEntry {
  _CacheEntry(this.layout, this.resources);
  final ChapterLayout layout;
  final LayoutResources resources;
}

/// UI-isolate typesetting with cooperative scheduling and an owning LRU cache.
/// Each returned layout is a separate lease: callers must dispose it. Clear the
/// cache before releasing borrowed images. [revision] is the content/resource
/// revision from the book manifest, never just a chapter name.
class ReflowEngine {
  ReflowEngine({
    this.maxChapters = 3,
    this.maxBytes = 32 * 1024 * 1024,
    this.maxImagePixels = 16 * 1024 * 1024,
    this.batchBudget = const Duration(milliseconds: 4),
    Future<void> Function()? yieldWork,
  }) : _yieldWork = yieldWork ?? (() => Future<void>.delayed(Duration.zero)) {
    if (maxChapters < 0 || maxBytes < 0 || maxImagePixels < 0 || batchBudget.isNegative) {
      throw ArgumentError('Budgets cannot be negative');
    }
  }
  final int maxChapters, maxBytes, maxImagePixels;
  final Duration batchBudget;
  final Future<void> Function() _yieldWork;
  final _cache = <(String, String, LayoutSpec), _CacheEntry>{};
  int _generation = 0;
  bool _disposed = false;
  int get generation => _generation;
  int get cachedLayouts => _cache.length;
  int get cachedBytes => _cache.values.fold(0, (n, e) => n + e.layout.estimatedBytes);

  /// Immediately invalidates old asynchronous work and geometry callbacks.
  int invalidate() => ++_generation;
  bool accepts(int generation) => !_disposed && generation == _generation;

  Future<ChapterLayout> layout(
    BookChapter chapter,
    LayoutSpec spec,
    int generation, {
    required String revision,
    LayoutResources? resources,
    int visibleOffset = 0,
  }) async {
    spec.validate();
    if (_disposed || generation < _generation) throw const LayoutCancelled();
    _generation = generation;
    final input = resources ?? LayoutResources();
    final pixels = input.images.values.toSet().fold(0, (n, i) => n + i.decodedPixels);
    if (pixels > maxImagePixels) throw ImageBudgetExceeded(decodedPixels: pixels, budget: maxImagePixels);
    final key = (revision, chapter.id, spec);
    final old = _cache.remove(key);
    if (old != null) {
      if (old.resources.matches(input)) {
        _cache[key] = old;
        return old.layout._retain(generation);
      }
      old.layout.dispose();
    }
    final work = Stopwatch()..start();
    final builder = _Typesetter(chapter, spec, input, visibleOffset: visibleOffset);
    final budget = Stopwatch()..start();
    try {
      for (final _ in builder.steps()) {
        if (!accepts(generation)) throw const LayoutCancelled();
        if (budget.elapsed >= batchBudget) {
          builder.maxBatchTime = Duration(
            microseconds: math.max(builder.maxBatchTime.inMicroseconds, budget.elapsedMicroseconds),
          );
          work.stop();
          await _yieldWork();
          work.start();
          budget.reset();
        }
      }
      if (!accepts(generation)) throw const LayoutCancelled();
      final geometry = builder.finish();
      geometry.workTime = work.elapsed;
      geometry.maxBatchTime = Duration(
        microseconds: math.max(geometry.maxBatchTime.inMicroseconds, budget.elapsedMicroseconds),
      );
      final result = ChapterLayout._(chapter, spec, generation, revision, geometry);
      if (maxChapters > 0 && result.estimatedBytes <= maxBytes) {
        _cache.remove(key)?.layout.dispose();
        _cache[key] = _CacheEntry(result._retain(generation), input);
        while (_cache.length > maxChapters || cachedBytes > maxBytes) {
          _cache.remove(_cache.keys.first)!.layout.dispose();
        }
      }
      return result;
    } catch (_) {
      builder.dispose();
      rethrow;
    }
  }

  /// Evict all references to a chapter before disposing its image handles.
  void evictChapter(String chapterId) {
    for (final key in _cache.keys.where((k) => k.$2 == chapterId).toList()) {
      _cache.remove(key)!.layout.dispose();
    }
  }

  void clear() {
    for (final entry in _cache.values) {
      entry.layout.dispose();
    }
    _cache.clear();
  }

  void dispose() {
    if (!_disposed) {
      _disposed = true;
      invalidate();
      clear();
    }
  }
}

/// Reading-view boundary. Settings changes invalidate callbacks synchronously;
/// completion preserves the source position and drops late generations. The
/// reader owns persistence, cross-chapter navigation and selection gestures.
class ReflowController extends ChangeNotifier {
  ReflowController({ReflowEngine? engine, this.onSelectionChanged}) : engine = engine ?? ReflowEngine();
  final ReflowEngine engine;
  final ValueChanged<List<TextAnchor>>? onSelectionChanged;
  ChapterLayout? _current;
  bool _disposed = false;
  int? _imageRelayoutGeneration;
  List<TextAnchor> _selection = const [];
  ChapterLayout? get current => _current;
  int get generation => engine.generation;
  double restoredTop = 0;
  List<TextAnchor> get selection => _selection;

  Future<ChapterLayout?> layout(
    BookChapter chapter,
    LayoutSpec spec, {
    required String revision,
    LayoutResources? resources,
    double viewportTop = 0,
    TextAnchor? position,
  }) async {
    if (_disposed) throw StateError('Controller has been disposed');
    final bookmark = position == null ? _current?.capture(viewportTop) : ViewportBookmark(position, 0);
    final request = engine.invalidate();
    notifyListeners();
    try {
      final result = await engine.layout(
        chapter,
        spec,
        request,
        revision: revision,
        resources: resources,
        visibleOffset: bookmark?.position.start ?? 0,
      );
      if (_disposed || !engine.accepts(request)) {
        result.dispose();
        return null;
      }
      final old = _current;
      _current = result;
      restoredTop = bookmark == null ? 0 : result.restore(bookmark) ?? 0;
      notifyListeners();
      old?.dispose();
      return result;
    } on LayoutCancelled {
      return null;
    }
  }

  /// One late image-size correction per generation; it retains the source
  /// bookmark. The caller batches missing image dimensions before invoking it.
  Future<bool> imagesReady(LayoutResources resources, int generation, {double viewportTop = 0}) async {
    if (!engine.accepts(generation) || _current?.generation != generation || _imageRelayoutGeneration == generation) {
      return false;
    }
    _imageRelayoutGeneration = generation;
    final old = _current!;
    final bookmark = old.capture(viewportTop);
    engine.evictChapter(old.chapter.id);
    try {
      final result = await engine.layout(
        old.chapter,
        old.spec,
        generation,
        revision: old.revision,
        resources: resources,
        visibleOffset: bookmark.position.start,
      );
      if (!engine.accepts(generation)) {
        result.dispose();
        return false;
      }
      _current = result;
      restoredTop = result.restore(bookmark) ?? 0;
      notifyListeners();
      old.dispose();
      return true;
    } on LayoutCancelled {
      return false;
    }
  }

  TextAnchor? hitTest(
    Offset point, {
    required int generation,
    int? page,
    Offset localScroll = Offset.zero,
    Map<String, double> horizontalOffsets = const {},
  }) => engine.accepts(generation) && _current?.generation == generation
      ? _current!.hitTest(point, page: page, localScroll: localScroll, horizontalOffsets: horizontalOffsets)
      : null;
  List<LayoutBox> boxes(
    TextAnchor anchor, {
    int? page,
    Offset localScroll = Offset.zero,
    Map<String, double> horizontalOffsets = const {},
  }) => _current != null && engine.accepts(_current!.generation)
      ? _current!.boxes(anchor, page: page, localScroll: localScroll, horizontalOffsets: horizontalOffsets)
      : const [];
  LayoutBox? reveal(
    TextAnchor position, {
    int? page,
    Offset localScroll = Offset.zero,
    Map<String, double> horizontalOffsets = const {},
  }) => _current != null && engine.accepts(_current!.generation)
      ? _current!.reveal(position, page: page, localScroll: localScroll, horizontalOffsets: horizontalOffsets)
      : null;

  /// The caller supplies anchors in spine order, one per selected chapter.
  /// Stale drag callbacks are rejected before notifying the reading view.
  bool selectionChanged(List<TextAnchor> anchors, {required int generation}) {
    if (!engine.accepts(generation) || _current?.generation != generation) return false;
    if (anchors.any((a) => a.chapterId == _current!.chapter.id && !_current!.chapter.resolves(a))) return false;
    _selection = List.unmodifiable(anchors);
    onSelectionChanged?.call(_selection);
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _current?.dispose();
    _current = null;
    engine.dispose();
    super.dispose();
  }
}
