import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../../../app/app_commands.dart';
import '../../../shared/l10n.dart';
import '../workspace_controller.dart';
import 'notices.dart';

/// Travels the shared document/map history, including edits in companions.
class WorkspaceHistoryControls extends ConsumerWidget {
  const WorkspaceHistoryControls({super.key, required this.studySetId, this.compact = false, this.dense = false});

  final String studySetId;
  final bool compact;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(workspaceProvider(studySetId).select((s) => (s.canUndo, s.canRedo)));
    final l = context.l10n;
    Future<void> travel(bool redo) async {
      final owner = ref.read(workspaceProvider(studySetId).notifier);
      final notice = redo ? await owner.redo() : await owner.undo();
      if (context.mounted) showNotice(context, notice, rootTitle: '');
    }

    // Phones expose both directions from one control to leave room for the
    // source/map switch and the assistant at narrow widths.
    if (compact) {
      return MMDropdownButton<bool>(
        key: const ValueKey('workspace-history'),
        tooltip: '${l.undo} / ${l.redo}',
        icon: const Icon(MMIcons.undo),
        enabled: history.$1 || history.$2,
        onSelected: travel,
        itemBuilder: (_) => [
          MMDropdownItem(
            key: const ValueKey('workspace-undo'),
            value: false,
            enabled: history.$1,
            icon: MMIcons.undo,
            child: Text(l.undo),
          ),
          MMDropdownItem(
            key: const ValueKey('workspace-redo'),
            value: true,
            enabled: history.$2,
            icon: MMIcons.redo,
            child: Text(l.redo),
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MMIconButton(
          compact: dense,
          key: const ValueKey('workspace-undo'),
          icon: MMIcons.undo,
          tooltip: AppShortcuts.tip(l.undo, AppShortcuts.undo),
          onPressed: history.$1 ? () => travel(false) : null,
        ),
        MMIconButton(
          compact: dense,
          key: const ValueKey('workspace-redo'),
          icon: MMIcons.redo,
          tooltip: AppShortcuts.tip(l.redo, AppShortcuts.redo),
          onPressed: history.$2 ? () => travel(true) : null,
        ),
      ],
    );
  }
}
