import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../../../app/app_commands.dart';
import '../../../shared/l10n.dart';
import '../../study_notes/note_setup_sheet.dart';
import '../workspace_controller.dart';

List<PopupMenuEntry<VoidCallback>> workspaceMenuEntries(BuildContext context, WidgetRef ref, String id) {
  final owner = ref.read(workspaceProvider(id).notifier);
  final state = ref.read(workspaceProvider(id));
  return [
    if (state.tabs.active?.kind == WorkspaceTabKind.note) ...[
      MMDropdownItem(
        value: () => owner.showNoteReference(NoteReference.document),
        enabled: state.activeDocumentId != null,
        child: Text(context.l10n.paneSource),
      ),
      MMDropdownItem(value: () => owner.showNoteReference(NoteReference.map), child: Text(context.l10n.paneMap)),
    ],
    MMDropdownItem(
      key: const ValueKey('workspace-command-organize-note'),
      value: () => showNoteSetupSheet(context, ref, id),
      child: Text(AppShortcuts.tip(context.l10n.organizeNotes, AppShortcuts.organizeStudyNote)),
    ),
  ];
}
