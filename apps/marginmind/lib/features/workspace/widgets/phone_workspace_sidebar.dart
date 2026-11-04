import 'package:flutter/material.dart';
import 'package:mm_design/mm_design.dart';

import '../../../app/navigation.dart';
import '../../../shared/l10n.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The phone's grouped navigation; it shares commands and content with the sidebar.
class PhoneWorkspaceSidebar extends ConsumerStatefulWidget {
  const PhoneWorkspaceSidebar({
    super.key,
    required this.title,
    required this.mapId,
    required this.documents,
    required this.maps,
    required this.notes,
    required this.showNotes,
    required this.learning,
    required this.tags,
    required this.results,
    required this.searching,
    this.onSearch,
    required this.onAddDocument,
    this.onAddWebPage,
    required this.onAddMap,
    this.onGenerateMap,
    required this.onAddNote,
  });

  final String title;
  final ValueChanged<String>? onSearch;
  final String? mapId;
  final VoidCallback onAddDocument, onAddMap, onAddNote;
  final VoidCallback? onAddWebPage, onGenerateMap;
  final List<Widget> documents, maps, notes, learning, results;
  final List<MMPhoneNavigationRow> tags;
  final bool searching, showNotes;

  @override
  ConsumerState<PhoneWorkspaceSidebar> createState() => _PhoneWorkspaceSidebarState();
}

class _PhoneWorkspaceSidebarState extends ConsumerState<PhoneWorkspaceSidebar> {
  final _headerKey = GlobalKey();
  bool _notesExpanded = false;
  bool _tagsExpanded = false;
  static const _tagPreviewCount = 10;

  @override
  void didUpdateWidget(covariant PhoneWorkspaceSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mapId != oldWidget.mapId) _tagsExpanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    final visibleTags = _tagsExpanded ? widget.tags : widget.tags.take(_tagPreviewCount).toList();
    final selectedTag = widget.tags.indexWhere((row) => row.item.selected);
    if (!_tagsExpanded && selectedTag >= _tagPreviewCount) {
      visibleTags[_tagPreviewCount - 1] = widget.tags[selectedTag];
    }
    final empty =
        widget.searching &&
        widget.documents.isEmpty &&
        widget.maps.isEmpty &&
        !widget.showNotes &&
        widget.learning.isEmpty &&
        widget.tags.isEmpty &&
        widget.results.isEmpty;
    final groups = [
      if (!widget.searching || widget.documents.isNotEmpty)
        MMPhoneNavigationGroup(
          title: l.sectionDocuments,
          trailing: widget.onAddWebPage == null
              ? MMIconButton(icon: MMIcons.add, tooltip: l.importDocument, onPressed: widget.onAddDocument)
              : MMDropdownButton<VoidCallback>(
                  tooltip: l.addDocumentMenu,
                  icon: const Icon(MMIcons.add),
                  onSelected: (action) => action(),
                  itemBuilder: (_) => [
                    MMDropdownItem(value: widget.onAddDocument, icon: MMIcons.import, child: Text(l.importDocument)),
                    MMDropdownItem(value: widget.onAddWebPage!, icon: MMIcons.web, child: Text(l.addWebPage)),
                  ],
                ),
          children: widget.documents,
        ),
      if (!widget.searching || widget.maps.isNotEmpty)
        MMPhoneNavigationGroup(
          title: l.sectionMaps,
          trailing: widget.onGenerateMap == null
              ? MMIconButton(icon: MMIcons.add, tooltip: l.newMap, onPressed: widget.onAddMap)
              : MMDropdownButton<VoidCallback>(
                  tooltip: l.newMap,
                  icon: const Icon(MMIcons.add),
                  onSelected: (action) => action(),
                  itemBuilder: (_) => [
                    MMDropdownItem(value: widget.onAddMap, icon: MMIcons.mindMap, child: Text(l.newMap)),
                    MMDropdownItem(
                      icon: MMIcons.generateMap,
                      value: widget.onGenerateMap!,
                      child: Row(
                        children: [
                          Expanded(child: Text(l.mapGenerateMenu)),
                          const SizedBox(width: MMSpacing.xs),
                          const MMBetaBadge(),
                        ],
                      ),
                    ),
                  ],
                ),
          children: widget.maps,
        ),
      if (widget.showNotes || widget.learning.isNotEmpty)
        MMPhoneNavigationGroup(
          title: l.sectionLearn,
          children: [
            if (widget.showNotes)
              MMPhoneNavigationRow(
                item: MMSidebarItem(
                  icon: MMIcons.studyNote,
                  label: l.phoneNavigationNotes,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const MMBetaBadge(),
                      const SizedBox(width: MMSpacing.xs),
                      Icon(
                        _notesExpanded ? MMIcons.chevronDown : MMIcons.chevronRight,
                        size: MMPhoneNavigation.iconSize,
                        color: c.secondaryLabel,
                      ),
                    ],
                  ),
                  onTap: widget.notes.isEmpty
                      ? widget.onAddNote
                      : () => setState(() => _notesExpanded = !_notesExpanded),
                ),
              ),
            if (_notesExpanded || widget.searching) ...widget.notes,
            if (_notesExpanded && !widget.searching)
              MMPhoneNavigationRow(
                item: MMSidebarItem(
                  icon: MMIcons.add,
                  label: l.organizeStudyNote,
                  trailing: const MMBetaBadge(),
                  onTap: widget.onAddNote,
                ),
              ),
            ...widget.learning,
          ],
        ),
      if (widget.tags.isNotEmpty)
        MMPhoneNavigationGroup(
          title: l.sectionTags,
          children: [
            ...visibleTags,
            if (widget.tags.length > _tagPreviewCount)
              MMPhoneNavigationRow(
                key: const ValueKey('sidebar-tags-expand'),
                item: MMSidebarItem(
                  icon: _tagsExpanded ? MMIcons.chevronUp : MMIcons.chevronDown,
                  label: _tagsExpanded ? l.collapseSection : l.expandSection,
                  trailing: _tagsExpanded ? null : MMBadge('${widget.tags.length - _tagPreviewCount}'),
                  onTap: () => setState(() => _tagsExpanded = !_tagsExpanded),
                ),
              ),
          ],
        ),
      if (widget.results.isNotEmpty) MMPhoneNavigationGroup(title: l.sectionCards, children: widget.results),
    ];
    final rows = <Widget>[
      if (empty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(l.noSidebarMatches, textAlign: TextAlign.center, style: context.mmText.footnote),
        ),
      for (final group in groups) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: group),
    ];
    final header = Column(
      key: _headerKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: MMPhoneNavigationAction(
                    label: l.librarySection,
                    icon: MMIcons.chevronLeft,
                    color: c.accent,
                    maxLines: null,
                    onPressed: () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      ref.read(navigationProvider.notifier).showLibrary();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(widget.title, style: context.mmText.title2, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: MMSearchField(placeholder: l.searchInSet, height: 44, onChanged: widget.onSearch),
        ),
      ],
    );
    return ColoredBox(
      key: const ValueKey('phone-workspace-sidebar'),
      color: c.windowBackground,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: LayoutBuilder(
            builder: (context, bounds) {
              // Landscape keyboards may leave too little room for a fixed header.
              // Scroll the complete page then, retaining the search field's state.
              if (bounds.maxHeight < 240) {
                return ListView(
                  key: const ValueKey('phone-drawer-list'),
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [header, ...rows],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  Expanded(
                    child: ListView(
                      key: const ValueKey('phone-drawer-list'),
                      padding: const EdgeInsets.only(bottom: 16),
                      children: rows,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
