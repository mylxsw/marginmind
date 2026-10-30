import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../../app/app_commands.dart';
import '../../assistant/assistant_scope.dart' show selectionContext, imageAreaContext;
import '../../assistant/widgets/assistant_quick_actions.dart';
import '../../assistant/widgets/assistant_overlays.dart' show boundsOf;
import '../../../shared/l10n.dart';
import '../workspace_controller.dart';
import '../reader_margin.dart';
import 'notices.dart';
import 'annotation_palette.dart';
import 'text_annotation_tools.dart';
import 'selection_lookup.dart';
import '../selection_vocabulary_context.dart';
import '../../vocabulary/vocabulary_controller.dart';

/// All reader text actions share their floating UI, focus and command handling.
class SelectionToolbar extends ConsumerStatefulWidget {
  const SelectionToolbar({
    super.key,
    required this.studySetId,
    required this.pending,
    required this.pdf,
    required this.rootTitle,
  });

  final String studySetId;
  final PendingAction pending;
  final MMPdfViewController pdf;
  final String rootTitle;

  @override
  ConsumerState<SelectionToolbar> createState() => _SelectionToolbarState();
}

class _SelectionToolbarState extends ConsumerState<SelectionToolbar> {
  final _focus = FocusNode();
  final _moreAnchor = GlobalKey();
  bool _busy = false;
  bool _quickOpen = false;
  bool _paletteOpen = false;
  bool _translationOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _dismiss() {
    ref.read(workspaceProvider(widget.studySetId).notifier).dismissPending();
    widget.pdf.clearSelection();
  }

  Future<void> _ask(
    String documentId,
    List<AnnotationPage> pages,
    String quote, [
    List<TextAnchor> anchors = const [],
  ]) async {
    if ((pages.isEmpty && anchors.isEmpty) || quote.trim().isEmpty) return;
    final layout = context.findAncestorRenderObjectOfType<RenderCustomSingleChildLayoutBox>();
    if (layout == null) return;
    final origin = layout.localToGlobal(Offset.zero);
    final selected = switch (widget.pending) {
      PendingSelection(:final selection) => selection.viewportRect ?? Rect.zero,
      PendingHighlight(:final viewportRect) => viewportRect,
      _ => Rect.zero,
    };
    setState(() => _quickOpen = true);
    final continued = await showAssistantQuickActions(
      context,
      studySetId: widget.studySetId,
      pending: widget.pending,
      passage: selectionContext(documentId: documentId, page: pages.firstOrNull?.page, quote: quote),
      source: SourceAnchor(
        target: anchors.isEmpty
            ? PdfTarget(documentId: documentId, pages: pages, quote: quote)
            : TextTarget(documentId: documentId, textAnchors: anchors, context: quote),
      ),
      toolbar: boundsOf(context),
      selection: selected.shift(origin),
      viewport: origin & layout.size,
    );
    if (!mounted) return;
    setState(() => _quickOpen = false);
    if (continued == true) {
      _dismiss();
    } else {
      _focus.requestFocus();
    }
  }

  Future<void> _askArea(Annotation annotation) async {
    final controller = ref.read(workspaceProvider(widget.studySetId).notifier);
    final card = controller.content.cardForAnnotation(annotation.id);
    final nodes = controller.content.nodes.where((node) => node.cardId == card?.id);
    final activeMapId = ref.read(workspaceProvider(widget.studySetId)).activeMapId;
    final node = nodes.where((node) => node.mapId == activeMapId).firstOrNull ?? nodes.firstOrNull;
    final layout = context.findAncestorRenderObjectOfType<RenderCustomSingleChildLayoutBox>();
    if (card == null || layout == null) return;
    final origin = layout.localToGlobal(Offset.zero);
    setState(() => _quickOpen = true);
    final continued = await showAssistantQuickActions(
      context,
      studySetId: widget.studySetId,
      pending: widget.pending,
      passage: imageAreaContext(annotation: annotation, cardId: card.id, title: context.l10n.imageExcerpt),
      source: SourceAnchor(
        target: PdfTarget(documentId: annotation.documentId, pages: annotation.pages),
      ),
      insertionTarget: node?.mapId == activeMapId ? (mapId: activeMapId, parentId: card.id) : null,
      toolbar: boundsOf(context),
      selection: widget.pending is PendingHighlight
          ? (widget.pending as PendingHighlight).viewportRect.shift(origin)
          : boundsOf(context),
      viewport: origin & layout.size,
    );
    if (!mounted) return;
    setState(() => _quickOpen = false);
    if (continued == true) {
      _dismiss();
    } else {
      _focus.requestFocus();
    }
  }

