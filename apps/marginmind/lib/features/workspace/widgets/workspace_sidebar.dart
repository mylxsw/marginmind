import '../../vocabulary/vocabulary_controller.dart';
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
import '../../../settings/app_settings.dart';
import '../../../shared/l10n.dart';
import '../translation_task_summary.dart';
import 'full_translation_sheet.dart';
import 'full_translation_panel.dart';
import '../workspace_controller.dart';
import '../../map_generation/map_generation_controller.dart';
import '../../map_generation/map_updates.dart';
import '../../map_generation/widgets/generate_map_sheet.dart';
import '../../study_notes/note_setup_sheet.dart';
import '../../study_notes/note_updates.dart';
import '../../study_notes/note_export_sheet.dart';
import 'notices.dart';
import 'phone_workspace_sidebar.dart';

/// Study set sidebar: documents, mind maps, notes and learning tools,
/// followed by matching cards and tags. Search filters every section at once.
class WorkspaceSidebar extends ConsumerWidget {
  const WorkspaceSidebar({super.key, required this.studySetId, required this.searchFocus, this.onDismiss});

  final String studySetId;
  final FocusNode searchFocus;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = context.mmText;
    final c = context.mmColors;
    final provider = workspaceProvider(studySetId);
    ref.watch(
      provider.select(
        (s) => (
          s.sidebarQuery,
          s.activeMapId,
          s.activeNoteId,
          s.tabs.activeId,
          s.panel,
          s.noteReference,
          s.activeDocumentId,
          s.tagFilter,
          s.selectedCardId,
        ),
      ),
    );
    final state = ref.read(provider);
    final controller = ref.read(provider.notifier);
    final content = ref.watch(workspaceContentProvider(studySetId));
    final studyTitle = ref.watch(studySetProvider(studySetId).select((s) => s?.title));
    final documents = content?.documents ?? const [];
    final query = state.sidebarQuery.trim().toLowerCase();
    bool matches(String text) => query.isEmpty || text.toLowerCase().contains(query);

    final phone = MMInput.of(context).phone && MMSizeClass.of(context) == MMSizeClass.compact;
    Widget phoneRow(Widget widget, {bool cautionCount = false, bool? mapDestination, bool document = false}) {
      if (widget is DecoratedBox) {
        return DecoratedBox(
          key: widget.key,
          decoration: widget.decoration,
          child: phoneRow(widget.child!, mapDestination: mapDestination, document: true),
        );
      }
      if (widget is! MMSidebarItem) return widget;
      return MMPhoneNavigationRow(
        key: widget.key,
        cautionCount: cautionCount,
        item: MMSidebarItem(
          icon: widget.icon,
          label: widget.label,
          selected:
              widget.selected && (mapDestination == null || mapDestination == (state.layout == MMSplitMode.secondary)),
          leading: widget.leading,
          labelColor: widget.labelColor,
          // A document row needs only its title, never OCR/map metadata.
          trailing: document ? null : widget.trailing,
          onContextMenu: widget.onContextMenu,
          onTap: widget.onTap == null
              ? null
              : () {
                  widget.onTap!();
                  onDismiss?.call();
                },
        ),
      );
    }

    final betaEnabled = ref.watch(settingsProvider.select((s) => s.betaFeaturesEnabled));
    final mapGen = ref.watch(mapGenerationControllerProvider(studySetId));

