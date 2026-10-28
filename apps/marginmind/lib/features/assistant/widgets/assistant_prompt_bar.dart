import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../assistant_controller.dart';
import '../assistant_entry.dart';
import '../assistant_scope.dart';
import 'assistant_context_summary.dart';

/// The current context and direct actions stay in one place. Other skills
/// remain available from the input menu and slash commands.
class AssistantPromptBar extends ConsumerWidget {
  const AssistantPromptBar({super.key, required this.studySetId, this.enabled = true});
  final String studySetId;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.mmColors;
    final ui = ref.watch(assistantUiProvider(studySetId));
    final auto = ref.watch(assistantAutoContextsProvider(studySetId));
    final conversation = ref.watch(assistantControllerProvider);
    final outgoing = outgoingContexts(ui, auto);
    final items = [
      ...ui.contexts,
      for (final item in auto)
        if (!ui.contexts.any(
          (c) =>
              c.kind == item.kind && c.documentId == item.documentId && c.page == item.page && c.nodeId == item.nodeId,
        ))
          item,
    ];
    final busy = !enabled || conversation.running || ref.watch(assistantBackgroundProvider) != null;
    final notifier = ref.read(assistantUiProvider(studySetId).notifier);
    return Padding(
      key: const ValueKey('assistant-suggestions'),
      padding: const EdgeInsets.fromLTRB(MMSpacing.s, MMSpacing.s, MMSpacing.s, MMSpacing.xs),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (items.isNotEmpty)
            AssistantContextSummary(
              key: ValueKey('prompt-contexts-${conversation.id}-${conversation.messages.length}'),
              items: items,
              outgoing: outgoing,
              onChange: (item) => item.auto ? notifier.toggleAuto(item.id) : notifier.removeContext(item.id),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: MMSpacing.xs),
            child: Wrap(
              spacing: MMSpacing.s,
              runSpacing: MMSpacing.xs,
              children: [
                for (final skill in [AssistantSkill.explain, AssistantSkill.verify, AssistantSkill.organize])
                  MMInteractive(
                    key: ValueKey('quick-${skill.name}'),
                    semanticLabel: skill.label(l),
                    tooltip: skill.prompt(l),
                    onTap: busy || outgoing.isEmpty
                        ? null
                        : () => assistantSend(ref, studySetId, l, skill.prompt(l), skill: skill.name),
                    builder: (context, state) => Opacity(
                      opacity: state.enabled ? 1 : .4,
                      child: Container(
                        height: MMSizes.field,
                        padding: const EdgeInsets.symmetric(horizontal: MMSpacing.m),
                        decoration: BoxDecoration(
                          color: state.hovered || state.focused ? c.researchTint : c.card,
                          border: Border.all(color: state.hovered || state.focused ? c.research : c.separator),
                          borderRadius: BorderRadius.circular(MMRadii.capsule),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(skill.icon, size: 13, color: c.research),
                            const SizedBox(width: MMSpacing.xs),
                            Text(
                              skill == AssistantSkill.organize ? l.assistantSkillOrganizeShort : skill.label(l),
                              style: context.mmText.callout.copyWith(color: c.label),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
