import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../workspace_controller.dart';
import 'card_details.dart';

/// The right panel: research or the selected card's details, one at a time.
/// Esc closes it unless a field inside uses the key first.
///
/// It appears and goes at once, like the split view's layouts: while its
/// width animated, the panes beside it would pass through the narrow-window
/// fallbacks (the map briefly hidden).
class RightPanelView extends ConsumerWidget {
  const RightPanelView({super.key, required this.studySetId});

  final String studySetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mmColors;
    final provider = workspaceProvider(studySetId);
    final panel = ref.watch(provider.select((s) => s.panel));
    final controller = ref.read(provider.notifier);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): controller.closePanel},
      child: FocusTraversalGroup(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.windowBackground,
            border: Border(left: BorderSide(color: c.separator)),
          ),
          child: switch (panel) {
            RightPanel.details => CardDetails(studySetId: studySetId),
            RightPanel.research || null => ResearchPanel(onClose: controller.closePanel),
          },
        ),
      ),
    );
  }
}

/// The panel's top row: what it shows, in [color], and a close button.
class RightPanelHeader extends StatelessWidget {
  const RightPanelHeader({super.key, required this.icon, required this.title, required this.onClose, this.color});

  final IconData icon;
  final String title;
  final VoidCallback onClose;

  /// Defaults to the secondary label color.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final tint = color ?? c.secondaryLabel;
    return Container(
      height: MMSizes.toolbarGroupHeight + MMSpacing.s,
      padding: const EdgeInsets.only(left: MMSpacing.l, right: MMSpacing.s),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.separator)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 13, color: tint),
          const SizedBox(width: MMSpacing.xs + 1),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.subheadline.copyWith(color: tint),
            ),
          ),
          MMIconButton(icon: MMIcons.close, tooltip: context.l10n.closePanel, iconSize: 13, onPressed: onClose),
        ],
      ),
    );
  }
}

/// Research: for now the shell and its empty state. Sessions, the launcher
/// and saving arrive with the research flow.
class ResearchPanel extends StatelessWidget {
  const ResearchPanel({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RightPanelHeader(icon: MMIcons.research, title: l.research, color: c.research, onClose: onClose),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(MMSpacing.xl),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(MMIcons.research, size: 32, color: c.research),
                  const SizedBox(height: MMSpacing.m),
                  Text(
                    l.researchEmptyTitle,
                    textAlign: TextAlign.center,
                    style: context.mmText.headline.copyWith(color: c.secondaryLabel),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