    final maps = [
      for (final map in content?.maps ?? const <MindMap>[])
        if (matches(map.title.isEmpty ? l.mainMap : map.title))
          MMSidebarItem(
            key: ValueKey('sidebar-map-${map.id}'),
            icon: MMIcons.mindMap,
            label: map.title.isEmpty ? l.mainMap : map.title,
            trailing: !betaEnabled
                ? null
                : () {
                    final isGenerating =
                        mapGen != null &&
                        mapGen.request.mapId == map.id &&
                        (mapGen.phase == MapGenerationPhase.reading || mapGen.phase == MapGenerationPhase.streaming);
                    if (isGenerating) {
                      return SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: c.research),
                      );
                    }
                    final hasUpdates = ref.watch(mapHasUpdatesProvider((studySetId, map.id)));
                    if (hasUpdates) {
                      return Semantics(
                        label: l.mapHasUpdates,
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(color: c.research, shape: BoxShape.circle),
                        ),
                      );
                    }
                    return null;
                  }(),
            selected:
                state.tagFilter == null &&
                state.tabs.active?.kind == WorkspaceTabKind.documentMap &&
                map.id == state.activeMapId,
            selectionStyle: context.mmTouchPlatform ? MMSidebarSelectionStyle.marker : MMSidebarSelectionStyle.filled,
            onTap: () => controller.openMainMap(map.id),
            onContextMenu: (position) => _mapMenu(context, ref, map, position),
          ),
    ];
    final orderedNotes = !betaEnabled
        ? <StudyNote>[]
        : ((content?.studyNotes ?? <StudyNote>[]).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)));
    final notes = [
      for (final note in orderedNotes)
        if (matches(note.title))
          MMSidebarItem(
            key: ValueKey('sidebar-note-${note.id}'),
            icon: MMIcons.studyNote,
            label: note.title,
            trailing: (ref.watch(noteChangesProvider((studySetId, note.id)))?.count ?? 0) > 0
                ? MMBadge(
                    '${ref.watch(noteChangesProvider((studySetId, note.id)))!.count}',
                    key: ValueKey('note-update-badge-${note.id}'),
                    prominent: true,
                  )
                : null,
            selected: state.activeNoteId == note.id,
            onTap: () => controller.openStudyNote(note.id),
            onContextMenu: (position) => showMMMenu(
              context,
              position: position,
              entries: [
                MMMenuItem(l.renameEllipsis, () async {
                  final title = await showRenameSheet(context, title: l.renameEllipsis, initial: note.title);
                  if (title != null && title.trim().isNotEmpty) {
                    await controller.changeStudyNote(note.id, (n) => n.copyWith(title: title.trim()));
                  }
                }, icon: MMIcons.editNote),
                MMMenuItem(
                  l.exportStudyNote,
                  () => showNoteExportSheet(context, ref, studySetId, note.id),
                  icon: MMIcons.export,
                ),
                MMMenuItem(
                  l.delete,
                  () async {
                    await controller.deleteStudyNote(note.id);
                    if (context.mounted) {
                      MMHud.show(
                        context,
                        l.deletedHud(note.title),
                        action: (
                          l.undo,
                          () {
                            controller.undo();
                          },
                        ),
                      );
                    }
                  },
                  destructive: true,
                  icon: MMIcons.trash,
                ),
              ],
            ),
          ),
    ];
    final browser = ref.watch(workspaceBrowserProvider(studySetId));
    final browserOwner = ref.read(workspaceBrowserProvider(studySetId).notifier);
    final importing = ref.watch(documentImportsProvider(studySetId));
    final flashed = ref.watch(importedDocumentsProvider(studySetId));
    final docs = <Widget>[
      for (final d in documents)
        if (matches(d.title))
          DecoratedBox(
            key: ValueKey('document-row-${d.id}'),
            decoration: BoxDecoration(
              color: flashed.contains(d.id) ? c.accentTint : null,
              borderRadius: BorderRadius.circular(MMRadii.row),
            ),
            child: MMSidebarItem(
              icon: documentIcon(d),
              label: d.title,
              trailing: _DocumentTranslationTrailing(studySetId: studySetId, document: d),
              selected:
                  !browser.visible &&
                  state.tabs.active?.kind == WorkspaceTabKind.documentMap &&
                  d.id == state.activeDocumentId,
              selectionStyle: context.mmTouchPlatform ? MMSidebarSelectionStyle.marker : MMSidebarSelectionStyle.filled,
              onTap: () {
                browserOwner.hide();
                controller.openDocument(d.id);
              },
              onContextMenu: (position) => _documentMenu(context, ref, d, position),
            ),
          ),
      for (final task in importing)
        MMSidebarItem(
          key: ValueKey('import-${task.id}'),
          icon: MMIcons.document,
          label: task.name,
          labelColor: c.secondaryLabel,
          trailing: const SizedBox(
            width: MMSizes.dropdownIcon,
            height: MMSizes.dropdownIcon,
            child: CircularProgressIndicator(strokeWidth: MMSpacing.xxs),
          ),
          onContextMenu: (position) => showMMMenu(
            context,
            position: position,
            entries: [
              MMMenuItem(
                l.cancelImport,
                () => ref.read(documentImportsProvider(studySetId).notifier).cancel(task.id),
                icon: MMIcons.close,
              ),
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
                  child: Builder(
                    builder: (context) {
                      final item = MMSidebarItem(
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
                        selectionStyle: context.mmTouchPlatform
                            ? MMSidebarSelectionStyle.marker
                            : MMSidebarSelectionStyle.filled,
                        onTap: browserOwner.show,
                      );
                      return phone ? phoneRow(item) : item;
                    },
                  ),
                ),
        ),
      );
    }
    final now = ref.watch(clockProvider)();
    final due = content?.dueCount(now, mapId: state.activeMapId) ?? 0;
    final vocabularyCount =
        ref
            .watch(vocabularyProvider)
            .asData
            ?.value
            .entries
            .where((e) => e.status == VocabularyStatus.learning)
            .length ??
        0;
    final learn = [
      if (matches(l.vocabularyTitle))
        MMSidebarItem(
          icon: MMIcons.vocabulary,
          label: l.vocabularyTitle,
          trailing: vocabularyCount > 0 ? MMBadge('$vocabularyCount') : null,
          onTap: () => controller.activateTab(WorkspaceTab.vocabulary),
        ),
      if (matches(l.review))
        MMSidebarItem(
          icon: MMIcons.review,
          label: l.review,
          trailing: due > 0 ? MMBadge('$due', prominent: true) : null,
          onTap: () => controller.activateTab(WorkspaceTab.review),
        ),
      if (content != null && content.reviewLogs.isNotEmpty && matches(l.statistics))
        MMSidebarItem(
          key: const ValueKey('sidebar-statistics'),
          icon: MMIcons.statistics,
          label: l.statistics,
          onTap: () => controller.activateTab(WorkspaceTab.statistics),
        ),
    ];
    final tagCounts = <String, int>{};
    for (final map in content?.maps ?? const <MindMap>[]) {
      for (final entry in content!.tagCounts(mapId: map.id).entries) {
        tagCounts.update(entry.key, (n) => n + entry.value, ifAbsent: () => entry.value);
      }
    }
    final tagFilter = state.tagFilter;
    final tags = [
      for (final tag in tagCounts.keys)
        if (matches(tag) || (!phone && tag.toLowerCase() == tagFilter?.toLowerCase()))
          MMSidebarItem(
            key: ValueKey('sidebar-tag-$tag'),
            icon: MMIcons.tag,
            label: tag,
            selected: tag.toLowerCase() == tagFilter?.toLowerCase(),
            selectionStyle: MMSidebarSelectionStyle.accent,
            trailing: MMBadge('${tagCounts[tag]}'),
            onTap: () => controller.filterTag(tag),
            onContextMenu: content!.dueCount(now, mapId: state.activeMapId, tag: tag) > 0
                ? (position) => showMMMenu(
                    context,
                    position: position,
                    entries: [
                      MMMenuItem(
                        l.reviewTag,
                        () => controller.startReview(mapId: state.activeMapId, tag: tag),
                        icon: MMIcons.review,
                      ),
                    ],
                  )
                : null,
          ),
    ];
    final hits = content == null ? const <Card>[] : content.search(query, mapId: state.activeMapId).toList();
    final cards = [
      for (final card in hits)
        MMSidebarItem(
          key: ValueKey('sidebar-card-${card.id}'),
          icon: switch (card.kind) {
            CardKind.topic => MMIcons.addTopic,
            CardKind.excerpt || CardKind.image => MMIcons.highlight,
            CardKind.note || CardKind.research => MMIcons.addNote,
          },
          label: card.title.isNotEmpty
              ? notePlainText(card.title, card.textFormat)
              : (content!.annotation(card.annotationId ?? '')?.quote ?? ''),
          selected: card.id == state.selectedCardId,
          onTap: () async {
            await controller.revealTagTopic(state.activeMapId, card.id);
          },
        ),
    ];
    final empty = maps.isEmpty && docs.isEmpty && notes.isEmpty && learn.isEmpty && cards.isEmpty && tags.isEmpty;

    if (phone) {
      return PhoneWorkspaceSidebar(
        key: ValueKey(studySetId),
        title: studyTitle ?? '',
        mapId: state.activeMapId,
        searchFocus: searchFocus,
        onSearch: controller.setSidebarQuery,
        onDismiss: onDismiss ?? controller.toggleSidebar,
        documents: [for (final row in docs) phoneRow(row, mapDestination: false)],
        maps: [for (final row in maps) phoneRow(row, mapDestination: true)],
        notes: [for (final row in notes) phoneRow(row)],
        showNotes: betaEnabled && (matches(l.phoneNavigationNotes) || notes.isNotEmpty),
        learning: [
          if (matches(l.sectionCards))
            MMPhoneNavigationRow(
              item: MMSidebarItem(
                icon: MMIcons.review,
                label: l.sectionCards,
                trailing: MMBadge(
                  '${content?.cards.where((card) => content.isPlaced(card.id, mapId: state.activeMapId)).length ?? 0}',
                ),
                onTap: () {
                  controller.filterTag(null);
                  controller.setLayout(MMSplitMode.secondary);
                  onDismiss?.call();
                },
              ),
            ),
          for (final row in learn) phoneRow(row, cautionCount: row.icon == MMIcons.review),
        ],
        tags: [
          if (query.isEmpty || matches(l.sectionTags) || tags.isNotEmpty)
            phoneRow(
              MMSidebarItem(
                key: const ValueKey('sidebar-tags'),
                icon: MMIcons.tag,
                label: l.allTags,
                onTap: controller.showTags,
              ),
            ) as MMPhoneNavigationRow,
        ],
        results: query.isEmpty ? const [] : [for (final row in cards) phoneRow(row)],
        searching: query.isNotEmpty,
        onAddDocument: () => pickAndImportDocuments(context, ref, studySetId),
        onAddWebPage: ref.watch(canAddWebPageProvider) ? () => dispatchAddWebPage(context, ref, studySetId) : null,
        onAddMap: () => showNewMapSheet(context, ref, studySetId),
        onGenerateMap: betaEnabled
            ? () => showGenerateMapSheet(context, ref, studySetId, preselectedDocId: state.activeDocumentId)
            : null,
        onAddNote: () => showNoteSetupSheet(context, ref, studySetId),
      );
    }

    final canAddWebPage = ref.watch(canAddWebPageProvider);
    List<PopupMenuEntry<String>> documentEntries(BuildContext _) => [
      MMDropdownItem(value: 'import', icon: MMIcons.import, child: Text(l.importDocument)),
      if (canAddWebPage) MMDropdownItem(value: 'web', icon: MMIcons.web, child: Text(l.addWebPage)),
    ];
    List<PopupMenuEntry<String>> mapEntries(BuildContext _) => [
      MMDropdownItem(value: 'new', icon: MMIcons.mindMap, child: Text(l.newMap)),
      if (betaEnabled)
        MMDropdownItem(
          icon: MMIcons.generateMap,
          value: 'generate',
          child: Row(
            children: [
              Expanded(child: Text(l.mapGenerateMenu)),
              const SizedBox(width: MMSpacing.xs),
              const MMBetaBadge(),
            ],
          ),
        ),
    ];
    void addContent(String value) {
      switch (value) {
        case 'import':
          pickAndImportDocuments(context, ref, studySetId);
        case 'web':
          dispatchAddWebPage(context, ref, studySetId);
        case 'new':
          showNewMapSheet(context, ref, studySetId);
        case 'generate':
          showGenerateMapSheet(context, ref, studySetId, preselectedDocId: state.activeDocumentId);
      }
    }

    return MMSidebar(
      topTrailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MMIconButton(
            key: const ValueKey('workspace-home'),
            icon: MMIcons.home,
            tooltip: AppShortcuts.tip(l.showLibrary, AppShortcuts.showLibrary),
            onPressed: () => ref.read(navigationProvider.notifier).showLibrary(),
          ),
          const SizedBox(width: 8),
          MMIconButton(
            key: const ValueKey('workspace-hide-sidebar'),
            icon: MMIcons.sidebarClose,
            tooltip: AppShortcuts.tip(l.hideSidebar, AppShortcuts.toggleSidebar),
            onPressed: onDismiss ?? controller.toggleSidebar,
          ),
        ],
      ),
      header: MMSearchField(placeholder: l.searchInSet, focusNode: searchFocus, onChanged: controller.setSidebarQuery),
      footer: Align(
        alignment: Alignment.centerRight,
        child: MMDropdownButton<String>(
          key: const ValueKey('workspace-add-content'),
          tooltip: l.addDocumentMenu,
          width: MMSizes.dropdownWideWidth,
          icon: const Icon(MMIcons.add),
          onSelected: addContent,
          itemBuilder: (context) => [
            MMDropdownHeader(l.sectionDocuments),
            ...documentEntries(context),
            const PopupMenuDivider(),
            MMDropdownHeader(l.sectionMaps),
            ...mapEntries(context),
          ],
        ),
      ),
      children: [
        if (empty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(l.noSidebarMatches, textAlign: TextAlign.center, style: t.footnote),
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
                    onSelected: addContent,
                    itemBuilder: documentEntries,
                  )
                : MMIconButton(
                    icon: MMIcons.add,
                    tooltip: AppShortcuts.tip(l.importDocument, AppShortcuts.importDocument),
                    onPressed: () => pickAndImportDocuments(context, ref, studySetId),
                  ),
            children: docs,
          ),
        if (maps.isNotEmpty)
          MMSidebarSection(
            title: l.sectionMaps,
            showTrailingOnHover: true,
            trailing: betaEnabled
                ? MMDropdownButton<String>(
                    key: const ValueKey('add-map-menu'),
                    tooltip: l.newMap,
                    width: MMSizes.dropdownWideWidth,
                    icon: const Icon(MMIcons.add),
                    onSelected: addContent,
                    itemBuilder: mapEntries,
                  )
                : MMIconButton(
                    key: const ValueKey('add-map-menu'),
                    icon: MMIcons.add,
                    tooltip: l.newMap,
                    onPressed: () => showNewMapSheet(context, ref, studySetId),
                  ),
            children: maps,
          ),
        if (betaEnabled && (notes.isNotEmpty || query.isEmpty))
          MMSidebarSection(
            title: l.notesTitle,
            titleTrailing: const MMBetaBadge(),
            trailing: MMIconButton(
              icon: MMIcons.add,
              tooltip: l.organizeStudyNote,
              onPressed: () => showNoteSetupSheet(context, ref, studySetId),
            ),
            children: notes,
          ),
        if (learn.isNotEmpty) MMSidebarSection(title: l.sectionLearn, children: learn),
        if (cards.isNotEmpty) MMSidebarSection(title: l.sectionCards, children: cards),
        if (query.isEmpty || matches(l.sectionTags))
          Padding(
            padding: const EdgeInsets.only(top: MMSpacing.m),
            child: MMSidebarItem(
              key: const ValueKey('sidebar-tags'),
              icon: MMIcons.tag,
              label: l.sectionTags,
              onTap: controller.showTags,
            ),
          ),
        if (query.isNotEmpty && tags.isNotEmpty)
          _SidebarTags(key: ValueKey((studySetId, state.activeMapId)), tags: tags),
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
        MMMenuItem(l.newMap, () => showNewMapSheet(context, ref, studySetId), icon: MMIcons.mindMap),
        MMMenuItem(l.renameMap, () => showMapRenameSheet(context, ref, studySetId, map.id), icon: MMIcons.editNote),
        if (controller.content.maps.length > 1)
          MMMenuItem(l.deleteMap, () => controller.removeMap(map.id), destructive: true, icon: MMIcons.trash),
      ],
    );
  }

  void _documentMenu(BuildContext context, WidgetRef ref, Document doc, Offset position) {
    final l = context.l10n;
    final controller = ref.read(workspaceProvider(studySetId).notifier);
    final fullState = ref.read(translationTaskSummaryProvider((studySetId, doc.id))).value;
    final targetLang = fullState?.targetLang ?? 'zh';
    final hasActiveFullJob = fullState?.isActive == true;
    final canFullTranslate = MMPlatformCapabilities.current.assistant && MMSizeClass.of(context) != MMSizeClass.compact;
    final betaEnabled = ref.read(settingsProvider).betaFeaturesEnabled;

    showMMMenu(
      context,
      position: position,
      entries: [
        MMMenuItem(l.open, () => controller.openDocument(doc.id), icon: MMIcons.reading),
        if (canFullTranslate) ...[
          if (hasActiveFullJob)
            MMMenuItem(
              l.fullTranslationTaskMenu(fullState!.percent),
              () =>
                  showFullTranslationPanel(context, studySetId: studySetId, documentId: doc.id, targetLang: targetLang),
              icon: MMIcons.translate,
            )
          else
            MMMenuItem(
              l.fullTranslationMenu,
              () => showFullTranslationSheet(context, studySetId: studySetId, documentId: doc.id),
              icon: MMIcons.translate,
            ),
        ],
        if (betaEnabled)
          MMMenuItem(
            l.mapGenerateDocumentMenu,
            () => showGenerateMapSheet(context, ref, studySetId, preselectedDocId: doc.id),
            badge: const MMBetaBadge(),
            icon: MMIcons.generateMap,
          ),

        MMMenuItem(l.renameEllipsis, () async {
          final title = await showRenameSheet(context, title: l.renameDocument, initial: doc.title);
          if (title != null) await controller.renameDocument(doc.id, title);
        }, icon: MMIcons.editNote),
        const MMMenuDivider(),
        MMMenuItem(
          l.removeDocumentEllipsis,
          () async {
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
          },
          destructive: true,
          icon: MMIcons.trash,
        ),
      ],
    );
  }
}