  Future<void> _run(ReaderSelectionCommand command, [MMAnnotationColor? color]) async {
    if (_busy || !ref.read(workspaceProvider(widget.studySetId).notifier).canRunSelection(command)) return;
    if (command == ReaderSelectionCommand.translate) {
      await _translate();
      return;
    }
    _busy = true;
    final controller = ref.read(workspaceProvider(widget.studySetId).notifier);
    final selectedColor = color ?? ref.read(workspaceProvider(widget.studySetId)).color;
    final pending = widget.pending;
    final pdf = widget.pdf;
    final rootTitle = widget.rootTitle;
    // Capture the target before opening a sheet or clearing the selection.
    try {
      if (command == ReaderSelectionCommand.marginNote) {
        final annotation = pending is PendingHighlight ? controller.content.annotation(pending.annotationId) : null;
        final selection = pending is PendingSelection ? pending.selection : null;
        if (annotation == null && selection == null) return;
        final margin = ref.read(readerMarginProvider(widget.studySetId).notifier);
        final anchors = annotation?.textAnchors ?? selection!.textAnchors;
        final pages = annotation == null
            ? selection!.pages
            : annotation.isText
            ? <AnnotationPage>[]
            : annotation.pages;
        if (pages.isNotEmpty) await pdf.ensureVisible(pages.first.page, pages.first.rects.first);
        await margin.start(
          annotation?.documentId ?? (pending as PendingSelection).documentId,
          pages: anchors.isEmpty ? pages : null,
          textAnchors: anchors,
          quote: annotation?.quote ?? selection!.text,
          colorIndex: annotation?.colorIndex ?? selectedColor.index,
        );
        await pdf.clearSelection();
        return;
      }
      if (pending case PendingHighlight(:final annotationId)) {
        final annotation = controller.content.annotation(annotationId);
        if (annotation == null) {
          _dismiss();
          return;
        }
        WorkspaceNotice? notice;
        if (color != null) {
          await controller.recolor(annotationId, color);
        } else {
          switch (command) {
            case ReaderSelectionCommand.copy:
              if (annotation.quote.isEmpty) return;
              await Clipboard.setData(ClipboardData(text: annotation.quote));
              if (mounted) MMHud.show(context, context.l10n.copiedHud);
              controller.dismissPending();
            case ReaderSelectionCommand.excerpt:
              final existing = controller.content.cardForAnnotation(annotationId);
              if (existing != null &&
                  controller.content.node(
                        existing.id,
                        mapId: ref.read(workspaceProvider(widget.studySetId)).activeMapId,
                      ) !=
                      null) {
                return;
              }
              notice = await controller.addHighlightToMap(annotationId);
            case ReaderSelectionCommand.locateCard:
              await controller.locateHighlightCard(annotationId);
            case ReaderSelectionCommand.deleteHighlight:
              notice = await controller.deleteHighlight(annotationId);
            case ReaderSelectionCommand.assistant:
              if (annotation.quote.isEmpty) {
                await _askArea(annotation);
                return;
              }
              await _ask(
                annotation.documentId,
                annotation.isText ? [] : annotation.pages,
                annotation.quote,
                annotation.textAnchors,
              );
              return;
            case ReaderSelectionCommand.translate:
            case ReaderSelectionCommand.marginNote:
            case ReaderSelectionCommand.highlight:
            case ReaderSelectionCommand.note:
              return;
          }
        }
        if (mounted) showNotice(context, notice, rootTitle: rootTitle);
        await pdf.clearSelection();
        return;
      }
      if (pending is! PendingSelection ||
          command == ReaderSelectionCommand.locateCard ||
          command == ReaderSelectionCommand.deleteHighlight) {
        return;
      }
      if (command == ReaderSelectionCommand.assistant) {
        await _ask(pending.documentId, pending.selection.pages, pending.selection.text, pending.selection.textAnchors);
        return;
      }
      if (command == ReaderSelectionCommand.note) {
        // The note is typed on its card in the map; the selection is done.
        await controller.excerptSourceAndEditNote(pending.documentId, pending.selection, selectedColor);
        await pdf.clearSelection();
        return;
      }
      if (command == ReaderSelectionCommand.copy) {
        await Clipboard.setData(ClipboardData(text: pending.selection.text));
        if (!mounted) return;
        MMHud.show(context, context.l10n.copiedHud);
        controller.dismissPending();
      } else {
        final notice =
            command == ReaderSelectionCommand.highlight && !ref.read(workspaceProvider(widget.studySetId)).syncToMap
            ? await controller.highlightSource(pending.documentId, pending.selection, selectedColor)
            : await controller.excerptSource(pending.documentId, pending.selection, selectedColor);
        if (mounted) showNotice(context, notice, rootTitle: rootTitle);
      }
      await pdf.clearSelection();
    } catch (_) {
      if (mounted) MMHud.show(context, context.l10n.somethingWentWrong, icon: MMIcons.close);
    } finally {
      _busy = false;
    }
  }

