import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_book/mm_book.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_reflow/mm_reflow.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../app/providers.dart';
import 'reflow_document.dart';
import 'workspace_controller.dart';

final reflowSessionProvider = Provider.autoDispose.family<ReflowSession, (String, String)>((ref, key) {
  ref.watch(
    workspaceProvider(key.$1).select((state) {
      final document = state.content?.document(key.$2);
      return (document?.revision, document?.contentManifest);
    }),
  );
  final doc = ref.read(workspaceProvider(key.$1)).content?.document(key.$2);
  final repo = ref.read(contentRepositoryProvider) as DocumentRepository;
  final session = ReflowSession(
    () {
      if (doc == null) throw StateError('Document closed');
      return ReflowDocument.load(repo, key.$1, doc);
    },
    onPosition: (p) {
      if (ref.mounted) ref.read(workspaceProvider(key.$1).notifier).setReadingPosition(key.$2, p);
    },
  );
  ref.onDispose(session.dispose);
  return session;
});

/// Owns one drawable chapter. Paragraphs are released before their image handles;
/// every settings/navigation request invalidates all older geometry immediately.
class ReflowSession extends ChangeNotifier {
  ReflowSession(this.load, {required this.onPosition, int maxImagePixels = 16 * 1024 * 1024})
    : engine = ReflowEngine(maxChapters: 0, maxImagePixels: maxImagePixels);
  final Future<ReflowDocument> Function() load;
  final ValueChanged<TextReadingPosition> onPosition;
  final ReflowEngine engine;
  ReflowDocument? book;
  ChapterLayout? layout;
  LayoutSpec? spec;
  Map<String, MMBookImage> _images = {};
  final _fonts = <String>{};
  TextReadingPosition? position;
  final history = <TextReadingPosition>[];
  List<TextAnchor> matches = [];
  String query = '';
  int matchIndex = -1;
  double zoom = 1;
  int page = 0;
  int viewTick = 0;
  double top = 0;
  bool busy = false, _disposed = false;
  Object? error;
  Future<void>? _loading;
  int _request = 0;
  int _searchRequest = 0;
  bool get ready => layout != null && !busy && engine.accepts(layout!.generation);

  Future<void> initialize() => _loading ??= _initialize();
  Future<void> _initialize() async {
    try {
      final loaded = await load();
      if (_disposed) return;
      book = loaded;
      final saved = loaded.document.readingPosition;
      position =
          saved is TextReadingPosition && saved.revision == loaded.revision && loaded.chapter(saved.chapterId) != null
          ? loaded.position(
              saved.chapterId,
              saved.offset.clamp(0, loaded.chapter(saved.chapterId)!.canonicalText.length),
            )
          : loaded.start;
      notifyListeners();
    } catch (e) {
      if (!_disposed) {
        error = e;
        notifyListeners();
      }
    }
  }

  Future<void> configure(LayoutSpec next) async {
    if (_disposed || (spec == next && (busy || ready))) return;
    spec = next;
    await initialize();
    if (!_disposed && book != null) await _layout();
  }

  Future<void> _layout() async {
    final b = book, target = position, currentSpec = spec;
    if (_disposed || b == null || target == null || currentSpec == null) return;
    final request = ++_request;
    final generation = engine.invalidate();
    busy = true;
    error = null;
    notifyListeners();
    final chapter = b.chapter(target.chapterId)!;
    final images = <String, MMBookImage>{};
    bool current() => !_disposed && request == _request;
    try {
      final paths = <String>{
        for (final block in chapter.blocks) ...[
          if (block.resource != null) block.resource!,
          for (final r in [...block.runs, ...block.rows.expand((r) => r).expand((c) => c.runs)])
            if (r.resource != null) r.resource!,
        ],
      };
      final budget = math.max(1, engine.maxImagePixels ~/ math.max(1, paths.length));
      for (final path in paths) {
        if (!current()) return;
        try {
          images[path] = await MMBookImage.decode(
            await b.resource(path),
            svgImage: b.resources[path]?['mime'] == 'image/svg+xml',
            maxPixels: budget,
          );
        } catch (_) {
          /* Missing/unsupported art retains its source placeholder. */
        }
      }
      final families = <String, String>{};
      for (final font in chapter.fonts) {
        if (!current()) return;
        final family = 'mmbook-${b.revision}-${font.family}';
        final key = '$family/${font.resource}';
        if (_fonts.contains(key)) {
          families[font.family] = family;
          continue;
        }
        try {
          final bytes = await b.resource(font.resource);
          await MMBookFonts.load(family, bytes);
          _fonts.add(key);
          families[font.family] = family;
        } catch (_) {
          /* Use the design-system fallback. */
        }
      }
      if (!current()) return;
      final containers = <String, Map<String, String>>{};
      void visit(BookNode node) {
        containers[node.path] = node.style;
        for (final child in node.children) {
          visit(child);
        }
      }

      for (final node in chapter.structure) {
        visit(node);
      }
      final next = await engine.layout(
        chapter,
        currentSpec,
        generation,
        revision: b.revision,
        visibleOffset: target.offset,
        resources: LayoutResources(
          revision: b.revision,
          images: images,
          intrinsicSizes: {
            for (final path in paths)
              if (b.resources[path]?['width'] is num && b.resources[path]?['height'] is num)
                path: Size(
                  (b.resources[path]!['width'] as num).toDouble(),
                  (b.resources[path]!['height'] as num).toDouble(),
                ),
          },
          headerRows: {
            for (final block in chapter.blocks)
              if (block.kind == BlockKind.table)
                block.id: block.rows.takeWhile((row) => row.isNotEmpty && row.every((c) => c.header)).length,
          },
          containerStyles: containers,
          fontFamilies: families,
        ),
      );
      if (!current()) {
        next.dispose();
        return;
      }
      layout?.dispose();
      for (final image in _images.values) {
        image.dispose();
      }
      layout = next;
      _images = Map.of(images);
      images.clear();
      viewTick++;
      page = next.pageForOffset(target.offset);
      top = next.reveal(chapter.anchor(target.offset, target.offset))?.rect.top ?? 0;
    } catch (e) {
      if (current()) error = e;
    } finally {
      for (final image in images.values) {
        image.dispose();
      }
      if (current()) {
        busy = false;
        notifyListeners();
      }
    }
  }

