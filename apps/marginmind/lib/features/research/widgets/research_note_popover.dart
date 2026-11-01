import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../../assistant/widgets/assistant_conversations.dart' show openConversation;
import '../../workspace/workspace_controller.dart';
import '../research_controller.dart';

/// The card a research note's mark in the source opens: the note's title,
/// the start of its text and its sources, and where to go from there.
class ResearchNotePopover extends ConsumerStatefulWidget {
  const ResearchNotePopover({
    super.key,
    required this.studySetId,
    required this.attachmentId,
    this.onDismiss,
    this.autofocus = true,
  });

  final String studySetId;
  final String attachmentId;
  final VoidCallback? onDismiss;
  final bool autofocus;

  @override
  ConsumerState<ResearchNotePopover> createState() => _ResearchNotePopoverState();
}

class _ResearchNotePopoverState extends ConsumerState<ResearchNotePopover> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  void _dismiss() => (widget.onDismiss ?? ref.read(workspaceProvider(widget.studySetId).notifier).dismissPending)();

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.escape) return false;
    _dismiss();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    ref.watch(workspaceContentProvider(widget.studySetId));
    final workspace = ref.read(workspaceProvider(widget.studySetId).notifier);
    final dismiss = _dismiss;
    final content = workspace.content;
    final attachment = content.noteAttachments.where((a) => a.id == widget.attachmentId).firstOrNull;
    final note = attachment == null ? null : content.researchNote(attachment.noteId);
    if (note == null) return const SizedBox.shrink();
    final sources = {
      for (final r in note.citations) ?content.evidence.where((e) => e.id == r.evidenceId).firstOrNull?.sourceId,
    }.length;
    final mapId = ref.watch(workspaceProvider(widget.studySetId).select((s) => s.activeMapId));
    final inMap = content.cards.any(
      (card) => card.researchNoteId == note.id && content.node(card.id, mapId: mapId) != null,
    );
    final panel = ref.read(researchPanelProvider(widget.studySetId).notifier);
    return TapRegion(
      onTapOutside: (_) => dismiss(),
      child: Focus(
        autofocus: widget.autofocus,
        child: Container(
          key: const ValueKey('research-note-popover'),
          width: 320,
          padding: const EdgeInsets.all(MMSpacing.m),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(MMRadii.card),
            border: Border.all(color: c.hairline, width: 0.5),
            boxShadow: c.sheetShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(MMIcons.research, size: 11, color: c.research),
                  const SizedBox(width: MMSpacing.xs),
                  Text(l.researchCardKind(sources), style: t.subheadline.copyWith(color: c.research)),
                ],
              ),
              const SizedBox(height: MMSpacing.xs + 2),
              Text(note.title, style: t.headline.copyWith(height: 20 / 13)),
              if (note.body.isNotEmpty) ...[
                const SizedBox(height: MMSpacing.xs),
                Text(
                  note.body,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: t.callout.copyWith(fontWeight: FontWeight.w400, color: c.secondaryLabel, height: 18 / 12),
                ),
              ],
              const SizedBox(height: MMSpacing.m),
              Wrap(
                spacing: MMSpacing.xs,
                runSpacing: MMSpacing.xs,
                children: [
                  if (inMap)
                    MMButton(
                      label: l.researchLocateInMap,
                      icon: MMIcons.mindMap,
                      onPressed: () {
                        dismiss();
                        workspace.locateNoteCard(note.id);
                      },
                    ),
                  MMButton(
                    key: const ValueKey('popover-open-note'),
                    label: l.researchCardOpen,
                    onPressed: () {
                      dismiss();
                      panel.showNote(note.id, origin: PanelOrigin.reader);
                    },
                  ),
                  if (note.conversationId case final conversation?)
                    MMButton(
                      key: const ValueKey('popover-ask-more'),
                      label: l.assistantAskMore,
                      variant: MMButtonVariant.plain,
                      onPressed: () {
                        dismiss();
                        openConversation(ref, widget.studySetId, conversation);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