  Future<void> _translate() async {
    if (_busy) return;
    final pending = widget.pending;
    final annotation = pending is PendingHighlight
        ? ref.read(workspaceProvider(widget.studySetId).notifier).content.annotation(pending.annotationId)
        : null;
    final selection = pending is PendingSelection ? pending.selection : null;
    final quote = annotation?.quote ?? selection?.text ?? '';
    final anchors = annotation?.textAnchors ?? selection?.textAnchors ?? <TextAnchor>[];
    final pages = annotation == null
        ? selection?.pages ?? []
        : annotation.isText
        ? <AnnotationPage>[]
        : annotation.pages;
    if (quote.trim().isEmpty || (pages.isEmpty && anchors.isEmpty)) return;
    final layout = context.findAncestorRenderObjectOfType<RenderCustomSingleChildLayoutBox>();
    if (layout == null) return;
    final origin = layout.localToGlobal(Offset.zero);
    final rect = pending is PendingHighlight ? pending.viewportRect : selection?.viewportRect ?? Rect.zero;
    _busy = true;
    setState(() => _translationOpen = true);
    var ask = false;
    try {
      await showSelectionLookup(
        context,
        onAsk: () => ask = true,
        studySetId: widget.studySetId,
        paragraph: TranslationParagraph(
          documentId: annotation?.documentId ?? (pending as PendingSelection).documentId,
          page: pages.firstOrNull?.page,
          textAnchor: anchors.firstOrNull,
          index: 0,
          text: quote,
          fingerprint: '',
          rects: pages.firstOrNull?.rects ?? [],
        ),
        toolbar: boundsOf(context),
        selection: rect.shift(origin),
        viewport: origin & layout.size,
      );
    } finally {
      _busy = false;
      if (mounted) {
        setState(() => _translationOpen = false);
        _focus.requestFocus();
      }
    }
    if (ask && mounted) {
      await _ask(annotation?.documentId ?? (pending as PendingSelection).documentId, pages, quote, anchors);
    }
  }

