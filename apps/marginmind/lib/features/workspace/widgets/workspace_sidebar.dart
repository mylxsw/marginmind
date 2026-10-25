import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../app/app_commands.dart';
import '../../../app/navigation.dart';
import '../../../app/providers.dart';
import '../../../shared/l10n.dart';
import '../workspace_controller.dart';
import 'notices.dart';

/// Study set sidebar: back to the library, search, then mind maps,
/// documents and learning tools. Search filters every section at once.
class WorkspaceSidebar extends ConsumerWidget {
  const WorkspaceSidebar({super.key, required this.studySetId, required this.searchFocus});

  final String studySetId;
  final FocusNode searchFocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = context.mmText;
    final c = context.mmColors;
    final provider = workspaceProvider(studySetId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final content = ref.watch(contentProvider(studySetId)).value;
    final studySet = ref.watch(studySetProvider(studySetId));
    final documents = content?.documents ?? const [];
    final query = state.sidebarQuery.trim().toLowerCase();
    bool matches(String text) => query.isEmpty || text.toLowerCase().contains(query);

    final maps = [
      if (matches(l.mainMap))
        MMSidebarItem(
          icon: MMIcons.mindMap,
          label: l.mainMap,
          selected: true,
          trailing: MMCount(content?.cardCount ?? 0),
          onTap: () => controller.setLayout(MMSplitMode.secondary),
        ),
    ];
    final docs = [
      for (final d in documents)
        if (matches(d.title))
          MMSidebarItem(
            icon: MMIcons.document,
            label: d.title,
            trailing: MMCount(d.pageCount),
            selected: d.id == state.activeDocumentId,
            onTap: () => controller.openDocument(d.id),
            onContextMenu: (position) => _documentMenu(context, ref, d, position),
          ),
    ];
    final now = ref.watch(clockProvider)();
    final due = content?.dueCount(now) ?? 0;
    final learn = [
      if (matches(l.review))
        MMSidebarItem(
          icon: MMIcons.review,
          label: l.review,
          trailing: due > 0 ? MMBadge('$due', prominent: true) : null,
          onTap: () => ref.read(navigationProvider.notifier).startReview(studySetId),
        ),
    ];
    final hits = content == null ? const <Card>[] : content.search(query).take(50).toList();
    final cards = [
      for (final card in hits)
        MMSidebarItem(
          icon: switch (card.kind) {
            CardKind.topic => MMIcons.addTopic,
            CardKind.excerpt => MMIcons.highlight,
            CardKind.note => MMIcons.addNote,
          },
          label: card.title.isNotEmpty ? card.title : (content!.annotation(card.annotationId ?? '')?.quote ?? ''),
          selected: card.id == state.selectedCardId,
          onTap: () => card.kind == CardKind.excerpt ? controller.revealCard(card.id) : controller.selectCard(card.id),
        ),
    ];
    final empty = maps.isEmpty && docs.isEmpty && learn.isEmpty && cards.isEmpty;

    return MMSidebar(
      topTrailing: MMIconButton(
        icon: MMIcons.sidebar,
        tooltip: AppShortcuts.tip(l.hideSidebar, AppShortcuts.toggleSidebar),
        onPressed: controller.toggleSidebar,
      ),
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MMInteractive(
            onTap: () => ref.read(navigationProvider.notifier).showLibrary(),
            tooltip: AppShortcuts.tip(l.showLibrary, AppShortcuts.showLibrary),
            semanticLabel: l.showLibrary,
            builder: (context, s) => Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: s.hovered ? c.hover : Colors.transparent,
                borderRadius: BorderRadius.circular(MMRadii.row),
              ),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(6)),
                    child: const Icon(MMIcons.studySet, size: 13, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(studySet?.title ?? '', style: t.headline, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  Icon(MMIcons.library, size: 13, color: c.icon),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          MMSearchField(placeholder: l.searchInSet, focusNode: searchFocus, onChanged: controller.setSidebarQuery),
        ],
      ),
      footer: Row(
        children: [
          MMIconButton(
            icon: MMIcons.add,
            tooltip: AppShortcuts.tip(l.importDocument, AppShortcuts.importDocument),
            onPressed: () => pickAndImportDocuments(context, ref, studySetId),
          ),
        ],
      ),
      children: [
        if (empty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(l.noSidebarMatches, textAlign: TextAlign.center, style: t.footnote),
          ),
        if (cards.isNotEmpty) MMSidebarSection(title: l.sectionCards, children: cards),
        if (maps.isNotEmpty) MMSidebarSection(title: l.sectionMaps, children: maps),
        if (docs.isNotEmpty) MMSidebarSection(title: l.sectionDocuments, children: docs),
        if (learn.isNotEmpty) MMSidebarSection(title: l.sectionLearn, children: learn),
      ],
    );
  }

  void _documentMenu(BuildContext context, WidgetRef ref, Document doc, Offset position) {
    final l = context.l10n;
    final controller = ref.read(workspaceProvider(studySetId).notifier);
    showMMMenu(
      context,
      position: position,
      entries: [
        MMMenuItem(l.open, () => controller.openDocument(doc.id)),
        MMMenuItem(l.renameEllipsis, () async {
          final title = await showRenameSheet(context, title: l.renameDocument, initial: doc.title);
          if (title != null) await controller.renameDocument(doc.id, title);
        }),
        const MMMenuDivider(),
        MMMenuItem(l.removeDocumentEllipsis, () async {
          final excerpts = controller.content.annotationsOn(doc.id).length;
          final ok = await showConfirmSheet(
            context,
            title: l.removeDocumentTitle(doc.title),
            message: l.removeDocumentMessage(excerpts),
            confirmLabel: l.remove,
          );
          if (!ok) return;
          final notice = await controller.removeDocument(doc.id);
          if (context.mounted) showNotice(context, notice, rootTitle: '');
        }, destructive: true),
      ],
    );
  }
}
