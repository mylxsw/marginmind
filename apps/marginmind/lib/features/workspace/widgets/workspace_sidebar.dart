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
import '../../../shared/l10n.dart';
import '../workspace_controller.dart';
import '../../map_generation/map_generation_controller.dart';
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
        (s) => (s.sidebarQuery, s.activeMapId, s.activeNoteId, s.activeDocumentId, s.tagFilter, s.selectedCardId),
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
    Widget phoneRow(Widget widget, {bool learning = false, bool? mapDestination, bool document = false}) {
      if (widget is DecoratedBox) {
        return phoneRow(widget.child!, learning: learning, mapDestination: mapDestination, document: true);
      }
      if (widget is! MMSidebarItem) return widget;
      return MMPhoneNavigationRow(
        key: widget.key,
        learningCount: learning,
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

    final mapGen = ref.watch(mapGenerationControllerProvider(studySetId));

    final maps = [
      for (final map in content?.maps ?? const <MindMap>[])
        if (matches(map.title.isEmpty ? l.mainMap : map.title))
          MMSidebarItem(
            key: ValueKey('sidebar-map-${map.id}'),
            icon: MMIcons.mindMap,
            label: map.title.isEmpty ? l.mainMap : map.title,
            trailing: () {
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
              final hasUpdates =
                  map.generation != null &&
                  mapSourcesChanged(map.generation!, [
                    for (final s in map.generation!.sources)
                      MapSource(
                        documentId: s.documentId,
                        chapters: s.chapters,
                        fingerprint: content?.document(s.documentId) == null ? '' : s.fingerprint,
                        readThrough: s.readThrough,
                      ),
                  ]);
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
            selected: state.tagFilter == null && state.activeNoteId == null && map.id == state.activeMapId,
            selectionStyle: context.mmTouchPlatform ? MMSidebarSelectionStyle.marker : MMSidebarSelectionStyle.filled,
            onTap: () async {
              await controller.selectMap(map.id);
              controller.setLayout(MMSplitMode.secondary);
            },
            onContextMenu: (position) => _mapMenu(context, ref, map, position),
          ),
    ];
    final orderedNotes = (content?.studyNotes ?? <StudyNote>[]).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
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
                }),
                MMMenuItem(l.exportStudyNote, () => showNoteExportSheet(context, ref, studySetId, note.id)),
                MMMenuItem(l.delete, () async {
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
                }, destructive: true),
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
              trailing: () {
                final hasMap =
                    content?.maps.any((m) => m.generation?.sources.any((s) => s.documentId == d.id) == true) == true;
                final hasOcr =
                    !d.capabilities().readingSettings &&
                    ref.watch(readerOcrProvider(controller.filePath(d))).document?.hasCopy == true;
                if (hasMap && hasOcr) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l.ocrRecognized, style: context.mmText.footnote),
                      const SizedBox(width: 6),
                      Semantics(
                        label: l.mapHasMap,
                        child: Icon(MMIcons.mindMap, size: 12, color: c.secondaryLabel),
                      ),
                    ],
                  );
                }
                if (hasMap) {
                  return Semantics(
                    label: l.mapHasMap,
                    child: Icon(MMIcons.mindMap, size: 12, color: c.secondaryLabel),
                  );
                }
                if (hasOcr) {
                  return Text(l.ocrRecognized, style: context.mmText.footnote);
                }
                return null;
              }(),
              selected: !browser.visible && d.id == state.activeDocumentId,
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
          onTap: () => ref.read(navigationProvider.notifier).showVocabulary(studySetId: studySetId),
        ),
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
    final tagCounts = content?.tagCounts(mapId: state.activeMapId) ?? const <String, int>{};
    final tagFilter = state.tagFilter;
    final tags = [
      for (final tag in tagCounts.keys)
        if (matches(tag) || tag.toLowerCase() == tagFilter?.toLowerCase())
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
                        () => ref
                            .read(navigationProvider.notifier)
                            .startReview(studySetId, mapId: state.activeMapId, tag: tag),
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
            await controller.revealAnchor(SourceAnchor(target: CardTarget(cardId: card.id)));
            if (content!.annotation(card.annotationId ?? '') != null) controller.revealCard(card.id);
          },
        ),
    ];
    final empty = maps.isEmpty && docs.isEmpty && notes.isEmpty && learn.isEmpty && cards.isEmpty && tags.isEmpty;

    if (phone) {
      return PhoneWorkspaceSidebar(
        title: studyTitle ?? '',
        searchFocus: searchFocus,
        onSearch: controller.setSidebarQuery,
        onDismiss: onDismiss ?? controller.toggleSidebar,
        documents: [for (final row in docs) phoneRow(row, mapDestination: false)],
        maps: [for (final row in maps) phoneRow(row, mapDestination: true)],
        notes: [for (final row in notes) phoneRow(row)],
        learning: [
          MMPhoneNavigationRow(
            learningCount: true,
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
          for (final row in learn)
            if (row.icon != MMIcons.vocabulary) phoneRow(row, learning: true),
        ],
        tags: [for (final row in tags) phoneRow(row)],
        results: query.isEmpty ? const [] : [for (final row in cards) phoneRow(row)],
        searching: query.isNotEmpty,
        onAddDocument: () => pickAndImportDocuments(context, ref, studySetId),
        onAddWebPage: ref.watch(canAddWebPageProvider) ? () => dispatchAddWebPage(context, ref, studySetId) : null,
        onAddMap: () => showNewMapSheet(context, ref, studySetId),
        onGenerateMap: () => showGenerateMapSheet(context, ref, studySetId, preselectedDocId: state.activeDocumentId),
        onAddNote: () => showNoteSetupSheet(context, ref, studySetId),
        onAddTag: state.selectedCardId == null
            ? null
            : () => showCardTagsSheet(context, ref, studySetId, state.selectedCardId!),
      );
    }

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
        if (maps.isNotEmpty)
          MMSidebarSection(
            title: l.sectionMaps,
            showTrailingOnHover: true,
            trailing: MMDropdownButton<String>(
              key: const ValueKey('add-map-menu'),
              tooltip: l.newMap,
              width: MMSizes.dropdownWideWidth,
              icon: const Icon(MMIcons.add),
              onSelected: (value) => value == 'generate'
                  ? showGenerateMapSheet(context, ref, studySetId, preselectedDocId: state.activeDocumentId)
                  : showNewMapSheet(context, ref, studySetId),
              itemBuilder: (_) => [
                MMDropdownItem(value: 'new', child: Text(l.newMap)),
                MMDropdownItem(value: 'generate', child: Text(l.mapGenerateMenu)),
              ],
            ),
            children: maps,
          ),
        if (notes.isNotEmpty || query.isEmpty)
          MMSidebarSection(
            title: l.notesTitle,
            trailing: MMIconButton(
              icon: MMIcons.add,
              tooltip: l.organizeStudyNote,
              onPressed: () => showNoteSetupSheet(context, ref, studySetId),
            ),
            children: notes,
          ),
        if (learn.isNotEmpty) MMSidebarSection(title: l.sectionLearn, children: learn),
        if (cards.isNotEmpty) MMSidebarSection(title: l.sectionCards, children: cards),
        if (tags.isNotEmpty) _SidebarTags(key: ValueKey((studySetId, state.activeMapId)), tags: tags),
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
        MMMenuItem(
          l.mapGenerateDocumentMenu,
          () => showGenerateMapSheet(context, ref, studySetId, preselectedDocId: doc.id),
        ),
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