  Future<void> _compactMore(bool isHighlight, bool isArea, bool hasCard) async {
    _paletteOpen = true;
    final l = context.l10n;
    final controller = ref.read(workspaceProvider(widget.studySetId).notifier);
    final capabilities = controller.activeCapabilities;
    try {
      await showMMMenu(
        context,
        position: boundsOf(_moreAnchor.currentContext!).bottomRight,
        entries: [
          MMMenuItem(
            hasCard ? l.locateCard : l.addToMapAction,
            capabilities.excerpt
                ? () => _run(hasCard ? ReaderSelectionCommand.locateCard : ReaderSelectionCommand.excerpt)
                : null,
          ),
          if (!isArea && MMPlatformCapabilities.current.assistant)
            MMMenuItem(l.vocabularyTranslate, capabilities.translate ? _translate : null),
          MMMenuItem(
            isHighlight ? l.deleteHighlight : l.addNote,
            capabilities.excerpt
                ? () => _run(isHighlight ? ReaderSelectionCommand.deleteHighlight : ReaderSelectionCommand.note)
                : null,
          ),
          MMMenuItem(
            l.marginNoteAction,
            capabilities.marginNotes ? () => _run(ReaderSelectionCommand.marginNote) : null,
          ),
        ],
      );
    } finally {
      _paletteOpen = false;
      if (mounted) _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final controller = ref.read(workspaceProvider(widget.studySetId).notifier);
    final capabilities = controller.activeCapabilities;
    final content = ref.watch(workspaceProvider(widget.studySetId).select((s) => s.content));
    final annotation = switch (widget.pending) {
      PendingHighlight(:final annotationId) => content?.annotation(annotationId),
      _ => null,
    };
    final isHighlight = widget.pending is PendingHighlight;
    final existingCard = annotation == null ? null : content?.cardForAnnotation(annotation.id);
    final hasCard =
        existingCard != null &&
        content!.node(existingCard.id, mapId: ref.watch(workspaceProvider(widget.studySetId)).activeMapId) != null;
    // An area excerpt has no text to copy.
    final isArea = annotation != null && annotation.quote.isEmpty;
    final c = context.mmColors;
    final compact = MMSizeClass.of(context) == MMSizeClass.compact;
    return TapRegion(
      groupId: annotationTapGroup(widget.studySetId),
      onTapOutside: (_) {
        if (!_busy && !_paletteOpen) {
          _dismiss();
        } else if (!_busy) {
          // Palette outside handlers run in the same pointer dispatch. Wait
          // for their close callbacks before dismissing the shared selection.
          Future<void>.microtask(() {
            if (mounted && !_busy && !_paletteOpen) _dismiss();
          });
        }
      },
      child: Actions(
        actions: {
          ReaderSelectionIntent: CallbackAction<ReaderSelectionIntent>(
            onInvoke: (intent) {
              _run(intent.command);
              return null;
            },
          ),
        },
        child: Shortcuts(
          shortcuts: readerSelectionShortcuts,
          child: CallbackShortcuts(
            bindings: {const SingleActivator(LogicalKeyboardKey.escape): _dismiss},
            child: Focus(
              focusNode: _focus,
              child: MMFloatingToolbar(
                children: [
                  TextAnnotationTools(
                    onApplied: _dismiss,
                    enabled: capabilities.annotate,
                    studySetId: widget.studySetId,
                    colorOnly: isArea,
                    onOpenChanged: (open) {
                      _paletteOpen = open;
                      if (!open) _focus.requestFocus();
                    },
                  ),
                  const MMToolbarDivider(),
                  if (!isArea)
                    MMToolbarButton(
                      icon: MMIcons.copy,
                      tooltip: l.copyAction,
                      onPressed: capabilities.selectText ? () => _run(ReaderSelectionCommand.copy) : null,
                    ),
                  if (!compact)
                    MMToolbarButton(
                      key: const ValueKey('selection-margin-note'),
                      icon: MMIcons.quoteBubble,
                      tooltip: '${l.marginNoteAction}（C）',
                      onPressed: capabilities.marginNotes ? () => _run(ReaderSelectionCommand.marginNote) : null,
                    ),
                  if (!compact)
                    MMToolbarButton(
                      icon: isHighlight ? MMIcons.trash : MMIcons.addNote,
                      tooltip: isHighlight
                          ? (annotation?.kind == AnnotationKind.underline ? l.deleteUnderline : l.deleteHighlight)
                          : l.addNote,
                      onPressed: (isHighlight ? capabilities.annotate : capabilities.excerpt)
                          ? () =>
                                _run(isHighlight ? ReaderSelectionCommand.deleteHighlight : ReaderSelectionCommand.note)
                          : null,
                    ),
                  if (!compact)
                    MMToolbarButton(
                      icon: MMIcons.network,
                      tooltip: hasCard ? l.locateCard : l.addToMapAction,
                      onPressed: capabilities.excerpt
                          ? () => _run(hasCard ? ReaderSelectionCommand.locateCard : ReaderSelectionCommand.excerpt)
                          : null,
                    ),
                  if (MMPlatformCapabilities.current.assistant && !isArea && !compact)
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        MMToolbarButton(
                          key: const ValueKey('selection-translate'),
                          icon: MMIcons.translate,
                          tooltip:
                              classifyVocabularySelection(
                                    annotation?.quote ??
                                        (widget.pending is PendingSelection
                                            ? (widget.pending as PendingSelection).selection.text
                                            : ''),
                                  ) ==
                                  VocabularySelectionKind.word
                              ? l.vocabularyLookup
                              : l.vocabularyTranslate,
                          selected: _translationOpen,
                          onPressed: capabilities.translate ? _translate : null,
                        ),
                        if ((ref.watch(vocabularyProvider).asData?.value.entries ?? <VocabularyEntry>[]).any(
                          (e) => e.forms.contains(
                            vocabularyKey(
                              selectionTerm(
                                annotation?.quote ??
                                    (widget.pending is PendingSelection
                                        ? (widget.pending as PendingSelection).selection.text
                                        : ''),
                              ),
                            ),
                          ),
                        ))
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              key: const ValueKey('selection-vocabulary-dot'),
                              width: MMSizes.vocabularyDot,
                              height: MMSizes.vocabularyDot,
                              decoration: BoxDecoration(color: c.vocabulary, shape: BoxShape.circle),
                            ),
                          ),
                      ],
                    ),
                  if (compact)
                    MMToolbarButton(
                      key: _moreAnchor,
                      icon: MMIcons.more,
                      tooltip: l.moreTools,
                      onPressed: () => _compactMore(isHighlight, isArea, hasCard),
                    ),
                  if (MMPlatformCapabilities.current.assistant) ...[
                    const MMToolbarDivider(),
                    MMToolbarButton(
                      key: const ValueKey('selection-assistant'),
                      icon: MMIcons.ai,
                      tint: c.research,
                      selected: _quickOpen,
                      tooltip: '${l.askAssistant}（A · ${describeShortcut(AppShortcuts.askAssistant)}）',
                      onPressed: () => _run(ReaderSelectionCommand.assistant),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
