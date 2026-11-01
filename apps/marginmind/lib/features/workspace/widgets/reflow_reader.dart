import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:mm_reflow/mm_reflow.dart';

import '../../../app/app_commands.dart';
import '../workspace_chrome_controller.dart';
import '../phone_reader_controls_controller.dart';
import 'phone_reader_controls.dart';
import '../../../app/navigation.dart';
import '../../../app/providers.dart';
import '../../../settings/app_settings.dart';
import '../../../shared/l10n.dart';
import '../../vocabulary/hint_card.dart';
import '../../vocabulary/hint_geometry.dart';
import '../../vocabulary/hint_painter.dart';
import '../../vocabulary/vocabulary_controller.dart';
import '../../vocabulary/vocabulary_hints.dart';
import '../../vocabulary/vocabulary_source_flash.dart';
import '../reader_compare.dart';
import '../reader_margin.dart';
import '../reader_translation.dart';
import '../reflow_geometry.dart';
import '../reflow_session.dart';
import '../workspace_controller.dart';
import 'notices.dart';
import 'reader_margin_notes.dart';
import 'reader_page_field.dart';
import 'reflow_scroll_reader.dart';
import 'reflow_thumbnail.dart';
import 'reflow_tools.dart';
import 'selection_toolbar.dart';
import 'annotation_palette.dart';

class ReflowReader extends ConsumerStatefulWidget {
  const ReflowReader({super.key, required this.studySetId, required this.document});
  final String studySetId;
  final Document document;
  @override
  ConsumerState<ReflowReader> createState() => _ReflowReaderState();
}

