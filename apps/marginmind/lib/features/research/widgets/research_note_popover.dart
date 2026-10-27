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
class ResearchNotePopover extends ConsumerWidget {
  const ResearchNotePopover({super.key, required this.studySetId, required this.attachmentId});

  final String studySetId;
  final String attachmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    ref.watch(workspaceContentProvider(studySetId));
    final workspace = ref.read(workspaceProvider(studySetId).notifier);
    final content = workspace.content;
    final attachment = content.noteAttachments.where((a) => a.id == attachmentId).firstOrNull;
    final note = attachment == null ? null : content.researchNote(attachment.noteId);
    if (note == null) return const SizedBox.shrink();
    final sources = {
      for (final r in note.citations) ?content.evidence.where((e) => e.id == r.evidenceId).firstOrNull?.sourceId,
    }.length;
    final mapId = ref.watch(workspaceProvider(studySetId).select((s) => s.activeMapId));
    final inMap = content.cards.any(
      (card) => card.researchNoteId == note.id && content.node(card.id, mapId: mapId) != null,
    );
    final panel = ref.read(researchPanelProvider(studySetId).notifier);
    return TapRegion(
      onTapOutside: (_) => workspace.dismissPending(),
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): workspace.dismissPending},
        child: Focus(
          autofocus: true,
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
                        onPressed: () => workspace.locateNoteCard(note.id),
                      ),
                    MMButton(
                      key: const ValueKey('popover-open-note'),
                      label: l.researchCardOpen,
                      onPressed: () {
                        workspace.dismissPending();
                        panel.showNote(note.id, origin: PanelOrigin.reader);
                      },
                    ),
                    if (note.conversationId case final conversation?)
                      MMButton(
                        key: const ValueKey('popover-ask-more'),
                        label: l.assistantAskMore,
                        variant: MMButtonVariant.plain,
                        onPressed: () {
                          workspace.dismissPending();
                          openConversation(ref, studySetId, conversation);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
