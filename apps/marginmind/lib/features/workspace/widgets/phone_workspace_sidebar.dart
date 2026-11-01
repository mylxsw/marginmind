import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mm_design/mm_design.dart';

import '../../../app/navigation.dart';
import '../../../settings/settings_window.dart';
import '../../../shared/l10n.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The phone's grouped navigation; it shares commands and content with the sidebar.
class PhoneWorkspaceSidebar extends ConsumerStatefulWidget {
  const PhoneWorkspaceSidebar({
    super.key,
    required this.title,
    required this.mapId,
    required this.searchFocus,
    required this.onSearch,
    required this.onDismiss,
    required this.documents,
    required this.maps,
    required this.notes,
    required this.showNotes,
    required this.learning,
    required this.tags,
    required this.results,
    required this.searching,
    required this.onAddDocument,
    this.onAddWebPage,
    required this.onAddMap,
    this.onGenerateMap,
    required this.onAddNote,
  });

  final String title;
  final String? mapId;
  final FocusNode searchFocus;
  final ValueChanged<String> onSearch;
  final VoidCallback onDismiss, onAddDocument, onAddMap, onAddNote;
  final VoidCallback? onAddWebPage, onGenerateMap;
  final List<Widget> documents, maps, notes, learning, results;
  final List<MMPhoneNavigationRow> tags;
  final bool searching, showNotes;

  @override
  ConsumerState<PhoneWorkspaceSidebar> createState() => _PhoneWorkspaceSidebarState();
}

class _PhoneWorkspaceSidebarState extends ConsumerState<PhoneWorkspaceSidebar> {
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
    final safe = MediaQuery.paddingOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
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
                    MMDropdownItem(value: widget.onAddDocument, child: Text(l.importDocument)),
                    MMDropdownItem(value: widget.onAddWebPage!, child: Text(l.addWebPage)),
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
                    MMDropdownItem(value: widget.onAddMap, child: Text(l.newMap)),
                    MMDropdownItem(
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
    return ColoredBox(
      key: const ValueKey('phone-workspace-sidebar'),
      color: MMPhoneNavigation.background(dark),
      child: Padding(
        padding: EdgeInsets.only(top: safe.top, bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                key: const ValueKey('phone-drawer-list'),
                padding: const EdgeInsets.only(bottom: MMSpacing.l),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: MMPhoneNavigation.headerInset,
                      vertical: MMSpacing.s,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: MMPhoneNavigationAction(
                            label: l.librarySection,
                            icon: MMIcons.chevronLeft,
                            color: c.accent,
                            onPressed: () => ref.read(navigationProvider.notifier).showLibrary(),
                          ),
                        ),
                        const SizedBox(height: MMSpacing.s),
                        Text(
                          widget.title,
                          style: context.mmText.title2.copyWith(fontSize: MMPhoneNavigation.titleSize),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: MMSpacing.m),
                        MMSearchField(
                          placeholder: l.searchInSet,
                          focusNode: widget.searchFocus,
                          onChanged: widget.onSearch,
                        ),
                      ],
                    ),
                  ),
                  if (empty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: MMSpacing.xl),
                      child: Text(l.noSidebarMatches, textAlign: TextAlign.center, style: context.mmText.footnote),
                    ),
                  for (final group in groups)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: MMSpacing.l),
                      child: group,
                    ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(
                MMPhoneNavigation.headerInset,
                MMSpacing.s,
                MMPhoneNavigation.headerInset,
                math.max(safe.bottom, MMSpacing.s),
              ),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: c.separator, width: MMSizes.hairline),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: MMPhoneNavigationAction(
                      label: l.settingsTitle,
                      icon: MMIcons.settings,
                      onPressed: () {
                        widget.onDismiss();
                        showSettings(context);
                      },
                    ),
                  ),
                  Flexible(
                    child: MMPhoneNavigationAction(label: l.done, color: c.accent, onPressed: widget.onDismiss),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
