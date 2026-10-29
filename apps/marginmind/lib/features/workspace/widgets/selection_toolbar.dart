import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../../app/app_commands.dart';
import '../../assistant/assistant_scope.dart' show selectionContext;
import '../../assistant/widgets/assistant_quick_actions.dart';
import '../../assistant/widgets/assistant_overlays.dart' show boundsOf;
import '../../../shared/l10n.dart';
import '../workspace_controller.dart';
import '../reader_margin.dart';
import 'notices.dart';
import 'highlight_color_button.dart';
import 'selection_translation.dart';

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

  Future<void> _ask(String documentId, List<AnnotationPage> pages, String quote) async {
    if (pages.isEmpty || quote.trim().isEmpty) return;
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
      passage: selectionContext(documentId: documentId, page: pages.first.page, quote: quote),
      source: SourceAnchor(
        target: PdfTarget(documentId: documentId, pages: pages, quote: quote),
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

  Future<void> _run(ReaderSelectionCommand command, [MMAnnotationColor? color]) async {
    if (_busy) return;
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
        final pages = annotation?.pages ?? selection!.pages;
        await pdf.ensureVisible(pages.first.page, pages.first.rects.first);
        await margin.start(
          annotation?.documentId ?? (pending as PendingSelection).documentId,
          pages: annotation?.pages ?? selection!.pages,
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
              if (annotation.quote.isEmpty) return;
              await _ask(annotation.documentId, annotation.pages, annotation.quote);
              return;
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
        await _ask(pending.documentId, pending.selection.pages, pending.selection.text);
        return;
      }
      if (command == ReaderSelectionCommand.note) {
        // The note is typed on its card in the map; the selection is done.
        await controller.excerptAndEditNote(pending.documentId, pending.selection, selectedColor);
        await pdf.clearSelection();
        return;
      }
      if (command == ReaderSelectionCommand.copy) {
        await Clipboard.setData(ClipboardData(text: pending.selection.text));
        if (!mounted) return;
        MMHud.show(context, context.l10n.copiedHud);
        controller.dismissPending();
      } else {
        final notice = command == ReaderSelectionCommand.highlight
            ? await controller.highlight(pending.documentId, pending.selection, selectedColor)
            : await controller.excerpt(pending.documentId, pending.selection, selectedColor);
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
    final pages = annotation?.pages ?? selection?.pages ?? [];
    if (quote.trim().isEmpty || pages.isEmpty) return;
    final layout = context.findAncestorRenderObjectOfType<RenderCustomSingleChildLayoutBox>();
    if (layout == null) return;
    final origin = layout.localToGlobal(Offset.zero);
    final rect = pending is PendingHighlight ? pending.viewportRect : selection?.viewportRect ?? Rect.zero;
    _busy = true;
    setState(() => _translationOpen = true);
    try {
      await showSelectionTranslation(
        context,
        studySetId: widget.studySetId,
        paragraph: TranslationParagraph(
          documentId: annotation?.documentId ?? (pending as PendingSelection).documentId,
          page: pages.first.page,
          index: 0,
          text: quote,
          fingerprint: '',
          rects: pages.first.rects,
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
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
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
    final color = annotation == null
        ? ref.watch(workspaceProvider(widget.studySetId).select((s) => s.color))
        : MMAnnotationColor.fromIndex(annotation.colorIndex);
    final c = context.mmColors;
    return TapRegion(
      onTapOutside: (_) {
        if (!_busy && !_paletteOpen) _dismiss();
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
                  HighlightColorButton(
                    color: color,
                    onOpenChanged: (open) {
                      _paletteOpen = open;
                      if (!open) _focus.requestFocus();
                    },
                    onChanged: (color) => _run(ReaderSelectionCommand.highlight, color),
                  ),
                  const MMToolbarDivider(),
                  if (!isArea)
                    MMToolbarButton(
                      icon: MMIcons.copy,
                      tooltip: l.copyAction,
                      onPressed: () => _run(ReaderSelectionCommand.copy),
                    ),
                  MMToolbarButton(
                    key: const ValueKey('selection-margin-note'),
                    icon: MMIcons.quoteBubble,
                    tooltip: '${l.marginNoteAction}（C）',
                    onPressed: () => _run(ReaderSelectionCommand.marginNote),
                  ),
                  MMToolbarButton(
                    icon: isHighlight ? MMIcons.trash : MMIcons.addNote,
                    tooltip: isHighlight ? l.deleteHighlight : l.addNote,
                    onPressed: () =>
                        _run(isHighlight ? ReaderSelectionCommand.deleteHighlight : ReaderSelectionCommand.note),
                  ),
                  MMToolbarButton(
                    icon: MMIcons.mindMap,
                    tooltip: hasCard ? l.locateCard : l.addToMapAction,
                    onPressed: () => _run(hasCard ? ReaderSelectionCommand.locateCard : ReaderSelectionCommand.excerpt),
                  ),
                  if (MMPlatformCapabilities.current.assistant && !isArea)
                    MMToolbarButton(
                      key: const ValueKey('selection-translate'),
                      icon: MMIcons.translate,
                      tooltip: l.selectionTranslate,
                      selected: _translationOpen,
                      onPressed: _translate,
                    ),
                  if (MMPlatformCapabilities.current.assistant && !isArea) ...[
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