class _ReflowReaderState extends ConsumerState<ReflowReader> {
  final _scroll = ScrollController();
  final _vocabularyCache = VocabularyMatchCache();
  final _vocabularyGeometry = <(ChapterLayout, int?, int, int, int, bool, String?), List<VocabularyHit>>{};
  final _viewport = GlobalKey();
  final _fixedTransform = TransformationController();
  final _surfaceKeys = <(String, int?), GlobalKey>{};
  final _surfaceLayouts = <(String, int?), ChapterLayout>{};
  bool _marginColumn = false;
  double _readerWidth = 0;
  double _appliedZoom = 1;
  double _interactionScale = 1;
  final _focus = FocusNode(debugLabel: 'Reflow reader');
  int? _handledReveal;
  int _pageFieldRequests = 0;
  GlobalKey<ReflowScrollReaderState> _scrollReader = GlobalKey<ReflowScrollReaderState>();
  Offset? _lastGlobalDrag;
  bool _autoScrolling = false;
  LayoutSpec? _requested;
  ReflowSession? _configuredSession;
  List<TextAnchor> _selection = [];
  TextAnchor? _base;
  String? _gestureChapter;
  Timer? _edgeTimer;
  Offset? _lastDrag;
  bool _hoverNavigation = false;
  bool _navigationFocused = false;
  bool _scrubbing = false;
  int _scrollRequest = 0;
  int _viewTick = -1;
  ChapterLayout? _interactionLayout;
  Offset _interactionOrigin = Offset.zero;
  ReflowSession get session => ref.read(reflowSessionProvider((widget.studySetId, widget.document.id)));
  WorkspaceController get workspace => ref.read(workspaceProvider(widget.studySetId).notifier);
  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (mounted) setState(() {});
    });
    _fixedTransform.addListener(() {
      if (mounted) {
        _appliedZoom = _fixedTransform.value.getMaxScaleOnAxis();
        session.zoomTo(_appliedZoom);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && MMInput.of(context).phone) {
        ref.read(settingsProvider.notifier).usePhoneReadingDefault(widget.document.format);
      }
    });
  }

  @override
  void dispose() {
    _edgeTimer?.cancel();
    _vocabularyCache.clear();
    _vocabularyGeometry.clear();
    _fixedTransform.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _configure(LayoutSpec spec) async {
    final request = ++_scrollRequest;
    await session.configure(spec);
    if (mounted) await ref.read(readerCompareProvider(widget.studySetId).notifier).ready(widget.document.id);
    if (!mounted || request != _scrollRequest) return;
    setState(() {});
    _restoreScroll();
  }

  void _restoreScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(session.top.clamp(0, _scroll.position.maxScrollExtent));
    });
  }

  void _dismiss() {
    _base = null;
    _gestureChapter = null;
    _edgeTimer?.cancel();
    _autoScrolling = false;
    if (_selection.isNotEmpty) setState(() => _selection = []);
    workspace.dismissPending();
  }

  void _takeInput() {
    final pair = ref.read(readerCompareProvider(widget.studySetId));
    if (pair == null) return;
    ref
        .read(readerCompareProvider(widget.studySetId).notifier)
        .userInput(pair.leftDocumentId == widget.document.id ? 0 : 1);
    if (pair.right is AiCompareTarget) ref.read(translationSourceInputProvider(widget.studySetId).notifier).take();
  }

  int _tapRevision = 0;

  Future<void> _jump(TextReadingPosition position) async {
    _tapRevision++;
    _takeInput();
    _dismiss();
    final found = await session.jump(position);
    if (!found && mounted) _missing();
    if (mounted && found) {
      final pair = ref.read(readerCompareProvider(widget.studySetId));
      if (pair != null) {
        ref
            .read(readerCompareProvider(widget.studySetId).notifier)
            .changed(pair.leftDocumentId == widget.document.id ? 0 : 1);
        if (pair.right is AiCompareTarget) {
          ref.read(readerTranslationProvider(widget.studySetId).notifier).textSourceChanged(position);
        }
      }
    }
    if (mounted) {
      setState(() {});
      _restoreScroll();
    }
  }

  String get _rootTitle => ref.read(studySetProvider(widget.studySetId))?.title ?? widget.document.title;

  void _missing() => MMHud.show(context, context.l10n.readerPositionMissing);
  Future<void> _reveal(List<TextAnchor> anchors) async {
    await session.initialize();
    if (!mounted || session.book == null) return;
    final resolved = anchors.map(session.book!.resolve).toList();
    if (resolved.isEmpty || resolved.any((a) => a == null)) {
      _missing();
      return;
    }
    if (widget.document.capabilities().zoom) session.fitPage();
    await _jump(session.book!.position(resolved.first!.chapterId, resolved.first!.start));
    if (mounted) _focus.requestFocus();
  }

  Future<void> _turn(int delta, bool paged) async {
    _tapRevision++;
    _takeInput();
    if (paged) {
      _dismiss();
      await session.turn(delta * _spread);
      if (mounted) setState(() {});
    } else if (_scroll.hasClients) {
      final next = _scroll.offset + delta * (_scroll.position.viewportDimension - (session.spec?.fontSize ?? 0));
      if (next < 0 || next > _scroll.position.maxScrollExtent) {
        await _nextChapter(delta);
      } else {
        _dismiss();
        _scroll.jumpTo(next.clamp(0, _scroll.position.maxScrollExtent));
        _scrollReader.currentState?.recordPosition();
      }
    }
  }

  Future<void> _nextChapter(int delta) async {
    final book = session.book;
    if (book == null) return;
    final index = book.chapters.indexWhere((c) => c.id == session.position!.chapterId) + delta.sign;
    if (index < 0 || index >= book.chapters.length) return;
    final chapter = book.chapters[index];
    await _jump(book.position(chapter.id, delta > 0 ? 0 : chapter.canonicalText.length));
  }

  Rect _bounds(List<TextAnchor> anchors) {
    final boxes = <Rect>[];
    final layout = _interactionLayout ?? session.layout;
    if (layout == null || layout.isDisposed) return Rect.zero;
    final paged =
        !widget.document.capabilities().readingSettings ||
        (ref.read(readerCompareProvider(widget.studySetId)) == null &&
            ref.read(settingsProvider).reading(widget.document.format).paged);
    for (final anchor in anchors) {
      for (final box in layout.boxes(anchor, page: paged ? _interactionPage ?? session.page : null)) {
        boxes.add(
          Rect.fromLTRB(
            box.rect.left * _interactionScale,
            box.rect.top * _interactionScale,
            box.rect.right * _interactionScale,
            box.rect.bottom * _interactionScale,
          ).shift(_interactionOrigin),
        );
      }
    }
    return boxes.isEmpty ? Rect.zero : boxes.reduce((a, b) => a.expandToInclude(b));
  }

  int? _interactionPage;
  int _spread = 1;
  double _panZoomX = 0;
  Future<void> _commit() async {
    _edgeTimer?.cancel();
    _autoScrolling = false;
    _scrollReader.currentState?.recordPosition();
    _base = null;
    _gestureChapter = null;
    final anchors = _selection.where((a) => a.quote.isNotEmpty).toList();
    if (anchors.isEmpty || !widget.document.capabilities().selectText) return;
    try {
      final notice = await workspace.onSourceSelectionCommitted(
        widget.document.id,
        SourceSelection.text(anchors, viewportRect: _bounds(anchors)),
      );
      if (!mounted) return;
      if (notice != null) {
        setState(() => _selection = []);
        showNotice(context, notice, rootTitle: _rootTitle);
      }
    } catch (_) {
      if (mounted) MMHud.show(context, context.l10n.somethingWentWrong);
    }
  }

  List<TextAnchor> _range(TextAnchor from, TextAnchor to) {
    final book = session.book!;
    var a = book.chapters.indexWhere((c) => c.id == from.chapterId);
    var b = book.chapters.indexWhere((c) => c.id == to.chapterId);
    var start = from.start, end = to.start;
    if (a > b || (a == b && start > end)) {
      final old = a;
      a = b;
      b = old;
      final n = start;
      start = end;
      end = n;
    }
    return [
      for (var i = a; i <= b; i++)
        book.chapters[i].anchor(
          i == a ? start : 0,
          i == b ? end : book.chapters[i].canonicalText.length,
          revision: book.revision,
        ),
    ];
  }

  void _activate(ChapterLayout layout, Offset global, Offset local, int? page) {
    _interactionLayout = layout;
    _interactionPage = page;
    _lastGlobalDrag = global;
    final viewport = _viewport.currentContext?.findRenderObject() as RenderBox?;
    _interactionScale = widget.document.capabilities().zoom ? session.zoom : 1;
    _interactionOrigin = viewport?.globalToLocal(global - local * _interactionScale) ?? Offset.zero;
  }

  void _select(ChapterLayout layout, Offset point, bool begin, {int? page}) {
    if (!session.ready || layout.isDisposed || !widget.document.capabilities().selectText) return;
    final anchor = layout.hitTest(point, page: page);
    if (begin) {
      workspace.dismissPending();
      _base = anchor;
      _gestureChapter = layout.chapter.id;
    }
    if (_base == null) return;
    setState(() => _selection = _range(_base!, anchor));
    if (page == null) {
      _autoScroll();
    } else {
      _lastDrag = point;
      final delta = point.dx < layout.spec.width * .05
          ? -1
          : point.dx > layout.spec.width * .95
          ? 1
          : 0;
      if (delta == 0) {
        _edgeTimer?.cancel();
        _edgeTimer = null;
      } else if (_edgeTimer?.isActive != true) {
        _edgeTimer = Timer(MMMotion.selectionEdge, () async {
          if (!mounted || _base == null) return;
          await session.turn(delta * _spread);
          if (mounted && _base != null && session.ready) {
            _select(session.layout!, _lastDrag!, false, page: session.page);
          }
        });
      }
    }
  }

  void _drag(ChapterLayout layout, Offset global, Offset local, int? page) {
    final hit = page == null ? _scrollReader.currentState?.hitTest(global) : null;
    final target = hit?.layout ?? layout, point = hit?.local ?? local;
    _activate(target, global, point, page);
    _select(target, point, false, page: page);
  }

  void _autoScroll() {
    final viewport = _viewport.currentContext?.findRenderObject() as RenderBox?;
    final global = _lastGlobalDrag;
    if (viewport == null || global == null || !_scroll.hasClients) return;
    final y = viewport.globalToLocal(global).dy;
    final delta = y < MMReaderLayout.margin
        ? -1
        : y > viewport.size.height - MMReaderLayout.margin
        ? 1
        : 0;
    if (delta == 0) {
      _edgeTimer?.cancel();
      _edgeTimer = null;
      _autoScrolling = false;
      return;
    }
    if (_edgeTimer?.isActive == true) return;
    _edgeTimer = Timer(_autoScrolling ? MMMotion.selectionScroll : MMMotion.selectionEdge, () {
      if (!mounted || _base == null || !_scroll.hasClients) return;
      final target = (_scroll.offset + delta * MMSpacing.xxxl).clamp(
        _scroll.position.minScrollExtent,
        _scroll.position.maxScrollExtent,
      );
      if (target == _scroll.offset) return;
      _autoScrolling = true;
      _scroll.jumpTo(target);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _base == null) return;
        final hit = _scrollReader.currentState?.hitTest(_lastGlobalDrag!);
        if (hit != null) _drag(hit.layout, _lastGlobalDrag!, hit.local, null);
      });
    });
  }

  void _word(ChapterLayout layout, Offset point, int? page, {bool commit = true}) {
    if (!session.ready || layout.isDisposed || !widget.document.capabilities().selectText) return;
    final hit = layout.hitTest(point, page: page);
    final chapter = session.book!.chapter(hit.chapterId)!;
    final matches = RegExp(r'[\p{L}\p{N}_]+|[^\s]', unicode: true).allMatches(chapter.canonicalText);
    final word = matches.where((m) => m.start <= hit.start && m.end > hit.start).firstOrNull;
    if (word == null) return;
    setState(() => _selection = [chapter.anchor(word.start, word.end, revision: session.book!.revision)]);
    if (commit) _commit();
  }

  List<VocabularyHit> _vocabularyHits(ChapterLayout layout, int? page) {
    final prefs = ref.read(vocabularyHintProvider);
    final vocabulary = ref.read(vocabularyProvider).value;
    final flashOnly = prefs.modeFor(widget.document.id) == VocabularyHintMode.off;
    final flash = ref.read(vocabularyAddedFlashProvider);
    if (vocabulary == null || (flashOnly && flash == null)) return [];
    var top = layout.chapter.id == session.position?.chapterId ? session.top : 0.0;
    var height = layout.spec.pageHeight;
    final surface = _surfaceKeys[(layout.chapter.id, page)]?.currentContext?.findRenderObject() as RenderBox?;
    final viewport = _viewport.currentContext?.findRenderObject() as RenderBox?;
    if (surface?.attached == true && viewport?.attached == true && viewport!.hasSize) {
      top = surface!.globalToLocal(viewport.localToGlobal(Offset.zero)).dy;
      height = viewport.size.height;
    }
    int at(double y) {
      var low = 0, high = layout.pages.length - 1;
      while (low < high) {
        final middle = (low + high) ~/ 2;
        if (layout.pages[middle].bottom <= y) {
          low = middle + 1;
        } else {
          high = middle;
        }
      }
      return low;
    }

    final first = math.max(0, (page ?? at(top)) - 1);
    final last = math.min(layout.pages.length - 1, (page ?? at(top + height)) + 1);
    final key = (layout, page, first, last, vocabulary.version, prefs.showKnown, flashOnly ? flash : null);
    final cached = _vocabularyGeometry[key];
    if (cached != null) return cached;
    final hits = vocabularyReflowHits(
      layout,
      flashOnly ? VocabularyMatchCache() : _vocabularyCache,
      flashOnly ? vocabulary.entries.where((e) => e.id == flash).toList() : vocabulary.entries,
      vocabulary.version,
      page: page,
      top: layout.pages[first].top,
      bottom: layout.pages[last].bottom,
      showKnown: prefs.showKnown,
    );
    // Bound geometry as well as paragraph text; disposed chapter painters are
    // never retained by a long reading session or after a font change.
    _vocabularyGeometry.removeWhere((k, _) => k.$1.isDisposed || k.$5 != vocabulary.version);
    if (_vocabularyGeometry.length >= 6) _vocabularyGeometry.remove(_vocabularyGeometry.keys.first);
    _vocabularyGeometry[key] = hits;
    return hits;
  }

  Future<void> _showVocabulary(VocabularyHit hit, Rect bounds) async {
    _dismiss();
    await showVocabularyHit(
      context,
      studySetId: widget.studySetId,
      anchor: bounds,
      hit: hit,
      occurrences: (active) async {
        final e = ref.read(vocabularyProvider).value?.entries.where((e) => e.id == hit.entryId).firstOrNull;
        if (e == null) return [];
        final matcher = VocabularyMatcher([e], showKnown: true);
        final hits = <VocabularyHit>[];
        // Navigation indexes text on demand; it never typesets offscreen chapters.
        for (final chapter in session.book!.chapters) {
          for (final m in matcher.match(chapter.canonicalText)) {
            final anchor = chapter.anchor(m.start, m.end);
            hits.add(
              VocabularyHit(
                e.id,
                chapter.id == hit.anchor?.chapterId && anchor.start == hit.anchor?.start ? hit.rects : const [],
                anchor: anchor,
              ),
            );
          }
          await Future<void>.delayed(Duration.zero);
          if (!mounted || !active()) return [];
        }
        return hits;
      },
      reveal: (h) async {
        if (h.anchor case final anchor?) await _jump(session.book!.position(anchor.chapterId, anchor.start));
      },
    );
  }

  bool _editAnnotation(ChapterLayout layout, Offset point, int? page, {double tolerance = 0}) {
    if (!session.ready || layout.isDisposed) return false;
    final resolved = <String, List<TextAnchor>>{};
    final lines = <(String, Rect)>[];
    for (final a in workspace.content.annotationsOn(widget.document.id).reversed) {
      if (!a.isText) continue;
      final anchors = a.textAnchors.map(session.book!.resolve).toList();
      if (anchors.any((a) => a == null)) continue;
      resolved[a.id] = anchors.cast<TextAnchor>();
      for (final anchor in resolved[a.id]!) {
        lines.addAll(layout.boxes(anchor, page: page).map((box) => (a.id, box.rect)));
      }
    }
    final id = hitAnnotation(point, lines, tolerance: tolerance / _interactionScale);
    if (id == null) return false;
    setState(() => _selection = []);
    _base = null;
    _gestureChapter = null;
    workspace.tapHighlight(id, _bounds(resolved[id]!));
    return true;
  }

  Future<void> _tap(ChapterLayout layout, Offset point, int? page, {double tolerance = 0}) async {
    if (!session.ready || layout.isDisposed) return;
    final state = ref.read(workspaceProvider(widget.studySetId));
    for (final hit in _vocabularyHits(layout, page)) {
      if (hit.rects.any((r) => r.contains(point))) {
        final surface = _surfaceKeys[(layout.chapter.id, page)]?.currentContext?.findRenderObject() as RenderBox?;
        await _showVocabulary(hit, hit.rects.first.shift(surface?.localToGlobal(Offset.zero) ?? Offset.zero));
        return;
      }
    }
    final link = layout.links
        .where((link) => layout.boxes(link.anchor, page: page).any((b) => b.rect.contains(point)))
        .firstOrNull;
    // Direct marks keep priority, but nearby marks must not capture a link tap.
    if (_editAnnotation(layout, point, page, tolerance: link == null ? tolerance : 0)) return;
    if (link != null) {
      final uri = Uri.tryParse(link.target);
      if (uri == null) return;
      if ({'https', 'http', 'mailto'}.contains(uri.scheme)) {
        await const ExternalLinks().open(uri);
        return;
      }
      if (uri.hasScheme) return;
      final path = Uri.parse(layout.chapter.id).resolve(uri.path).path;
      final target = session.book!.chapter(uri.path.isEmpty ? layout.chapter.id : path);
      final offset = target?.elementOffsets[uri.fragment];
      if (target == null || (uri.hasFragment && offset == null)) {
        _missing();
        return;
      }
      await _jump(session.book!.position(target.id, offset ?? 0));
      if (mounted) {
        MMHud.show(
          context,
          context.l10n.goBack,
          action: (
            context.l10n.goBack,
            () async {
              await session.back();
              if (mounted) {
                setState(() {});
                _restoreScroll();
                _focus.requestFocus();
              }
            },
          ),
        );
      }
      return;
    }
    if (state.pending != null || _selection.isNotEmpty) {
      _dismiss();
      return;
    }
    final isPhone = usePhoneReaderControls(context);

    if (isPhone) {
      PhoneReaderControlsScope.read(context)?.onBodyTap();
      WorkspaceChromeScope.maybeOf(context)?.reveal();
    } else if (page == null) {
      WorkspaceChromeScope.maybeOf(context)?.reveal();
    }
    if (page != null) {
      if (point.dx < layout.spec.width * MMReaderLayout.turnZone) {
        await _turn(-1, true);
      } else if (point.dx > layout.spec.width * (1 - MMReaderLayout.turnZone)) {
        await _turn(1, true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(reflowSessionProvider((widget.studySetId, widget.document.id)));
    if (_configuredSession != s) {
      _configuredSession = s;
      _requested = null;
      _viewTick = -1;
    }
    final state = ref.watch(workspaceProvider(widget.studySetId));
    final settings = ref.watch(settingsProvider);
    final pair = ref.watch(readerCompareProvider(widget.studySetId));
    final comparing = pair != null;
    final reading = comparing
        ? ref
              .read(readerCompareProvider(widget.studySetId).notifier)
              .reading(widget.document.id, widget.document.format)
        : settings.reading(widget.document.format);
    final side = pair?.leftDocumentId == widget.document.id ? 0 : 1;
    final paged = !widget.document.capabilities().readingSettings || (!comparing && reading.paged);
    final marginState = ref.watch(readerMarginProvider(widget.studySetId));
    final style = settings.readerStyle;
    ref.listen(focusRequestsProvider, (_, request) {
      if (request?.$1 == FocusTarget.pageField && widget.document.capabilities().zoom) {
        setState(() => _pageFieldRequests++);
      }
    });
    final reveal = state.reveal;
    if (reveal?.documentId == widget.document.id && reveal!.textAnchors.isNotEmpty && reveal.nonce != _handledReveal) {
      _handledReveal = reveal.nonce;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reveal(reveal.textAnchors);
      });
    }
    ref.listen(workspaceProvider(widget.studySetId).select((s) => s.pending), (_, pending) {
      if (pending == null && mounted && _base == null && _selection.isNotEmpty) setState(() => _selection = []);
    });
    ref.listen(workspaceProvider(widget.studySetId).select((s) => s.findVisible), (was, next) {
      if (!next && was == true) s.search('');
    });
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        if (s.error != null && s.layout == null) {
          return MMEmptyState(
            icon: MMIcons.document,
            title: context.l10n.readerLoadFailed,
            message: '',
            actions: [
              MMButton(
                label: context.l10n.readerRetry,
                onPressed: () {
                  ref.invalidate(reflowSessionProvider((widget.studySetId, widget.document.id)));
                  _requested = null;
                },
              ),
            ],
          );
        }
        return ColoredBox(
          color: style.paperColor,
          child: Row(
            children: [
              if (state.readerPanelVisible && s.book != null && MMSizeClass.of(context) != MMSizeClass.compact)
                _sidebar(s, state),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, size) {
                    final margin = MMSizeClass.of(context) == MMSizeClass.compact
                        ? MMReaderLayout.marginCompact
                        : MMReaderLayout.margin;
                    _marginColumn =
                        !comparing &&
                        MMSizeClass.of(context) == MMSizeClass.regular &&
                        marginState.openDocuments.contains(widget.document.id) &&
                        size.maxWidth >= MMReaderLayout.measure + MMReaderLayout.marginColumn;
                    _readerWidth = size.maxWidth - (_marginColumn ? MMReaderLayout.marginColumn + MMSpacing.s : 0);
                    _spread =
                        widget.document.capabilities().readingSettings &&
                            paged &&
                            !comparing &&
                            !_marginColumn &&
                            _readerWidth - 2 * margin >= MMReaderLayout.spreadMinWidth &&
                            MMSizeClass.of(context) == MMSizeClass.regular
                        ? 2
                        : 1;
                    final width = math.max(
                      1.0,
                      math.min(
                        (_readerWidth - (_spread - 1) * MMReaderLayout.spreadGap) / _spread,
                        (_spread == 2 ? MMReaderLayout.spreadMeasure : MMReaderLayout.measure) + 2 * margin,
                      ),
                    );
                    final spec = LayoutSpec(
                      width: width,
                      pageHeight: math.max(MMSizes.touchTarget, size.maxHeight),
                      padding: EdgeInsets.fromLTRB(
                        math.min(margin, width / 4),
                        math.min(
                          paged
                              ? (MMSizeClass.of(context) == MMSizeClass.compact
                                    ? MMReaderLayout.topInsetCompact
                                    : MMReaderLayout.topInset)
                              : (MMSizeClass.of(context) == MMSizeClass.compact
                                    ? MMReaderLayout.scrollTopInsetCompact
                                    : MMReaderLayout.scrollTopInset),
                          math.max(1.0, size.maxHeight) / 4,
                        ),
                        math.min(margin, width / 4),
                        math.min(MMSizes.readerNavigationHeight + MMSpacing.xxl, math.max(1.0, size.maxHeight) / 4),
                      ),
                      fontSize: MMReaderTypography.fontSizes[reading.size],
                      lineHeight: MMReaderTypography.lineHeights[reading.lineHeight],
                      fontFamily: switch (reading.font) {
                        ReaderFont.original => null,
                        ReaderFont.serif => MMReaderTypography.serif,
                        ReaderFont.sans => MMReaderTypography.sans,
                      },
                      locale: Localizations.localeOf(context),
                      direction: Directionality.of(context),
                      textScale: MediaQuery.textScalerOf(context).scale(1),
                      readerStyle: style,
                    );
                    if (_requested != spec) {
                      _requested = spec;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          _dismiss();
                          _configure(spec);
                        }
                      });
                    }
                    if (_viewTick != s.viewTick) {
                      _viewTick = s.viewTick;
                      _scrollReader = GlobalKey<ReflowScrollReaderState>();
                      _restoreScroll();
                    }
                    if (widget.document.capabilities().zoom && _appliedZoom != s.zoom) {
                      final zoom = s.zoom;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          _fixedTransform.value = Matrix4.identity()
                            ..translateByDouble((1 - zoom) * size.maxWidth / 2, (1 - zoom) * size.maxHeight / 2, 0, 1)
                            ..scaleByDouble(zoom, zoom, 1, 1);
                        }
                      });
                    }
                    final layout = s.layout;
                    final drawable = layout != null && layout.spec == spec && s.ready;
                    return CallbackShortcuts(
                      bindings: {
                        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _turn(1, paged),
                        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _turn(-1, paged),
                        const SingleActivator(LogicalKeyboardKey.pageDown): () => _turn(1, paged),
                        const SingleActivator(LogicalKeyboardKey.pageUp): () => _turn(-1, paged),
                        const SingleActivator(LogicalKeyboardKey.space): () => _turn(1, paged),
                        const SingleActivator(LogicalKeyboardKey.space, shift: true): () => _turn(-1, paged),
                      },
                      child: Focus(
                        focusNode: _focus,
                        child: Stack(
                          key: _viewport,
                          children: [
                            if (drawable)
                              Positioned.fill(
                                right: _marginColumn ? MMReaderLayout.marginColumn + MMSpacing.s : 0,
                                child: ReflowAreaCapture(
                                  studySetId: widget.studySetId,
                                  documentId: widget.document.id,
                                  spec: spec,
                                  view: (s.viewTick, s.position?.chapterId, _scroll.hasClients ? _scroll.offset : 0.0),
                                  anchors: (region) {
                                    final result = <TextAnchor>[];
                                    for (final entry in _surfaceLayouts.entries) {
                                      final layout = entry.value;
                                      final box =
                                          _surfaceKeys[entry.key]?.currentContext?.findRenderObject() as RenderBox?;
                                      if (layout.isDisposed || box == null || !box.attached) continue;
                                      result.addAll(
                                        captureAnchors(
                                          layout,
                                          Rect.fromPoints(
                                            box.globalToLocal(region.topLeft),
                                            box.globalToLocal(region.bottomRight),
                                          ),
                                          page: entry.key.$2,
                                        ),
                                      );
                                    }
                                    final unique = {
                                      for (final anchor in result) (anchor.chapterId, anchor.start, anchor.end): anchor,
                                    }.values.toList();
                                    final spine = s.book!.chapters.map((c) => c.id).toList();
                                    unique.sort((a, b) {
                                      final order = spine.indexOf(a.chapterId).compareTo(spine.indexOf(b.chapterId));
                                      return order == 0 ? a.start.compareTo(b.start) : order;
                                    });
                                    return unique;
                                  },
                                  child: paged
                                      ? _pagedSurface(s, layout, state)
                                      : ReflowScrollReader(
                                          key: _scrollReader,
                                          selectionChapter: _gestureChapter,
                                          book: s.book!,
                                          position: s.position!,
                                          spec: spec,
                                          controller: _scroll,
                                          surface: (chapter) => _surface(chapter, null, state),
                                          onPreviewPosition: (p, top) {
                                            s.observe(p, top, persist: false);
                                            if (comparing) {
                                              ref.read(readerCompareProvider(widget.studySetId).notifier).changed(side);
                                            }
                                            if (pair?.right is AiCompareTarget) {
                                              ref
                                                  .read(readerTranslationProvider(widget.studySetId).notifier)
                                                  .textSourceChanged(p);
                                            }
                                          },
                                          onPosition: (p, top) {
                                            s.observe(p, top);
                                            if (comparing) {
                                              ref.read(readerCompareProvider(widget.studySetId).notifier).changed(side);
                                            }
                                            if (pair?.right is AiCompareTarget) {
                                              ref
                                                  .read(readerTranslationProvider(widget.studySetId).notifier)
                                                  .textSourceChanged(p);
                                            }
                                          },
                                          onReady: () {
                                            _restoreScroll();
                                            if (mounted) setState(() {});
                                          },
                                        ),
                                ),
                              ),
                            if (s.busy || (s.error == null && !drawable))
                              const Center(child: CircularProgressIndicator()),
                            if (s.error != null)
                              Center(
                                child: MMButton(label: context.l10n.readerRetry, onPressed: () => _configure(spec)),
                              ),
                            if (state.findVisible)
                              Positioned(
                                top: MMChromeInsets.of(context).top + MMSpacing.m,
                                right: MMSpacing.m,
                                left: MMSpacing.m,
                                child: Align(
                                  alignment: Alignment.topRight,
                                  child: _ReflowFindBar(
                                    session: s,
                                    tick: state.findFocusTick,
                                    onClose: workspace.closeFind,
                                    onNavigate: () {
                                      _dismiss();
                                      _restoreScroll();
                                    },
                                  ),
                                ),
                              ),
                            if (s.book != null)
                              Positioned(
                                bottom: usePhoneReaderControls(context)
                                    ? 0
                                    : MMSpacing.l + MMChromeInsets.of(context).bottom,
                                left: 0,
                                right: 0,
                                child: usePhoneReaderControls(context)
                                    ? _navigation(s, paged)
                                    : Center(
                                        child: MouseRegion(
                                          onEnter: (_) => setState(() => _hoverNavigation = true),
                                          onExit: (_) => setState(() => _hoverNavigation = false),
                                          child: Focus(
                                            onFocusChange: (focused) => setState(() => _navigationFocused = focused),
                                            child: WorkspaceChromeBar(bottom: true, child: _navigation(s, paged)),
                                          ),
                                        ),
                                      ),
                              ),
                            if (state.pending case final PendingAction pending when _pendingForDocument(pending))
                              Positioned.fill(
                                child: MMFloatingToolbarLayout(
                                  padding: EdgeInsets.only(
                                    top: MMChromeInsets.of(context).top,
                                    bottom: MMChromeInsets.of(context).bottom,
                                  ),
                                  anchor: switch (pending) {
                                    PendingSelection(:final selection) => selection.viewportRect ?? Rect.zero,
                                    PendingHighlight(:final viewportRect) => viewportRect,
                                    PendingResearchNote(:final viewportRect) => viewportRect,
                                  },
                                  avoid: (size) => Rect.fromLTWH(
                                    0,
                                    size.height - MMSizes.readerNavigationHeight - MMSpacing.xxl,
                                    size.width,
                                    MMSizes.readerNavigationHeight,
                                  ),
                                  child: SelectionToolbar(
                                    key: ObjectKey(pending.toolbarIdentity),
                                    studySetId: widget.studySetId,
                                    pending: pending,
                                    pdf: ref.read(readerPdfProvider(widget.studySetId)),
                                    rootTitle: _rootTitle,
                                  ),
                                ),
                              ),
                            if (state.readerPanelVisible &&
                                s.book != null &&
                                MMSizeClass.of(context) == MMSizeClass.compact)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                height: size.maxHeight * MMSizes.bottomSheetMedium,
                                child: _sidebar(s, state),
                              ),
                            if (_marginColumn)
                              Positioned(
                                top: 0,
                                bottom: 0,
                                right: 0,
                                width: MMReaderLayout.marginColumn,
                                child: GestureDetector(
                                  key: const ValueKey('reflow-margin-column'),
                                  behavior: HitTestBehavior.opaque,
                                  onTapDown: (d) {
                                    for (final entry in _surfaceLayouts.entries) {
                                      final layout = entry.value;
                                      final box =
                                          _surfaceKeys[entry.key]?.currentContext?.findRenderObject() as RenderBox?;
                                      if (layout.isDisposed || box == null || !box.attached) continue;
                                      final point = box.globalToLocal(d.globalPosition);
                                      if (point.dy < 0 || point.dy > box.size.height) continue;
                                      final anchor = layout.hitTest(
                                        Offset(layout.spec.padding.left, point.dy),
                                        page: entry.key.$2,
                                      );
                                      paragraphMarginCommand(
                                        context.l10n,
                                        ref,
                                        widget.studySetId,
                                        widget.document.id,
                                        position: s.book!.position(anchor.chapterId, anchor.start),
                                      ).onInvoke?.call();
                                      break;
                                    }
                                  },
                                ),
                              ),
                            ..._marginNotes(s, style, size.maxWidth, paged),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _pagedSurface(ReflowSession s, ChapterLayout layout, WorkspaceState state) {
    final pages = Align(
      alignment: Alignment.topCenter,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _surface(layout, s.page, state),
          if (_spread == 2 && s.page + 1 < layout.pages.length) ...[
            const SizedBox(width: MMReaderLayout.spreadGap),
            _surface(layout, s.page + 1, state),
          ],
        ],
      ),
    );
    return !widget.document.capabilities().zoom
        ? pages
        : InteractiveViewer(
            transformationController: _fixedTransform,
            minScale: MMReaderLayout.minZoom,
            maxScale: MMReaderLayout.maxZoom,
            onInteractionStart: (_) => _dismiss(),
            child: pages,
          );
  }

  bool _pendingForDocument(PendingAction pending) => switch (pending) {
    PendingSelection(:final documentId) => documentId == widget.document.id,
    PendingHighlight(:final annotationId) =>
      workspace.content.annotation(annotationId)?.documentId == widget.document.id,
    _ => false,
  };

  Widget _surface(ChapterLayout layout, int? page, WorkspaceState state) {
    final source = ref.watch(vocabularySourceFlashProvider);
    final sourceFlash = source?.studySetId == widget.studySetId && source?.documentId == widget.document.id
        ? source?.textAnchor
        : null;
    ref.watch(vocabularyHintProvider);
    ref.watch(vocabularyProvider);
    ref.watch(vocabularyAddedFlashProvider);
    final hintHits = _vocabularyHits(layout, page);
    final prefs = ref.watch(vocabularyHintProvider);
    final entries = ref.watch(vocabularyProvider).value?.entries ?? <VocabularyEntry>[];
    final hintTop = hintHits.isEmpty ? 0.0 : hintHits.first.rects.first.top - layout.spec.pageHeight;
    final hintBottom = hintHits.isEmpty ? 0.0 : hintHits.last.rects.last.bottom;
    final hintPainter = VocabularyHintPainter(
      hits: hintHits,
      entries: {for (final e in entries) e.id: e},
      color: context.mmColors.vocabulary,
      knownColor: context.mmColors.secondaryLabel,
      tint: context.mmColors.vocabularyTint,
      glossStyle: context.mmText.footnote,
      gloss: prefs.modeFor(widget.document.id) == VocabularyHintMode.gloss,
      lines: [
        for (final p in layout.pieces)
          if (!p.decorative &&
              hintHits.isNotEmpty &&
              (page == null
                  ? p.rect.bottom >= hintTop && p.rect.top <= hintBottom
                  : p.rect.bottom >= layout.pages[page].top - layout.spec.pageHeight &&
                        p.rect.top <= layout.pages[page].bottom))
            ...layout
                .boxes(layout.chapter.anchor(p.textStart, p.textEnd), page: page, candidates: [p])
                .map((b) => b.rect),
      ],
      flashEntry: ref.watch(vocabularyAddedFlashProvider),
      flashOnly: prefs.modeFor(widget.document.id) == VocabularyHintMode.off,
    );
    final selectable = widget.document.capabilities().selectText;
    final isPhone = usePhoneReaderControls(context);
    final highlights = workspace.content.annotationsOn(widget.document.id).where((a) => a.isText).toList();
    final resolved = <String, List<TextAnchor>>{};
    for (final a in highlights) {
      final anchors = a.textAnchors.map(session.book!.resolve).toList();
      if (anchors.every((a) => a != null)) resolved[a.id] = anchors.cast<TextAnchor>();
    }
    void tap(TapUpDetails d) {
      _activate(layout, d.globalPosition, d.localPosition, page);
      _tap(layout, d.localPosition, page, tolerance: d.kind == PointerDeviceKind.touch ? 12 : 3);
    }

    void word(TapDownDetails d) {
      _activate(layout, d.globalPosition, d.localPosition, page);
      _word(layout, d.localPosition, page);
    }

    final start = page == null
        ? 0
        : layout.hitTest(Offset(layout.spec.padding.left, layout.spec.padding.top), page: page).start;
    final end = page == null
        ? layout.chapter.canonicalText.length
        : layout
              .hitTest(
                Offset(
                  layout.spec.width - layout.spec.padding.right,
                  layout.spec.pageHeight - layout.spec.padding.bottom,
                ),
                page: page,
              )
              .start;
    final label = layout.chapter.anchor(math.min(start, end), math.max(start, end)).quote;
    _surfaceLayouts.removeWhere((_, value) => value.isDisposed);
    _surfaceKeys.removeWhere((key, value) => !_surfaceLayouts.containsKey(key) && value.currentContext == null);
    final surfaceId = (layout.chapter.id, page);
    _surfaceLayouts[surfaceId] = layout;
    final key = _surfaceKeys.putIfAbsent(surfaceId, GlobalKey.new);
    return TapRegion(
      key: key,
      groupId: annotationTapGroup(widget.studySetId),
      child: Listener(
        onPointerDown: (_) {
          _focus.requestFocus();
          _takeInput();
        },
        onPointerSignal: (_) {
          _takeInput();
          if (_base == null) _dismiss();
        },
        onPointerPanZoomStart: (_) {
          _takeInput();
          _panZoomX = 0;
        },
        onPointerPanZoomUpdate: (d) {
          if (page != null && session.zoom <= 1) _panZoomX += d.panDelta.dx;
        },
        onPointerPanZoomEnd: (_) {
          if (page != null && session.zoom <= 1 && _panZoomX.abs() > MMReaderLayout.margin) {
            _turn(_panZoomX < 0 ? 1 : -1, true);
          }
        },
        child: _ImmediateReaderTap(
          key: ValueKey((surfaceId, _tapRevision, 'mouse')),
          supportedDevices: const {PointerDeviceKind.mouse},
          onTapUp: tap,
          onDoubleTapDown: selectable ? word : null,
          child: GestureDetector(
            supportedDevices: const {PointerDeviceKind.mouse},
            dragStartBehavior: DragStartBehavior.down,
            behavior: HitTestBehavior.opaque,
            onPanStart: !selectable
                ? null
                : (d) {
                    _activate(layout, d.globalPosition, d.localPosition, page);
                    _select(layout, d.localPosition, true, page: page);
                  },
            onPanUpdate: !selectable
                ? null
                : (d) {
                    _drag(layout, d.globalPosition, d.localPosition, page);
                  },
            onPanEnd: !selectable ? null : (_) => _commit(),
            onPanCancel: !selectable
                ? null
                : () {
                    if (_base != null) _dismiss();
                  },
            child: _ImmediateReaderTap(
              key: ValueKey((surfaceId, _tapRevision, 'touch')),
              supportedDevices: const {
                PointerDeviceKind.touch,
                PointerDeviceKind.stylus,
                PointerDeviceKind.invertedStylus,
              },
              onTapUp: tap,
              onDoubleTapDown: (isPhone && widget.document.capabilities().zoom) ? null : (selectable ? word : null),
              onDoubleTap: (isPhone && widget.document.capabilities().zoom)
                  ? () {
                      final isZoomed = session.zoom > session.widthZoom * 1.05;
                      if (isZoomed) {
                        session.fitWidth();
                      } else {
                        session.zoomTo(1.5 * session.widthZoom);
                      }
                    }
                  : null,
              child: GestureDetector(
                supportedDevices: const {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.stylus,
                  PointerDeviceKind.invertedStylus,
                },
                behavior: HitTestBehavior.opaque,
                onLongPressStart: !selectable
                    ? null
                    : (d) {
                        _activate(layout, d.globalPosition, d.localPosition, page);
                        if (_editAnnotation(layout, d.localPosition, page, tolerance: 12)) return;
                        _word(layout, d.localPosition, page, commit: false);
                        _base = _selection.firstOrNull;
                        _gestureChapter = layout.chapter.id;
                      },
                onLongPressMoveUpdate: !selectable
                    ? null
                    : (d) {
                        _drag(layout, d.globalPosition, d.localPosition, page);
                      },
                onLongPressEnd: !selectable ? null : (_) => _commit(),
                onLongPressCancel: !selectable
                    ? null
                    : () {
                        if (_base != null) _dismiss();
                      },
                onHorizontalDragEnd: page == null || session.zoom > 1
                    ? null
                    : (d) {
                        if ((d.primaryVelocity ?? 0).abs() > MMReaderLayout.margin) {
                          _turn(d.primaryVelocity! < 0 ? 1 : -1, true);
                        }
                      },
                child: Semantics(
                  label: label,
                  textDirection: Directionality.of(context),
                  onScrollLeft: page == null ? null : () => _turn(1, true),
                  onScrollRight: page == null ? null : () => _turn(-1, true),
                  onSetSelection: !widget.document.capabilities().selectText
                      ? null
                      : (value) {
                          final a = (start + value.start).clamp(0, layout.chapter.canonicalText.length);
                          final b = (start + value.end).clamp(0, layout.chapter.canonicalText.length);
                          setState(
                            () => _selection = [
                              layout.chapter.anchor(math.min(a, b), math.max(a, b), revision: session.book!.revision),
                            ],
                          );
                          _commit();
                        },
                  child: Stack(
                    children: [
                      ReflowTools(
                        studySetId: widget.studySetId,
                        documentId: widget.document.id,
                        layout: layout,
                        page: page,
                        child: CustomPaint(
                          key: ValueKey(page == null || page == session.page ? 'reflow-surface' : 'reflow-second-page'),
                          size: Size(
                            layout.spec.width,
                            page == null ? layout.height + MMSizes.readerNavigationHeight : layout.spec.pageHeight,
                          ),
                          painter: ReflowReaderPainter(
                            layout,
                            page,
                            highlights,
                            resolved,
                            _selection,
                            session.currentMatch,
                            state.flashAnnotationId,
                            state.selectedCardId == null
                                ? null
                                : workspace.content.card(state.selectedCardId!)?.annotationId,
                            editing: switch (state.pending) {
                              PendingHighlight(:final annotationId) => annotationId,
                              _ => null,
                            },
                            editingColor: context.mmColors.accent,
                            sourceFlash: sourceFlash == null ? null : session.book!.resolve(sourceFlash),
                            sourceFlashColor: context.mmColors.vocabularyTint,
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ReflowTransientDecoration(
                            child: CustomPaint(key: const ValueKey('vocabulary-hints-surface'), painter: hintPainter),
                          ),
                        ),
                      ),
                      ..._handles(layout, page),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _handles(ChapterLayout layout, int? page) {
    if (!MMInput.touchInputOf(context) || _selection.isEmpty) return [];
    final boxes = [for (final a in _selection) ...layout.boxes(a, page: page)];
    if (boxes.isEmpty) return [];
    return [
      for (final first in [true, false])
        Positioned(
          left: (first ? boxes.first.rect.left : boxes.last.rect.right) - MMSizes.touchTarget / 2,
          top: (first ? boxes.first.rect.bottom : boxes.last.rect.bottom) - MMSizes.touchTarget / 2,
          child: Semantics(
            label: first ? context.l10n.readerSelectionStart : context.l10n.readerSelectionEnd,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) {
                _gestureChapter = layout.chapter.id;
                final a = first ? _selection.last : _selection.first;
                final offset = first ? a.end : a.start;
                _base = session.book!.chapter(a.chapterId)!.anchor(offset, offset);
              },
              onPanUpdate: (d) {
                final viewport = _viewport.currentContext?.findRenderObject() as RenderBox?;
                if (viewport == null) return;
                final local = (d.globalPosition - viewport.localToGlobal(_interactionOrigin)) / _interactionScale;
                _drag(layout, d.globalPosition, local, page);
              },
              onPanEnd: (_) => _commit(),
              child: SizedBox.square(
                dimension: MMSizes.touchTarget,
                child: Center(
                  child: Container(
                    width: MMSpacing.m,
                    height: MMSpacing.m,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: context.mmColors.accent),
                  ),
                ),
              ),
            ),
          ),
        ),
    ];
  }

  Widget _navigation(ReflowSession s, bool paged) {
    final book = s.book!, position = s.position!;
    final fixed = widget.document.capabilities().zoom;
    final sourcePage = book.chapters.indexWhere((c) => c.id == position.chapterId) + 1;
    final progress = fixed
        ? (book.chapters.length > 1 ? (sourcePage - 1) / (book.chapters.length - 1) : 0.0)
        : book.progress(position);
    void jumpPage(int page) => _jump(book.position(book.chapters[(page - 1).clamp(0, book.chapters.length - 1)].id, 0));
    if (usePhoneReaderControls(context)) {
      return PhoneReaderControls(
        studySetId: widget.studySetId,
        page: fixed ? sourcePage : s.page + 1,
        pageCount: fixed ? book.chapters.length : (s.layout?.pages.length ?? 1),
        chapter: book.title(position, fallback: widget.document.title),
        progress: progress,
        onProgress: (value) {
          fixed ? jumpPage((value * (book.chapters.length - 1)).round() + 1) : _jump(book.atProgress(value));
        },
        onJump: jumpPage,
      );
    }
    final visible = _hoverNavigation || _navigationFocused || _scrubbing || MMInput.touchInputOf(context);
    final c = context.mmColors;
    Widget fade(Widget child) => IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        duration: MMAppearance.duration(context, MMMotion.quick),
        opacity: visible ? 1 : 0,
        child: child,
      ),
    );
    return SizedBox(
      width: math.min(s.spec?.width ?? MMReaderLayout.measure, MMReaderLayout.measure) * .8,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          fade(
            SizedBox(
              height: context.mmTouchPlatform ? null : MMSizes.field,
              child: MMGlass(
                borderRadius: BorderRadius.circular(MMRadii.capsule),
                padding: const EdgeInsets.symmetric(horizontal: MMSpacing.m, vertical: MMSpacing.xs),
                child: fixed
                    ? ReaderPageField(
                        page: sourcePage,
                        pageCount: book.chapters.length,
                        editRequests: _pageFieldRequests,
                        onJump: jumpPage,
                      )
                    : GestureDetector(
                        onTap: () => workspace.showReaderPanel(ReaderPanelMode.outline),
                        child: Text(
                          '${book.title(position, fallback: widget.document.title)} · ${(book.progress(position) * 100).round()}%',
                          key: const ValueKey('reflow-progress-label'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.mmText.footnote,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: MMSpacing.s),
          Row(
            children: [
              if (paged)
                fade(
                  MMIconButton(
                    icon: MMIcons.chevronLeft,
                    tooltip: context.l10n.previousPage,
                    onPressed: book.progress(position) == 0 ? null : () => _turn(-1, true),
                  ),
                ),
              Expanded(
                child: SizedBox(
                  height: context.mmTouchPlatform ? MMSizes.touchTarget : MMSizes.field - MMSpacing.xxs,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: MMSizes.readerProgressTrack,
                      activeTrackColor: context.mmTouchPlatform
                          ? c.accent
                          : c.secondaryLabel.withValues(alpha: visible ? .65 : .3),
                      inactiveTrackColor: c.secondaryLabel.withValues(alpha: visible ? .2 : .12),
                      thumbColor: context.mmTouchPlatform ? c.label : c.secondaryLabel,
                      overlayColor: c.secondaryLabel.withValues(alpha: .1),
                      trackShape: context.mmTouchPlatform
                          ? const RoundedRectSliderTrackShape()
                          : const RectangularSliderTrackShape(),
                      thumbShape: RoundSliderThumbShape(
                        enabledThumbRadius: visible ? MMSpacing.xs : 0,
                        elevation: 0,
                        pressedElevation: 0,
                      ),
                      showValueIndicator: ShowValueIndicator.never,
                    ),
                    child: Slider(
                      key: const ValueKey('reflow-progress'),
                      padding: const EdgeInsets.symmetric(horizontal: MMSpacing.s),
                      onChangeStart: (_) => setState(() => _scrubbing = true),
                      onChangeEnd: (_) => setState(() => _scrubbing = false),
                      value: progress.clamp(0, 1),
                      onChanged: (v) {
                        if (fixed) {
                          jumpPage((v * (book.chapters.length - 1)).round() + 1);
                        } else {
                          _jump(book.atProgress(v));
                        }
                      },
                    ),
                  ),
                ),
              ),
              if (paged)
                fade(
                  MMIconButton(
                    icon: MMIcons.chevronRight,
                    tooltip: context.l10n.nextPage,
                    onPressed:
                        !s.ready ||
                            (s.page == s.layout!.pages.length - 1 && position.chapterId == book.chapters.last.id)
                        ? null
                        : () => _turn(1, true),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sidebar(ReflowSession s, WorkspaceState state) {
    final book = s.book!, l = context.l10n;
    bool needsReview(Annotation a) => a.needsReview || a.textAnchors.any((anchor) => book.resolve(anchor) == null);
    final width = ref.watch(settingsProvider).readerSidebarWidth;
    final mode = state.readerPanelMode == ReaderPanelMode.thumbnails && !widget.document.capabilities().zoom
        ? ReaderPanelMode.outline
        : state.readerPanelMode;
    Widget entry(
      String title,
      VoidCallback onTap, {
      Key? key,
      String? subtitle,
      Color? subtitleColor,
      Color? color,
      IconData? icon,
      bool selected = false,
      VoidCallback? onDelete,
      VoidCallback? onRename,
    }) => MMContextMenuRegion(
      key: key,
      onSecondaryTapUp: onDelete == null && onRename == null
          ? null
          : (d) => showMMMenu(
              context,
              position: d.globalPosition,
              entries: [
                if (onRename != null) MMMenuItem(l.rename, onRename, icon: MMIcons.editNote),
                if (onDelete != null) MMMenuItem(l.delete, onDelete, icon: MMIcons.trash),
              ],
            ),
      child: MMInteractive(
        onTap: onTap,
        selected: selected,
        builder: (context, interaction) => Container(
          color: selected
              ? context.mmColors.accentTint
              : interaction.hovered
              ? context.mmColors.hover
              : null,
          padding: const EdgeInsets.all(MMSpacing.m),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (color != null) ...[
                Container(width: MMSpacing.xs, height: MMSpacing.xxl, color: color),
                const SizedBox(width: MMSpacing.s),
              ],
              if (icon != null) ...[
                Icon(icon, size: context.mmText.callout.fontSize, color: context.mmColors.secondaryLabel),
                const SizedBox(width: MMSpacing.s),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 3, overflow: TextOverflow.ellipsis, style: context.mmText.callout),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.mmText.footnote.copyWith(
                          color: subtitleColor ?? context.mmColors.secondaryLabel,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    Future<void> navigate(TextReadingPosition p) async {
      await _jump(p);
      if (mounted && MMSizeClass.of(context) == MMSizeClass.compact) workspace.toggleReaderPanel();
    }

    final annotations = workspace.content.annotationsOn(widget.document.id).where((a) => a.isText).toList();
    final inkChapters = <String, List<InkStroke>>{};
    final unresolvedInk = <InkStroke>[];
    for (final stroke in workspace.content.inkStrokes) {
      if (stroke.documentId != widget.document.id || stroke.textAnchor == null) continue;
      final anchor = stroke.textAnchor!;
      final chapter = book.chapter(anchor.anchor.chapterId);
      if (anchor.anchor.revision != book.revision ||
          chapter?.resolves(anchor.anchor) != true ||
          !chapter!.blocks.any((b) => b.id == anchor.blockId)) {
        unresolvedInk.add(stroke);
      } else {
        // Reflow has no stable page numbers. A source chapter is the logical
        // page; fixed-layout books store exactly one original page per chapter.
        (inkChapters[chapter.id] ??= []).add(stroke);
      }
    }
    final chapterOrder = {for (var i = 0; i < book.chapters.length; i++) book.chapters[i].id: i};
    final annotationRows =
        <({String chapterId, int offset, Widget row})>[
          for (final a in annotations.where((a) => !needsReview(a)))
            (() {
              final anchor = book.resolve(a.textAnchors.first)!;
              return (
                chapterId: anchor.chapterId,
                offset: anchor.start,
                row: entry(
                  a.capture == null ? a.quote : l.imageExcerpt,
                  () {
                    navigate(book.position(anchor.chapterId, anchor.start));
                    workspace.tapHighlight(a.id);
                  },
                  onDelete: () => workspace.deleteHighlight(a.id),
                  color: MMAnnotationColor.fromIndex(a.colorIndex).color,
                  subtitle: book.title(book.position(anchor.chapterId, anchor.start)),
                ),
              );
            })(),
          for (final group in inkChapters.entries)
            (() {
              final offset = group.value.map((s) => s.textAnchor!.anchor.start).reduce(math.min);
              final position = book.position(group.key, offset);
              final number = chapterOrder[group.key]! + 1;
              final location = widget.document.layout == DocumentLayout.fixed
                  ? l.pageNumber(number)
                  : book.title(position, fallback: '${l.researchContextChapter} $number');
              return (
                chapterId: group.key,
                offset: offset,
                row: entry(
                  l.inkAnnotations,
                  () => navigate(position),
                  key: ValueKey('ink-chapter-${group.key}'),
                  icon: MMIcons.inkAnnotations,
                  subtitle: '$location · ${l.inkStrokeCount(group.value.length)}',
                ),
              );
            })(),
        ]..sort((a, b) {
          final byChapter = chapterOrder[a.chapterId]!.compareTo(chapterOrder[b.chapterId]!);
          return byChapter != 0 ? byChapter : a.offset.compareTo(b.offset);
        });
    final reviewCount = annotations.where(needsReview).length + unresolvedInk.length;
    final panel = Container(
      width: MMSizeClass.of(context) == MMSizeClass.compact
          ? double.infinity
          : math.max(0, math.min(width, MediaQuery.sizeOf(context).width * .45) - MMSpacing.m),
      margin: const EdgeInsets.all(MMSpacing.m / 2),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.mmColors.sidebarOpaque,
        borderRadius: BorderRadius.circular(MMRadii.sidebar),
        border: Border.all(color: context.mmColors.border, width: MMSizes.hairline),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: MMSpacing.s),
            child: LayoutBuilder(
              builder: (context, bounds) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: bounds.maxWidth),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final tab in [
                        if (widget.document.capabilities().zoom)
                          (ReaderPanelMode.thumbnails, MMIcons.thumbnails, l.readerThumbnails),
                        (ReaderPanelMode.outline, MMIcons.outline, l.readerOutline),
                        (ReaderPanelMode.bookmarks, MMIcons.bookmark, l.readerBookmarks),
                        (ReaderPanelMode.annotations, MMIcons.annotations, l.readerAnnotations),
                      ])
                        MMToolbarButton(
                          icon: tab.$2,
                          tooltip: tab.$3,
                          selected: mode == tab.$1,
                          onPressed: workspace.canShowReaderPanel(tab.$1)
                              ? () => workspace.setReaderPanelMode(tab.$1)
                              : null,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Divider(height: 1, thickness: 1, color: context.mmColors.separator),
          Expanded(
            child: ListView(
              children: switch (mode) {
                ReaderPanelMode.thumbnails => [
                  for (var i = 0; i < book.chapters.length; i++)
                    ReflowThumbnail(
                      key: ValueKey('reflow-thumbnail-${book.chapters[i].id}'),
                      book: book,
                      chapterId: book.chapters[i].id,
                      page: i + 1,
                      selected: s.position?.chapterId == book.chapters[i].id,
                      style: ref.watch(settingsProvider).readerStyle,
                      onTap: () => navigate(book.position(book.chapters[i].id, 0)),
                    ),
                ],
                ReaderPanelMode.outline => [
                  if (book.outline.isEmpty) entry(l.readerNoOutline, () {}),
                  for (final e in book.outline)
                    entry(
                      e.title,
                      () => navigate(book.position(e.chapterId, e.offset)),
                      selected: e.chapterId == s.position?.chapterId && e.title == book.title(s.position!),
                    ),
                ],
                ReaderPanelMode.bookmarks => [
                  MMButton(label: l.addBookmark, icon: MMIcons.bookmark, onPressed: workspace.toggleBookmark),
                  if (workspace.content.bookmarksOn(widget.document.id).isEmpty) entry(l.noBookmarks, () {}),
                  for (final b in workspace.content.bookmarksOn(
                    widget.document.id,
                    chapters: book.chapters.map((c) => c.id).toList(),
                  ))
                    if (b.position case final TextReadingPosition p)
                      Dismissible(
                        key: ValueKey(b.id),
                        onDismissed: (_) => workspace.removeBookmark(b.id),
                        child: entry(
                          b.title.isEmpty ? book.title(p, fallback: widget.document.title) : b.title,
                          () => navigate(p),
                          onDelete: () => workspace.removeBookmark(b.id),
                          onRename: () async {
                            final name = await showRenameSheet(context, title: l.rename, initial: b.title);
                            if (name != null) await workspace.renameBookmark(b.id, name);
                          },
                          subtitle:
                              '${book.chapter(p.chapterId)?.canonicalText.substring(p.offset.clamp(0, book.chapter(p.chapterId)!.canonicalText.length)).characters.take(24).string ?? ''} · ${(book.progress(p) * 100).round()}%',
                        ),
                      ),
                ],
                ReaderPanelMode.annotations => [
                  if (annotations.isEmpty && unresolvedInk.isEmpty && inkChapters.isEmpty)
                    entry(l.noAnnotations, () {}),
                  if (reviewCount > 0) ...[
                    Padding(
                      padding: const EdgeInsets.all(MMSpacing.m),
                      child: Row(
                        children: [
                          Icon(
                            MMIcons.warning,
                            color: context.mmColors.caution,
                            size: context.mmText.subheadline.fontSize,
                          ),
                          const SizedBox(width: MMSpacing.s),
                          Text(
                            l.annotationsNeedReview(reviewCount),
                            style: context.mmText.subheadline.copyWith(color: context.mmColors.caution),
                          ),
                        ],
                      ),
                    ),
                    for (final stroke in unresolvedInk)
                      entry(
                        stroke.textAnchor!.anchor.quote,
                        () {
                          final chapter = book.chapter(stroke.textAnchor!.anchor.chapterId);
                          if (chapter != null) navigate(book.position(chapter.id, 0));
                          _missing();
                        },
                        subtitle: l.readerNeedsReview,
                        onDelete: () => workspace.eraseInkStrokes({stroke.id}),
                      ),
                    for (final a in annotations.where(needsReview))
                      entry(
                        a.capture == null ? a.quote : l.imageExcerpt,
                        () async {
                          final chapter = book.chapter(a.textAnchors.first.chapterId) ?? book.chapters.firstOrNull;
                          if (chapter != null) await navigate(book.position(chapter.id, 0));
                          if (mounted) MMHud.show(context, l.annotationNotFound, icon: MMIcons.warning);
                        },
                        key: ValueKey('annotation-${a.id}'),
                        onDelete: () => workspace.deleteHighlight(a.id),
                        color: MMAnnotationColor.fromIndex(a.colorIndex).color,
                        subtitle: book.title(
                          book.position((book.chapter(a.textAnchors.first.chapterId) ?? book.chapters.first).id, 0),
                          fallback: widget.document.title,
                        ),
                        subtitleColor: context.mmColors.caution,
                      ),
                    Divider(height: MMSpacing.m, thickness: 0.5, color: context.mmColors.separator),
                  ],
                  for (final item in annotationRows) item.row,
                ],
              },
            ),
          ),
        ],
      ),
    );
    if (MMSizeClass.of(context) == MMSizeClass.compact) return panel;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        panel,
        MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            key: const ValueKey('reflow-sidebar-resize'),
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) => ref
                .read(settingsProvider.notifier)
                .setReaderSidebarWidth(ref.read(settingsProvider).readerSidebarWidth + d.delta.dx, persist: false),
            onHorizontalDragEnd: (_) => ref
                .read(settingsProvider.notifier)
                .setReaderSidebarWidth(ref.read(settingsProvider).readerSidebarWidth),
            child: const SizedBox(width: MMSpacing.xs),
          ),
        ),
      ],
    );
  }

  List<Widget> _marginNotes(ReflowSession s, MMReaderStyle style, double width, bool paged) {
    if (!s.ready) return [];
    final viewport = _viewport.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null || !viewport.hasSize) return [];
    final margin = ref.watch(readerMarginProvider(widget.studySetId));
    final notes = ref.read(readerMarginProvider(widget.studySetId).notifier).notes(widget.document.id);
    final visible = <({MarginNote note, double y, double height})>[];
    final cardWidth = math.max(1.0, math.min(MMReaderLayout.marginColumn, width - MMSpacing.l));
    for (final note in notes) {
      final original = note.anchor?.textAnchors.firstOrNull;
      final anchor = original == null ? null : s.book!.resolve(original);
      if (anchor == null) continue;
      for (final entry in _surfaceLayouts.entries) {
        final layout = entry.value;
        final box = _surfaceKeys[entry.key]?.currentContext?.findRenderObject() as RenderBox?;
        if (layout.isDisposed || box == null || !box.attached || !box.hasSize) continue;
        final boxes = layout.boxes(anchor, page: entry.key.$2);
        if (boxes.isEmpty) continue;
        final point = viewport.globalToLocal(box.localToGlobal(boxes.first.rect.topRight));
        if (point.dy < 0 || point.dy >= viewport.size.height) continue;
        visible.add((note: note, y: point.dy, height: marginNoteHeight(context, note, cardWidth, style)));
        break;
      }
    }
    visible.sort((a, b) => a.y.compareTo(b.y));
    final packed = packReflowNotes(
      [for (final n in visible) (y: n.y, height: n.height)],
      viewport.size.height,
      MMSpacing.s,
    );
    final result = <Widget>[];
    final markers = <({double y, List<MarginNote> notes})>[];
    final popups = <MarginNote>[];
    var popupTop = viewport.size.height;
    for (var i = 0; i < visible.length; i++) {
      final n = visible[i], place = packed[i];
      final popup = margin.popup.contains(n.note.id) || margin.draft?.id == n.note.id;
      if (popup) {
        popups.add(n.note);
        popupTop = math.min(popupTop, n.y);
      } else if (_marginColumn && place.card) {
        result.add(
          Positioned(
            top: place.top,
            right: MMSpacing.s,
            width: cardWidth,
            child: MarginNoteCard(key: ValueKey(n.note.id), studySetId: widget.studySetId, note: n.note, style: style),
          ),
        );
      } else {
        final group = markers.where((m) => (m.y - n.y).abs() < MMSizes.readerToolbarButton.height).firstOrNull;
        if (group == null) {
          markers.add((y: n.y, notes: [n.note]));
        } else {
          group.notes.add(n.note);
        }
      }
    }
    for (final group in markers) {
      result.add(
        Positioned(
          top: group.y.clamp(0.0, math.max(0.0, viewport.size.height - MMSizes.touchTarget)),
          right: MMSpacing.xs,
          child: MMToolbarButton(
            key: ValueKey('margin-marker-${group.notes.first.id}'),
            icon: MMIcons.quoteBubble,
            tooltip: context.l10n.marginNotes,
            onPressed: () => ref.read(readerMarginProvider(widget.studySetId).notifier).show(group.notes),
          ),
        ),
      );
    }
    if (popups.isNotEmpty) {
      final top = math.min(popupTop, viewport.size.height * (1 - MMSizes.bottomSheetMedium));
      result.add(
        Positioned(
          top: top,
          right: MMSpacing.s,
          width: cardWidth,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: viewport.size.height - top),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final note in popups)
                    MarginNoteCard(key: ValueKey(note.id), studySetId: widget.studySetId, note: note, style: style),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return result;
  }
}

/// Text geometry is always recomputed from source anchors, including bidi boxes.
class ReflowReaderPainter extends CustomPainter {
  ReflowReaderPainter(
    this.layout,
    this.page,
    this.annotations,
    this.resolved,
    this.selection,
    this.match,
    this.flash,
    this.selected, {
    this.sourceFlash,
    this.sourceFlashColor,
    this.editing,
    this.editingColor,
  });
  final ChapterLayout layout;
  final int? page;
  final List<Annotation> annotations;
  final Map<String, List<TextAnchor>> resolved;
  final List<TextAnchor> selection;
  final TextAnchor? match;
  final String? flash, selected;
  final String? editing;
  final Color? editingColor;
  final TextAnchor? sourceFlash;
  final Color? sourceFlashColor;
  @override
  void paint(Canvas canvas, Size size) {
    if (layout.isDisposed) return;
    for (final a in annotations) {
      if (a.kind == AnnotationKind.underline || a.capture != null) continue;
      for (final anchor in resolved[a.id] ?? <TextAnchor>[]) {
        for (final box in layout.boxes(anchor, page: page)) {
          canvas.drawRect(
            box.rect,
            Paint()
              ..color = MMAnnotationColor.fromIndex(a.colorIndex).color.withValues(alpha: a.id == selected ? .5 : .32),
          );
        }
      }
    }
    for (final anchor in [...selection, ?match]) {
      for (final box in layout.boxes(anchor, page: page)) {
        canvas.drawRect(box.rect, Paint()..color = layout.spec.readerStyle.marginNoteLine);
      }
    }
    if (sourceFlash != null && sourceFlashColor != null) {
      for (final box in layout.boxes(sourceFlash!, page: page)) {
        canvas.drawRect(box.rect, Paint()..color = sourceFlashColor!);
      }
    }
    layout.paint(canvas, page: page);
    for (final a in annotations) {
      for (final anchor in resolved[a.id] ?? <TextAnchor>[]) {
        for (final box in layout.boxes(anchor, page: page)) {
          if (a.kind == AnnotationKind.underline) {
            canvas.save();
            canvas.translate(box.rect.left, box.rect.top);
            MMPdfAnnotationLinePainter(
              color: MMAnnotationColor.fromIndex(a.colorIndex).underline,
              style: a.lineStyle,
            ).paint(canvas, box.rect.size);
            canvas.restore();
          }
          if (a.id == editing) {
            canvas.drawRRect(
              RRect.fromRectAndRadius(box.rect.inflate(2), const Radius.circular(3)),
              Paint()
                ..color = editingColor ?? MMAnnotationColor.fromIndex(a.colorIndex).underline
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2,
            );
          } else if (a.id == flash) {
            canvas.drawRect(
              box.rect.inflate(MMSpacing.xxs),
              Paint()
                ..color = MMAnnotationColor.fromIndex(a.colorIndex).underline
                ..style = PaintingStyle.stroke
                ..strokeWidth = MMSpacing.xxs,
            );
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(ReflowReaderPainter old) => true;
}

class _ReflowFindBar extends StatefulWidget {
  const _ReflowFindBar({required this.session, required this.tick, required this.onClose, required this.onNavigate});
  final ReflowSession session;
  final int tick;
  final VoidCallback onClose, onNavigate;
  @override
  State<_ReflowFindBar> createState() => _ReflowFindBarState();
}

class _ReflowFindBarState extends State<_ReflowFindBar> {
  final text = TextEditingController();
  final focus = FocusNode();
  @override
  void initState() {
    super.initState();
    text.text = widget.session.query;
    _focus();
  }

  void _focus() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) {
      focus.requestFocus();
      text.selection = TextSelection(baseOffset: 0, extentOffset: text.text.length);
    }
  });
  @override
  void didUpdateWidget(_ReflowFindBar old) {
    super.didUpdateWidget(old);
    if (old.tick != widget.tick) _focus();
  }

  @override
  void dispose() {
    text.dispose();
    focus.dispose();
    super.dispose();
  }

  Future<void> step(int delta) async {
    await widget.session.stepMatch(delta);
    widget.onNavigate();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session, l = context.l10n;
    return MMGlass(
      padding: const EdgeInsets.all(MMSpacing.xs),
      borderRadius: BorderRadius.circular(MMRadii.card),
      child: SizedBox(
        width: MMSizes.dropdownWideWidth,
        child: Row(
          children: [
            Expanded(
              child: MMSearchField(
                key: const ValueKey('reflow-find'),
                controller: text,
                focusNode: focus,
                placeholder: l.findInDocument,
                onChanged: (v) async {
                  await s.search(v);
                  widget.onNavigate();
                },
                onSubmitted: (_) => step(HardwareKeyboard.instance.isShiftPressed ? -1 : 1),
                onEscape: widget.onClose,
              ),
            ),
            Flexible(
              child: Text(
                s.matches.isEmpty ? l.noResults : l.matchOf(s.matchIndex + 1, s.matches.length),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.mmText.footnote,
              ),
            ),
            MMIconButton(
              icon: MMIcons.chevronUp,
              tooltip: l.findPrevious,
              onPressed: s.matches.isEmpty ? null : () => step(-1),
            ),
            MMIconButton(
              icon: MMIcons.chevronDown,
              tooltip: l.findNext,
              onPressed: s.matches.isEmpty ? null : () => step(1),
            ),
            MMIconButton(icon: MMIcons.close, tooltip: l.done, onPressed: widget.onClose),
          ],
        ),
      ),
    );
  }
}

/// Taps share an arena with selection drags and long presses, but never wait
/// for a possible second tap. Child controls still win their own taps.
class _ImmediateReaderTap extends StatelessWidget {
  const _ImmediateReaderTap({
    super.key,
    required this.child,
    required this.supportedDevices,
    required this.onTapUp,
    this.onDoubleTapDown,
    this.onDoubleTap,
  });
  final Widget child;
  final Set<PointerDeviceKind> supportedDevices;
  final GestureTapUpCallback onTapUp;
  final GestureTapDownCallback? onDoubleTapDown;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    behavior: HitTestBehavior.opaque,
    gestures: {
      MMImmediateTapGestureRecognizer: GestureRecognizerFactoryWithHandlers<MMImmediateTapGestureRecognizer>(
        () => MMImmediateTapGestureRecognizer(supportedDevices: supportedDevices),
        (tap) => tap
          ..doubleClickInterval = MMInput.of(context).doubleClickInterval
          ..onTapUp = onTapUp
          ..onDoubleTapDown = onDoubleTapDown
          ..onDoubleTap = onDoubleTap,
      ),
    },
    child: child,
  );
}
