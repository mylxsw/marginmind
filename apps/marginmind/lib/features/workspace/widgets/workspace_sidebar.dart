import '../document_import.dart';
import '../../../app/document_commands.dart';
import '../../../shared/document_icon.dart';
import '../reader_ocr.dart';
import '../workspace_browser.dart';

import 'package:mm_platform/mm_platform.dart';

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
    ref.watch(
      provider.select((s) => (s.sidebarQuery, s.activeMapId, s.activeDocumentId, s.tagFilter, s.selectedCardId)),
    );
    final state = ref.read(provider);
    final controller = ref.read(provider.notifier);
    final content = ref.watch(workspaceContentProvider(studySetId));
    final studyTitle = ref.watch(studySetProvider(studySetId).select((s) => s?.title));
    final documents = content?.documents ?? const [];
    final query = state.sidebarQuery.trim().toLowerCase();
    bool matches(String text) => query.isEmpty || text.toLowerCase().contains(query);

    final maps = [
      for (final map in content?.maps ?? const <MindMap>[])
        if (matches(map.title.isEmpty ? l.mainMap : map.title))
          MMSidebarItem(
            key: ValueKey('sidebar-map-${map.id}'),
            icon: MMIcons.mindMap,
            label: map.title.isEmpty ? l.mainMap : map.title,
            selected: map.id == state.activeMapId,
            onTap: () async {
              await controller.selectMap(map.id);
              controller.setLayout(MMSplitMode.secondary);
            },
            onContextMenu: (position) => _mapMenu(context, ref, map, position),
          ),
    ];
    final browser = ref.watch(workspaceBrowserProvider(studySetId));
    final browserOwner = ref.read(workspaceBrowserProvider(studySetId).notifier);
    final importing = ref.watch(documentImportsProvider(studySetId));
    final docs = <Widget>[
      for (final d in documents)
        if (matches(d.title))
          MMSidebarItem(
            icon: documentIcon(d),
            label: d.title,
            trailing: d.capabilities().readingSettings
                ? null
                : ref.watch(readerOcrProvider(controller.filePath(d))).document?.hasCopy == true
                ? Text(l.ocrRecognized, style: context.mmText.footnote)
                : MMCount(d.pageCount),
            selected: !browser.visible && d.id == state.activeDocumentId,
            onTap: () {
              browserOwner.hide();
              controller.openDocument(d.id);
            },
            onContextMenu: (position) => _documentMenu(context, ref, d, position),
          ),
      for (final task in importing)
        MMSidebarItem(
          key: ValueKey('import-${task.id}'),
          icon: MMIcons.document,
          label: task.name,
          trailing: const SizedBox(
            width: MMSizes.dropdownIcon,
            height: MMSizes.dropdownIcon,
            child: CircularProgressIndicator(strokeWidth: MMSpacing.xxs),
          ),
          onContextMenu: (position) => showMMMenu(
            context,
            position: position,
            entries: [
              MMMenuItem(l.cancelImport, () => ref.read(documentImportsProvider(studySetId).notifier).cancel(task.id)),
            ],
          ),
        ),
    ];
    if (browser.session case final session?) {
      docs.add(
        ListenableBuilder(
          listenable: session,
          builder: (context, _) => session.disposed
              ? const SizedBox.shrink()
              : Tooltip(
                  message: l.browserUnsaved,
                  child: MMSidebarItem(
                    icon: MMIcons.web,
                    leading: session.loading
                        ? SizedBox.square(
                            dimension: MMSpacing.l,
                            child: CircularProgressIndicator(strokeWidth: MMSpacing.xxs, color: c.secondaryLabel),
                          )
                        : null,
                    labelColor: c.secondaryLabel,
                    label: session.phase == BrowserPhase.loading || session.title.isEmpty
                        ? session.url.host
                        : session.title,
                    selected: browser.visible,
                    onTap: browserOwner.show,
                  ),
                ),
        ),
      );
    }
    final now = ref.watch(clockProvider)();
    final due = content?.dueCount(now, mapId: state.activeMapId) ?? 0;
    final learn = [
      if (matches(l.review))
        MMSidebarItem(
          icon: MMIcons.review,
          label: l.review,
          trailing: due > 0 ? MMBadge('$due', prominent: true) : null,
          onTap: () => ref.read(navigationProvider.notifier).startReview(studySetId, mapId: state.activeMapId),
        ),
      if (content != null && content.reviewLogs.isNotEmpty && matches(l.statistics))
        MMSidebarItem(
          key: const ValueKey('sidebar-statistics'),
          icon: MMIcons.statistics,
          label: l.statistics,
          onTap: () => ref.read(navigationProvider.notifier).showStats(studySetId),
        ),
    ];
    final tagNames = content?.tags(mapId: state.activeMapId) ?? const <String>[];
    // A deleted tag must not leave the results trapped behind a stale filter.
    final tagFilter = tagNames.any((tag) => tag.toLowerCase() == state.tagFilter?.toLowerCase())
        ? state.tagFilter
        : null;
    final tags = [
      if (tagFilter != null)
        MMSidebarItem(icon: MMIcons.tag, label: l.allTags, onTap: () => controller.filterTag(null)),
      for (final tag in tagNames)
        if (matches(tag) || tag == tagFilter)
          MMSidebarItem(
            key: ValueKey('sidebar-tag-$tag'),
            icon: MMIcons.tag,
            label: tag,
            selected: tag.toLowerCase() == tagFilter?.toLowerCase(),
            onTap: () => controller.filterTag(tag.toLowerCase() == tagFilter?.toLowerCase() ? null : tag),
            onContextMenu: content!.dueCount(now, mapId: state.activeMapId, tag: tag) > 0
                ? (position) => showMMMenu(
                    context,
                    position: position,
                    entries: [
                      MMMenuItem(
                        l.reviewTag,
                        () => ref
                            .read(navigationProvider.notifier)
                            .startReview(studySetId, mapId: state.activeMapId, tag: tag),
                      ),
                    ],
                  )
                : null,
          ),
    ];
    final hits = content == null
        ? const <Card>[]
        : content.search(query, mapId: state.activeMapId, tag: tagFilter).toList();
    final cards = [
      for (final card in hits)
        MMSidebarItem(
          icon: switch (card.kind) {
            CardKind.topic => MMIcons.addTopic,
            CardKind.excerpt || CardKind.image => MMIcons.highlight,
            CardKind.note || CardKind.research => MMIcons.addNote,
          },
          label: card.title.isNotEmpty
              ? notePlainText(card.title, card.textFormat)
              : (content!.annotation(card.annotationId ?? '')?.quote ?? ''),
          selected: card.id == state.selectedCardId,
          onTap: () => content!.annotation(card.annotationId ?? '') != null
              ? controller.revealCard(card.id)
              : controller.selectCard(card.id),
        ),
    ];
    final empty = maps.isEmpty && docs.isEmpty && learn.isEmpty && cards.isEmpty && tags.isEmpty;

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
                    child: Text(studyTitle ?? '', style: t.headline, maxLines: 1, overflow: TextOverflow.ellipsis),
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
      children: [
        if (empty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(l.noSidebarMatches, textAlign: TextAlign.center, style: t.footnote),
          ),
        if (tags.isNotEmpty) MMSidebarSection(title: l.sectionTags, children: tags),
        if (cards.isNotEmpty || tagFilter != null)
          MMSidebarSection(
            title: l.sectionCards,
            children: [
              if (cards.isEmpty) Text(l.noSidebarMatches, style: t.footnote),
              ...cards,
            ],
          ),
        if (maps.isNotEmpty)
          MMSidebarSection(
            title: l.sectionMaps,
            showTrailingOnHover: true,
            trailing: MMIconButton(
              icon: MMIcons.add,
              tooltip: l.newMap,
              onPressed: () => showNewMapSheet(context, ref, studySetId),
            ),
            children: maps,
          ),
        if (docs.isNotEmpty || query.isEmpty)
          MMSidebarSection(
            title: l.sectionDocuments,
            showTrailingOnHover: true,
            trailing: ref.watch(canAddWebPageProvider)
                ? MMDropdownButton<String>(
                    key: const ValueKey('add-document-menu'),
                    tooltip: l.addDocumentMenu,
                    width: MMSizes.dropdownWideWidth,
                    icon: const Icon(MMIcons.add),
                    onSelected: (value) => value == 'web'
                        ? dispatchAddWebPage(context, ref, studySetId)
                        : pickAndImportDocuments(context, ref, studySetId),
                    itemBuilder: (_) => [
                      MMDropdownItem(value: 'import', child: Text(l.importDocument)),
                      MMDropdownItem(value: 'web', child: Text(l.addWebPage)),
                    ],
                  )
                : MMIconButton(
                    icon: MMIcons.add,
                    tooltip: AppShortcuts.tip(l.importDocument, AppShortcuts.importDocument),
                    onPressed: () => pickAndImportDocuments(context, ref, studySetId),
                  ),
            children: docs,
          ),
        if (learn.isNotEmpty) MMSidebarSection(title: l.sectionLearn, children: learn),
      ],
    );
  }

  void _mapMenu(BuildContext context, WidgetRef ref, MindMap map, Offset position) {
    final l = context.l10n;
    final controller = ref.read(workspaceProvider(studySetId).notifier);
    showMMMenu(
      context,
      position: position,
      entries: [
        MMMenuItem(l.newMap, () => showNewMapSheet(context, ref, studySetId)),
        MMMenuItem(l.renameMap, () => showMapRenameSheet(context, ref, studySetId, map.id)),
        if (controller.content.maps.length > 1)
          MMMenuItem(l.deleteMap, () => controller.removeMap(map.id), destructive: true),
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
