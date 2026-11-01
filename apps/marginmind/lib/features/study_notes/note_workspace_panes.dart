import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../../shared/l10n.dart';
import '../workspace/workspace_controller.dart';
import '../workspace/phone_reader_controls_controller.dart';
import '../workspace/widgets/map_pane.dart';
import '../workspace/widgets/reader_pane.dart';
import '../workspace/widgets/workspace_toolbar.dart';
import 'note_view.dart';

/// Notes own the page. Sources share its right edge only when requested.
class NoteWorkspacePanes extends ConsumerWidget {
  const NoteWorkspacePanes({super.key, required this.studySetId, required this.noteId});
  final String studySetId, noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = workspaceProvider(studySetId);
    final reference = ref.watch(provider.select((s) => s.noteReference));
    final fraction = ref.watch(provider.select((s) => s.noteSplitFraction));
    final owner = ref.read(provider.notifier);
    final c = context.mmColors;
    final phoneHeader = usePhoneReaderControls(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        const minNote = 400.0, minReference = 400.0;
        final split = reference != null && constraints.maxWidth >= minNote + minReference + 1;
        final noteWidth = split
            ? MMSplitView.primaryWidth(constraints.maxWidth, fraction, minNote, minReference)
            : constraints.maxWidth;
        final referenceWidth = split ? constraints.maxWidth - noteWidth - 1 : constraints.maxWidth;
        final close = MMToolbarItem(
          id: 'note-reference-close',
          priority: 100,
          child: MMToolbarButton(
            key: const ValueKey('note-reference-close'),
            icon: MMIcons.close,
            tooltip: context.l10n.closePanel,
            onPressed: owner.closeNoteReference,
          ),
          menuEntry: MMDropdownItem<VoidCallback>(
            value: owner.closeNoteReference,
            child: Text(context.l10n.closePanel),
          ),
        );
        return Stack(
          key: const ValueKey('note-workspace'),
          children: [
            Positioned(
              top: 0,
              bottom: 0,
              left: 0,
              width: noteWidth,
              child: ExcludeFocus(
                excluding: reference != null && !split,
                child: StudyNoteView(studySetId: studySetId, noteId: noteId),
              ),
            ),
            if (reference != null)
              Positioned(
                key: const ValueKey('note-reference-pane'),
                top: 0,
                bottom: 0,
                right: 0,
                width: referenceWidth,
                child: WorkspaceToolbarScope(
                  actions: phoneHeader ? const [] : [close],
                  leading: null,
                  ownsActions: true,
                  ownsLeading: false,
                  useGeometry: false,
                  child: ColoredBox(
                    color: c.windowBackground,
                    child: Column(
                      children: [
                        if (phoneHeader)
                          MMToolbar.content(
                            semanticLabel: context.l10n.notesTitle,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: MMSpacing.m),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      reference == NoteReference.document
                                          ? ref.watch(
                                                  provider.select(
                                                    (s) => s.content?.document(s.activeDocumentId ?? '')?.title,
                                                  ),
                                                ) ??
                                                context.l10n.paneSource
                                          : context.l10n.paneMap,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: context.mmText.headline,
                                    ),
                                  ),
                                  close.child,
                                ],
                              ),
                            ),
                          ),
                        Expanded(
                          child: reference == NoteReference.document
                              ? ReaderPane(studySetId: studySetId)
                              : MapPane(studySetId: studySetId),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (split)
              Positioned(
                left: noteWidth + .5 - context.mmDividerHit / 2,
                top: 0,
                bottom: 0,
                width: context.mmDividerHit,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: GestureDetector(
                    key: const ValueKey('note-reference-divider'),
                    behavior: HitTestBehavior.opaque,
                    onDoubleTap: () => owner.setNoteSplitFraction(.55),
                    onHorizontalDragUpdate: (event) {
                      final width = MMSplitView.primaryWidth(
                        constraints.maxWidth,
                        (noteWidth + event.delta.dx) / constraints.maxWidth,
                        minNote,
                        minReference,
                      );
                      owner.setNoteSplitFraction(width / constraints.maxWidth);
                    },
                    child: Center(
                      child: Container(width: MMSizes.hairline, color: c.separator),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
