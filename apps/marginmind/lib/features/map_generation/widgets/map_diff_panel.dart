import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../../shared/l10n.dart';
import '../../workspace/workspace_controller.dart';
import '../../workspace/widgets/notices.dart' show showRenameSheet;
import '../map_generation_controller.dart';

final mapDiffFocusProvider = NotifierProvider.autoDispose.family<MapDiffFocus, String?, String>(MapDiffFocus.new);

class MapDiffFocus extends Notifier<String?> {
  MapDiffFocus(this.studySetId);
  final String studySetId;
  @override
  String? build() => null;
  void select(String id) => state = id;
}

class MapDiffPanel extends ConsumerStatefulWidget {
  const MapDiffPanel({super.key, required this.studySetId, required this.onApply, this.scrollController});
  final String studySetId;
  final VoidCallback onApply;
  final ScrollController? scrollController;
  @override
  ConsumerState<MapDiffPanel> createState() => _MapDiffPanelState();
}

class _MapDiffPanelState extends ConsumerState<MapDiffPanel> {
  final _keys = <String, GlobalKey>{};
  final _focus = FocusNode();
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = ref.watch(mapGenerationControllerProvider(widget.studySetId));
    if (preview == null) return const SizedBox.shrink();
    final ctl = ref.read(mapGenerationControllerProvider(widget.studySetId).notifier);
    final content = ref.read(workspaceProvider(widget.studySetId).notifier).content;
    final selected = ref.watch(mapDiffFocusProvider(widget.studySetId));
    ref.listen(mapDiffFocusProvider(widget.studySetId), (_, id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final row = _keys[id]?.currentContext;
        if (row != null) Scrollable.ensureVisible(row, alignment: .5);
      });
    });
    final l = context.l10n;
    final colors = context.mmColors;
    String title(String? id) => id?.startsWith('new:') == true
        ? preview.lines.where((l) => l.id == id!.substring(4)).firstOrNull?.title ?? preview.request.title
        : content.card(id ?? '')?.title ?? preview.request.title;
    final protected = content.nodes
        .where((n) => n.mapId == preview.request.mapId && isMapNodeProtected(content, n.mapId, n.cardId))
        .length;
    final groups = [
      (l.mapDiffAdded, {MapLineKind.add, MapLineKind.excerpt}),
      (l.mapDiffRenamed, {MapLineKind.rename}),
      (l.mapDiffMoved, {MapLineKind.move}),
      (l.mapDiffRemoved, {MapLineKind.remove}),
    ];
    final ordered = [for (final group in groups) ...preview.lines.where((line) => group.$2.contains(line.kind))];
    final focused = ordered.where((line) => line.id == selected).firstOrNull ?? ordered.firstOrNull;
    void navigate(int direction) {
      if (ordered.isEmpty) return;
      final index = ordered.indexWhere((line) => line.id == focused?.id);
      ref
          .read(mapDiffFocusProvider(widget.studySetId).notifier)
          .select(ordered[(index + direction) % ordered.length].id);
    }

    Future<void> editLine(MapLine? line) async {
      if (line == null || preview.isApplying || (line.kind != MapLineKind.add && line.kind != MapLineKind.rename)) {
        return;
      }
      final value = await showRenameSheet(context, title: l.renameEllipsis, initial: line.title ?? '');
      if (mounted && value != null) ctl.edit(line.id, value);
    }

    return CallbackShortcuts(
      bindings: {
        primaryShortcut(LogicalKeyboardKey.enter): () {
          if (preview.selectedCount > 0 && !preview.isApplying) widget.onApply();
        },
        const SingleActivator(LogicalKeyboardKey.escape): ctl.discard,
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (preview.selectedCount > 0 && !preview.isApplying) widget.onApply();
        },
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => navigate(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => navigate(-1),
        const SingleActivator(LogicalKeyboardKey.space): () {
          if (focused != null) ctl.toggle(focused.id, !focused.kept);
        },
        const SingleActivator(LogicalKeyboardKey.f2): () => editLine(focused),
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: Semantics(
          scopesRoute: true,
          explicitChildNodes: true,
          label: l.mapUpdateTitle,
          child: Material(
            color: colors.windowBackground,
            shape: RoundedRectangleBorder(side: BorderSide(color: colors.separator)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(MMSpacing.m),
                  child: Text(l.mapUpdateTitle, style: context.mmText.headline),
                ),
                Expanded(
                  child: ListView(
                    controller: widget.scrollController,
                    padding: const EdgeInsets.all(MMSpacing.s),
                    children: [
                      for (final group in groups)
                        if (preview.lines.any((line) => group.$2.contains(line.kind))) ...[
                          Padding(
                            padding: const EdgeInsets.all(MMSpacing.s),
                            child: Text(
                              '${group.$1}  ${preview.lines.where((line) => group.$2.contains(line.kind)).length}',
                              style: context.mmText.subheadline,
                            ),
                          ),
                          for (final line in preview.lines.where((line) => group.$2.contains(line.kind)))
                            Container(
                              key: _keys.putIfAbsent(line.id, () => GlobalKey()),
                              color: selected == line.id ? colors.selectedRow : null,
                              child: InkWell(
                                onTap: () {
                                  ref.read(mapDiffFocusProvider(widget.studySetId).notifier).select(line.id);
                                  _focus.requestFocus();
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(MMSpacing.s),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      MMCheckbox(
                                        value: line.kept,
                                        color: colors.research,
                                        semanticLabel: line.title ?? title(line.nodeId),
                                        onChanged: preview.isApplying ? null : (value) => ctl.toggle(line.id, value),
                                      ),
                                      const SizedBox(width: MMSpacing.s),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              line.title ??
                                                  (line.kind == MapLineKind.excerpt
                                                      ? l.mapDiffExcerpt(
                                                          content.annotation(line.annotationId ?? '')?.quote ?? '',
                                                        )
                                                      : title(line.nodeId)),
                                              style: context.mmText.body,
                                            ),
                                            if (line.kind == MapLineKind.rename)
                                              Text(
                                                title(line.nodeId),
                                                style: context.mmText.footnote.copyWith(
                                                  decoration: TextDecoration.lineThrough,
                                                ),
                                              ),
                                            if (line.kind == MapLineKind.move)
                                              Text(
                                                l.mapDiffMoveRoute(
                                                  title(
                                                    content.nodes
                                                        .where(
                                                          (n) =>
                                                              n.mapId == preview.request.mapId &&
                                                              n.cardId == line.nodeId,
                                                        )
                                                        .firstOrNull
                                                        ?.parentId,
                                                  ),
                                                  title(line.parentId),
                                                ),
                                                style: context.mmText.footnote,
                                              ),
                                            if (line.reason != null) Text(line.reason!, style: context.mmText.footnote),
                                          ],
                                        ),
                                      ),
                                      if (line.source != null)
                                        Text('p.${line.source!.page}', style: context.mmText.footnote),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      Padding(
                        padding: const EdgeInsets.all(MMSpacing.s),
                        child: Text(l.mapUpdateProtected(protected), style: context.mmText.footnote),
                      ),
                      if (preview.failure != null)
                        Text(l.assistantErrorFailed, style: context.mmText.footnote.copyWith(color: colors.critical)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(MMSpacing.s),
                  child: Wrap(
                    spacing: MMSpacing.s,
                    runSpacing: MMSpacing.s,
                    children: [
                      MMButton(
                        label: l.mapIdeaRegenerate,
                        onPressed: preview.isApplying ? null : () => ctl.regenerate(),
                      ),
                      MMButton(label: l.mapIdeaDiscard, onPressed: preview.isApplying ? null : ctl.discard),
                      MMButton(
                        key: const ValueKey('map-update-apply'),
                        label: l.mapUpdateApply(preview.selectedCount),
                        variant: MMButtonVariant.primary,
                        onPressed: preview.selectedCount == 0 || preview.isApplying ? null : widget.onApply,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
