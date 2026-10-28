import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../../app/app_commands.dart';
import '../../assistant/assistant_entry.dart';
import '../../../shared/l10n.dart';
import '../workspace_controller.dart';
import 'notices.dart';

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
              // The highlight's own place is the anchor; the toolbar is done.
              askAboutPassage(
                ref,
                widget.studySetId,
                documentId: annotation.documentId,
                pages: annotation.pages,
                quote: annotation.quote,
              );
              _dismiss();
              return;
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
        // The context keeps the passage and its place; the selection is done.
        askAboutPassage(
          ref,
          widget.studySetId,
          documentId: pending.documentId,
          pages: pending.selection.pages,
          quote: pending.selection.text,
        );
        _dismiss();
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
    final c = context.mmColors;
    return TapRegion(
      onTapOutside: (_) {
        if (!_busy) _dismiss();
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
                  for (final color in MMAnnotationColor.values)
                    MMFloatingToolbarColor(
                      color: color,
                      tooltip: isHighlight ? l.colorName(color) : l.excerptInColor(l.colorName(color)),
                      selected: isHighlight && annotation?.colorIndex == color.index,
                      onPressed: () => _run(ReaderSelectionCommand.excerpt, color),
                    ),
                  const MMToolbarDivider(),
                  MMToolbarButton(
                    icon: isHighlight ? MMIcons.mindMap : MMIcons.highlight,
                    tooltip: isHighlight ? (hasCard ? l.locateCard : l.addToMapAction) : l.highlightAction,
                    onPressed: () => _run(
                      isHighlight
                          ? (hasCard ? ReaderSelectionCommand.locateCard : ReaderSelectionCommand.excerpt)
                          : ReaderSelectionCommand.highlight,
                    ),
                  ),
                  if (!isArea)
                    MMToolbarButton(
                      icon: MMIcons.copy,
                      tooltip: l.copyAction,
                      onPressed: () => _run(ReaderSelectionCommand.copy),
                    ),
                  MMToolbarButton(
                    icon: isHighlight ? MMIcons.trash : MMIcons.addNote,
                    tooltip: isHighlight ? l.deleteHighlight : l.addNote,
                    onPressed: () =>
                        _run(isHighlight ? ReaderSelectionCommand.deleteHighlight : ReaderSelectionCommand.note),
                  ),
                  if (MMPlatformCapabilities.current.assistant && !isArea) ...[
                    const MMToolbarDivider(),
                    MMToolbarButton(
                      key: const ValueKey('selection-assistant'),
                      icon: MMIcons.ai,
                      tint: c.research,
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
