import 'package:flutter/services.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../workspace_controller.dart';
import 'right_panel.dart';

/// Tags browse all maps in a right drawer, without replacing the main subject.
class TagContentPane extends ConsumerStatefulWidget {
  const TagContentPane({super.key, required this.studySetId, this.tag});
  final String studySetId;
  final String? tag;

  @override
  ConsumerState<TagContentPane> createState() => _TagContentPaneState();
}

class _TagContentPaneState extends ConsumerState<TagContentPane> {
  final _focus = FocusNode(debugLabel: 'Tag results');
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

  @override
  Widget build(BuildContext context) {
    final studySetId = widget.studySetId;
    final state = ref.watch(workspaceProvider(studySetId));
    final owner = ref.read(workspaceProvider(studySetId).notifier);
    final content = state.content ?? StudySetContent.empty;
    final selected = state.tagFilter ?? widget.tag;
    final counts = <String, int>{};
    for (final map in content.maps) {
      for (final entry in content.tagCounts(mapId: map.id).entries) {
        counts.update(entry.key, (n) => n + entry.value, ifAbsent: () => entry.value);
      }
    }
    final tags = counts.keys.toList()..sort();
    final results = [
      for (final map in content.maps)
        for (final card in content.search('', mapId: map.id, tag: selected))
          if (selected != null || card.tags.isNotEmpty) (map: map, card: card),
    ];
    final c = context.mmColors;
    final l = context.l10n;
    return Shortcuts(
      shortcuts: const {SingleActivator(LogicalKeyboardKey.escape): DismissIntent()},
      child: Actions(
        actions: {DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) => owner.closePanel())},
        child: Focus(
          focusNode: _focus,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RightPanelHeader(icon: MMIcons.tag, title: l.sectionTags, onClose: owner.closePanel),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(MMSpacing.l),
                  children: [
                    Wrap(
                      spacing: MMSpacing.s,
                      runSpacing: MMSpacing.s,
                      children: [
                        for (final value in tags)
                          MMButton(
                            key: ValueKey('tag-filter-$value'),
                            label: value,
                            variant: value.toLowerCase() == selected?.toLowerCase()
                                ? MMButtonVariant.primary
                                : MMButtonVariant.secondary,
                            onPressed: () => owner.filterTag(value),
                          ),
                      ],
                    ),
                    const SizedBox(height: MMSpacing.l),
                    Text(
                      l.workspaceTagMatches(results.length),
                      style: context.mmText.footnote.copyWith(color: c.secondaryLabel),
                    ),
                    const SizedBox(height: MMSpacing.s),
                    if (results.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: MMSpacing.xl),
                        child: Text(l.tagNoNodes, style: context.mmText.body.copyWith(color: c.secondaryLabel)),
                      ),
                    for (final result in results) ...[
                      MMInteractive(
                        key: ValueKey('tag-result-${result.map.id}-${result.card.id}'),
                        semanticLabel: notePlainText(result.card.title, result.card.textFormat),
                        onTap: () => owner.revealTagTopic(result.map.id, result.card.id),
                        builder: (context, interaction) => Container(
                          color: interaction.hovered ? c.hover : null,
                          padding: const EdgeInsets.symmetric(vertical: MMSpacing.l),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(MMIcons.mindMap, size: 18, color: c.accent),
                              const SizedBox(width: MMSpacing.m),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      notePlainText(result.card.title, result.card.textFormat).isNotEmpty
                                          ? notePlainText(result.card.title, result.card.textFormat)
                                          : content.annotation(result.card.annotationId ?? '')?.quote ??
                                                l.untitledExcerpt,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: context.mmText.headline,
                                    ),
                                    const SizedBox(height: MMSpacing.s),
                                    if (content.document(
                                          result.card.source?.documentId ??
                                              content.annotation(result.card.annotationId ?? '')?.documentId ??
                                              '',
                                        )
                                        case final document?)
                                      Text(
                                        document.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: context.mmText.footnote.copyWith(color: c.secondaryLabel),
                                      ),
                                    Text(
                                      [
                                        result.map.title.isEmpty ? l.mainMap : result.map.title,
                                        ...content.pathOf(result.card.id, mapId: result.map.id),
                                      ].join(' › '),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: context.mmText.footnote.copyWith(color: c.secondaryLabel),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(MMIcons.chevronRight, size: 14, color: c.secondaryLabel),
                            ],
                          ),
                        ),
                      ),
                      Divider(height: 1, color: c.separator),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