class _DocumentTranslationTrailing extends ConsumerWidget {
  const _DocumentTranslationTrailing({required this.studySetId, required this.document});

  final String studySetId;
  final Document document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fullState = ref.watch(translationTaskSummaryProvider((studySetId, document.id)).select((s) => s.value));
    final job = fullState?.job;
    final c = context.mmColors;

    if (job != null && job.isActive) {
      if (job.state == TranslationJobState.review) {
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
        );
      }
      final pct = fullState!.percent;
      return SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          value: (pct / 100.0).clamp(0.0, 1.0),
          strokeWidth: 1.5,
          color: c.accent,
          backgroundColor: c.quaternaryFill,
        ),
      );
    }

    final content = ref.watch(workspaceContentProvider(studySetId));
    final hasMap =
        content?.maps.any((m) => m.generation?.sources.any((s) => s.documentId == document.id) == true) == true;
    final hasOcr =
        !document.capabilities().readingSettings &&
        ref
                .watch(readerOcrProvider(ref.read(workspaceProvider(studySetId).notifier).filePath(document)))
                .document
                ?.hasCopy ==
            true;
    if (hasMap || hasOcr) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasOcr) Text(context.l10n.ocrRecognized, style: context.mmText.footnote),
          if (hasOcr && hasMap) const SizedBox(width: 6),
          if (hasMap)
            Semantics(
              label: context.l10n.mapHasMap,
              child: Icon(MMIcons.mindMap, size: 12, color: c.secondaryLabel),
            ),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}

class _SidebarTags extends StatefulWidget {
  const _SidebarTags({super.key, required this.tags});

  final List<MMSidebarItem> tags;

  @override
  State<_SidebarTags> createState() => _SidebarTagsState();
}

class _SidebarTagsState extends State<_SidebarTags> {
  static const _previewCount = 10;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final tags = widget.tags;
    final visible = _expanded ? tags : tags.take(_previewCount).toList();
    // Keep the active filter visible when collapsing a longer tag list.
    final selected = tags.indexWhere((tag) => tag.selected);
    if (!_expanded && selected >= _previewCount) visible[_previewCount - 1] = tags[selected];
    return MMSidebarSection(
      title: l.sectionTags,
      children: [
        ...visible,
        if (tags.length > _previewCount)
          MMSidebarItem(
            key: const ValueKey('sidebar-tags-expand'),
            icon: _expanded ? MMIcons.chevronUp : MMIcons.chevronDown,
            label: _expanded ? l.collapseSection : l.expandSection,
            trailing: _expanded ? null : MMCount(tags.length - _previewCount),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
      ],
    );
  }
}
