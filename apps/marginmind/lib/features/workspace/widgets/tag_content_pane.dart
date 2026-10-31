import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../workspace_controller.dart';
import 'workspace_toolbar.dart';

/// A tag is a destination with its own results, rather than a hidden filter
/// on the sidebar. The map stays mounted underneath so Back keeps its view.
class TagContentPane extends ConsumerStatefulWidget {
  const TagContentPane({super.key, required this.studySetId, required this.tag});

  final String studySetId;
  final String tag;

  @override
  ConsumerState<TagContentPane> createState() => _TagContentPaneState();
}

class _TagContentPaneState extends ConsumerState<TagContentPane> {
  final _focus = FocusNode(debugLabel: 'Tag content');

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
    final tag = widget.tag;
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    final provider = workspaceProvider(studySetId);
    final mapId = ref.watch(provider.select((s) => s.activeMapId));
    final content = ref.watch(workspaceContentProvider(studySetId)) ?? StudySetContent.empty;
    final controller = ref.read(provider.notifier);
    final results = content.search('', mapId: mapId, tag: tag);
    final mapTitle = content.map(mapId)?.title ?? '';
    void back() => controller.filterTag(null);

    return Shortcuts(
      shortcuts: const {SingleActivator(LogicalKeyboardKey.escape): DismissIntent()},
      child: Actions(
        actions: {DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) => back())},
        child: FocusTraversalGroup(
          child: Focus(
            focusNode: _focus,
            child: ColoredBox(
              color: c.canvas,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: MMChromeInsets.of(context).top),
                    child: WorkspaceToolbar(
                      label: l.sectionTags,
                      items: [
                        MMToolbarItem(
                          id: 'tag-back',
                          priority: 100,
                          child: MMButton(
                            key: const ValueKey('tag-back-to-map'),
                            icon: MMIcons.chevronLeft,
                            label: l.backToMap,
                            onPressed: back,
                          ),
                          menuEntry: MMDropdownItem<VoidCallback>(value: back, child: Text(l.backToMap)),
                        ),
                      ],
                      menuEntries: const [],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        MMSpacing.l,
                        MMSpacing.l,
                        MMSpacing.l,
                        MMChromeInsets.of(context).bottom,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Semantics(
                            header: true,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(MMIcons.tag, size: MMSpacing.xl, color: c.accent),
                                const SizedBox(width: MMSpacing.m),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Tooltip(
                                        message: tag,
                                        child: Text(tag, style: t.title3, maxLines: 2, overflow: TextOverflow.ellipsis),
                                      ),
                                      const SizedBox(height: MMSpacing.xs),
                                      Text(
                                        l.tagNodesInMap(results.length),
                                        style: t.footnote.copyWith(color: c.secondaryLabel),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: MMSpacing.l),
                          Divider(height: MMSizes.hairline, thickness: MMSizes.hairline, color: c.separator),
                          Expanded(
                            child: results.isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.symmetric(vertical: MMSpacing.xxl),
                                    child: Text(l.tagNoNodes, style: t.body.copyWith(color: c.secondaryLabel)),
                                  )
                                : ListView.builder(
                                    key: ValueKey(('tag-results-list', tag)),
                                    padding: const EdgeInsets.only(bottom: MMSpacing.l),
                                    itemCount: results.length,
                                    itemBuilder: (context, index) {
                                      final card = results[index];
                                      final title = switch (card.kind) {
                                        CardKind.research =>
                                          content.researchNote(card.researchNoteId ?? '')?.title ?? '',
                                        _ => notePlainText(card.title, card.textFormat),
                                      };
                                      final label = title.isNotEmpty
                                          ? title
                                          : content.annotation(card.annotationId ?? '')?.quote ??
                                                switch (card.kind) {
                                                  CardKind.image => l.imageExcerpt,
                                                  CardKind.excerpt => l.untitledExcerpt,
                                                  CardKind.note || CardKind.research => l.newNoteText,
                                                  CardKind.topic => l.newTopicName,
                                                };
                                      final path = [
                                        mapTitle.isEmpty ? l.mainMap : mapTitle,
                                        ...content.pathOf(card.id, mapId: mapId),
                                      ].join(' › ');
                                      return Column(
                                        children: [
                                          _TagResultRow(
                                            key: ValueKey('tag-result-${card.id}'),
                                            card: card,
                                            title: label,
                                            path: path,
                                            onTap: () => controller.revealAnchor(
                                              SourceAnchor(
                                                mapId: mapId,
                                                target: CardTarget(cardId: card.id),
                                              ),
                                            ),
                                          ),
                                          Divider(
                                            height: MMSizes.hairline,
                                            thickness: MMSizes.hairline,
                                            color: c.separator,
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TagResultRow extends StatelessWidget {
  const _TagResultRow({super.key, required this.card, required this.title, required this.path, required this.onTap});

  final Card card;
  final String title, path;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;
    return MMInteractive(
      semanticLabel: '$title, $path, ${l.viewInMap}',
      tooltip: l.viewInMap,
      onTap: onTap,
      builder: (context, state) => Container(
        padding: const EdgeInsets.symmetric(vertical: MMSpacing.m),
        decoration: BoxDecoration(
          color: state.hovered || state.pressed ? c.hover : null,
          borderRadius: BorderRadius.circular(MMRadii.row),
          border: state.focused ? Border.all(color: c.accent, width: MMSizes.nodeStroke) : null,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              Container(
                width: MMSpacing.xxl,
                height: MMSpacing.xxl,
                decoration: BoxDecoration(color: c.fill, borderRadius: BorderRadius.circular(MMRadii.row)),
                child: Icon(
                  switch (card.kind) {
                    CardKind.topic => MMIcons.network,
                    CardKind.excerpt => MMIcons.quoteBubble,
                    CardKind.image => MMIcons.image,
                    CardKind.note => MMIcons.studyNote,
                    CardKind.research => MMIcons.research,
                  },
                  size: MMSizes.dropdownIcon,
                  color: c.label,
                ),
              ),
              const SizedBox(width: MMSpacing.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.headline, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: MMSpacing.xs),
                    Text(
                      path,
                      style: t.footnote.copyWith(color: c.secondaryLabel),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: MMSpacing.m),
              if (constraints.maxWidth >= MMSizes.dropdownWideWidth) ...[
                Text(l.viewInMap, style: t.callout.copyWith(color: c.secondaryLabel)),
                const SizedBox(width: MMSpacing.m),
              ],
              Icon(MMIcons.chevronRight, size: MMSizes.dropdownIcon, color: c.secondaryLabel),
            ],
          ),
        ),
      ),
    );
  }
}