  double get pageScale {
    final chapter = layout?.chapter, current = spec;
    if (chapter?.viewportWidth == null || chapter?.viewportHeight == null || current == null) return 1;
    return math.min(current.contentWidth / chapter!.viewportWidth!, current.contentHeight / chapter.viewportHeight!);
  }

  double get widthZoom =>
      layout?.chapter.viewportWidth == null ? 1 : spec!.contentWidth / (layout!.chapter.viewportWidth! * pageScale);
  void zoomTo(double value) {
    if (_disposed || !value.isFinite) return;
    final next = value.clamp(MMReaderLayout.minZoom, MMReaderLayout.maxZoom);
    if ((zoom - next).abs() < .000001) return;
    zoom = next;
    notifyListeners();
  }

  void fitPage() => zoomTo(1);
  void fitWidth() => zoomTo(widthZoom);
  void actualSize() => zoomTo(1 / pageScale);

  Future<bool> jump(TextReadingPosition target, {bool remember = true}) async {
    final b = book;
    if (_disposed || b == null || target.revision != b.revision) return false;
    final chapter = b.chapter(target.chapterId);
    if (chapter == null || target.offset > chapter.canonicalText.length) return false;
    if (remember && position != null) history.add(position!);
    final sameChapter = layout?.chapter.id == target.chapterId;
    position = target;
    if (sameChapter && ready) {
      viewTick++;
      page = layout!.pageForOffset(target.offset);
      top = layout!.reveal(chapter.anchor(target.offset, target.offset))?.rect.top ?? 0;
      notifyListeners();
    } else {
      await _layout();
    }
    if (!_disposed && position == target) onPosition(target);
    return true;
  }

  Future<void> back() async {
    if (history.isNotEmpty) await jump(history.removeLast(), remember: false);
  }

  Future<void> turn(int delta) async {
    if (!ready) return;
    final next = page + delta;
    if (next >= 0 && next < layout!.pages.length) {
      final anchor = layout!.hitTest(
        Offset(layout!.spec.padding.left, layout!.spec.padding.top + layout!.pages[next].headerHeight),
        page: next,
      );
      await jump(book!.position(anchor.chapterId, anchor.start), remember: false);
      if (_disposed) return;
      page = next;
      notifyListeners();
    } else {
      final index = book!.chapters.indexWhere((c) => c.id == position!.chapterId) + delta.sign;
      if (index >= 0 && index < book!.chapters.length) {
        final c = book!.chapters[index];
        await jump(book!.position(c.id, delta > 0 ? 0 : c.canonicalText.length), remember: false);
      }
    }
  }

  void scrolled(double offset, {bool persist = true}) {
    if (!ready) return;
    top = offset;
    final anchor = layout!.capture(offset).position;
    position = book!.position(anchor.chapterId, anchor.start);
    page = layout!.pageForOffset(anchor.start);
    if (persist) onPosition(position!);
    notifyListeners();
  }

  void observe(TextReadingPosition p, double localTop, {bool persist = true}) {
    if (_disposed) return;
    position = p;
    top = localTop;
    if (persist) onPosition(p);
    notifyListeners();
  }

  Future<void> search(String text) async {
    final request = ++_searchRequest;
    query = text;
    await initialize();
    if (_disposed || request != _searchRequest) return;
    matches = book?.search(text) ?? [];
    matchIndex = matches.isEmpty ? -1 : 0;
    notifyListeners();
    if (matches.isNotEmpty) await revealMatch();
  }

  Future<void> stepMatch(int delta) async {
    if (matches.isEmpty) return;
    matchIndex = (matchIndex + delta) % matches.length;
    notifyListeners();
    await revealMatch();
  }

  Future<void> revealMatch() => jump(book!.position(matches[matchIndex].chapterId, matches[matchIndex].start));
  TextAnchor? get currentMatch => matchIndex < 0 ? null : matches[matchIndex];
  @override
  void dispose() {
    _disposed = true;
    _request++;
    layout?.dispose();
    engine.dispose();
    for (final image in _images.values) {
      image.dispose();
    }
    super.dispose();
  }
}
