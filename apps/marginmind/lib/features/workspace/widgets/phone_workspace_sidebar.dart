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
    required this.searchFocus,
    required this.onSearch,
    required this.onDismiss,
    required this.documents,
    required this.maps,
    required this.notes,
    required this.learning,
    required this.tags,
    required this.results,
    required this.searching,
    required this.onAddDocument,
    this.onAddWebPage,
    required this.onAddMap,
    required this.onGenerateMap,
    required this.onAddNote,
    this.onAddTag,
  });

  final String title;
  final FocusNode searchFocus;
  final ValueChanged<String> onSearch;
  final VoidCallback onDismiss, onAddDocument, onAddMap, onGenerateMap, onAddNote;
  final VoidCallback? onAddWebPage;
  final VoidCallback? onAddTag;
  final List<Widget> documents, maps, notes, learning, tags, results;
  final bool searching;

  @override
  ConsumerState<PhoneWorkspaceSidebar> createState() => _PhoneWorkspaceSidebarState();
}

class _PhoneWorkspaceSidebarState extends ConsumerState<PhoneWorkspaceSidebar> {
  bool _notesExpanded = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    final safe = MediaQuery.paddingOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
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
          trailing: MMDropdownButton<VoidCallback>(
            tooltip: l.newMap,
            icon: const Icon(MMIcons.add),
            onSelected: (action) => action(),
            itemBuilder: (_) => [
              MMDropdownItem(value: widget.onAddMap, child: Text(l.newMap)),
              MMDropdownItem(value: widget.onGenerateMap, child: Text(l.mapGenerateMenu)),
            ],
          ),
          children: widget.maps,
        ),
      MMPhoneNavigationGroup(
        title: l.sectionLearn,
        trailing: MMIconButton(icon: MMIcons.add, tooltip: l.organizeStudyNote, onPressed: widget.onAddNote),
        children: [
          MMPhoneNavigationRow(
            learningCount: true,
            item: MMSidebarItem(
              icon: MMIcons.studyNote,
              label: l.phoneNavigationNotes,
              trailing: MMBadge('${widget.notes.length}'),
              onTap: widget.notes.isEmpty ? widget.onAddNote : () => setState(() => _notesExpanded = !_notesExpanded),
            ),
          ),
          if (_notesExpanded || widget.searching) ...widget.notes,
          ...widget.learning,
        ],
      ),
      if (widget.tags.isNotEmpty)
        MMPhoneNavigationGroup(
          title: l.sectionTags,
          trailing: MMIconButton(icon: MMIcons.add, tooltip: l.cardTags, onPressed: widget.onAddTag),
          children: widget.tags,
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
                      label: l.phoneNavigationSettings,
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
