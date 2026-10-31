import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../../app/providers.dart';
import '../../../shared/l10n.dart';
import '../../assistant/assistant_settings.dart';
import '../../assistant/widgets/assistant_panel.dart' show ModelSetupCard;
import '../../workspace/workspace_controller.dart';
import '../../workspace/reader_ocr.dart';
import '../map_generation_controller.dart';
import 'map_source_range.dart';
import 'map_generation_structure_preview.dart';

Future<void> showGenerateMapSheet(
  BuildContext context,
  WidgetRef ref,
  String studySetId, {
  String? preselectedDocId,
  String initialInstructions = '',
  bool mergeCurrentMap = false,
  bool initialNeedsSetup = false,
  ValueChanged<String>? onInstructionsChanged,
}) async {
  await showMMSheet<void>(
    context: context,
    width: MMSizes.mapGenerateSheetWidth,
    builder: (_) => GenerateMapSheet(
      studySetId: studySetId,
      preselectedDocId: preselectedDocId,
      mergeCurrentMap: mergeCurrentMap,
      initialNeedsSetup: initialNeedsSetup,
      initialInstructions: initialInstructions,
      onInstructionsChanged: onInstructionsChanged,
    ),
  );
}

class GenerateMapSheet extends ConsumerStatefulWidget {
  const GenerateMapSheet({
    super.key,
    required this.studySetId,
    this.preselectedDocId,
    this.mergeCurrentMap = false,
    this.initialNeedsSetup = false,
    this.initialInstructions = '',
    this.onInstructionsChanged,
  });

  final String studySetId;
  final String? preselectedDocId;
  final bool mergeCurrentMap;
  final bool initialNeedsSetup;
  final String initialInstructions;
  final ValueChanged<String>? onInstructionsChanged;

  @override
  ConsumerState<GenerateMapSheet> createState() => _GenerateMapSheetState();
}

enum _GeneratePanel { main, documents, advanced, range }

class _GenerateMapSheetState extends ConsumerState<GenerateMapSheet> {
  final _selectedDocs = <String>{};
  MapOrganization _organization = MapOrganization.chapter;
  bool _needsSetup = false;
  bool _starting = false;
  bool _userTouchedOrganization = false;
  int _depth = 3;
  bool _includeAnnotations = true;
  bool _extractQuotes = false;
  final _ranges = <String, List<String>?>{};
  String? _expandedDocument;
  _GeneratePanel _panel = _GeneratePanel.main;
  Set<String> _documentDraft = {};
  final _searchController = TextEditingController();
  int _rangeRevision = 0;
  String _destination = 'new'; // 'new' or 'branch'
  late final TextEditingController _titleController;
  late final TextEditingController _instructionsController;

  @override
  void initState() {
    super.initState();
    _needsSetup = widget.initialNeedsSetup;
    final content = ref.read(workspaceProvider(widget.studySetId).notifier).content;
    final prefs = ref.read(sharedPreferencesProvider);
    final key = 'map_gen.${widget.studySetId}';

    // Documents
    final preselected = widget.preselectedDocId;
    if (preselected != null && content.document(preselected) != null) {
      _selectedDocs.add(preselected);
    } else {
      final active = ref.read(workspaceProvider(widget.studySetId)).activeDocumentId;
      if (active != null && content.document(active) != null) {
        _selectedDocs.add(active);
      } else if (content.documents.isNotEmpty) {
        _selectedDocs.add(content.documents.first.id);
      }
    }

    // Prefs
    final orgName = prefs.getString('$key.organization');
    if (orgName != null) {
      _organization = MapOrganization.values.where((o) => o.name == orgName).firstOrNull ?? MapOrganization.chapter;
      _userTouchedOrganization = true;
    } else {
      _organization = _selectedDocs.length > 1 ? MapOrganization.topic : MapOrganization.chapter;
    }

    if (widget.mergeCurrentMap) {
      final mapId = ref.read(workspaceProvider(widget.studySetId)).activeMapId;
      final generation = content.map(mapId)?.generation;
      _selectedDocs.addAll([
        for (final source in generation?.sources ?? <MapSource>[])
          if (content.document(source.documentId) != null) source.documentId,
      ]);
      _organization = MapOrganization.topic;
      _userTouchedOrganization = true;
      _destination = 'branch';
    }

    _depth = (prefs.getInt('$key.depth') ?? 3).clamp(2, 4);
    _includeAnnotations = prefs.getBool('$key.includeAnnotations') ?? true;

    final firstDoc = content.document(_selectedDocs.firstOrNull ?? '');
    _titleController = TextEditingController(text: firstDoc?.title ?? '');
    _instructionsController = TextEditingController(text: widget.initialInstructions);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _instructionsController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _savePrefs() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final key = 'map_gen.${widget.studySetId}';
    await prefs.setString('$key.organization', _organization.name);
    await prefs.setInt('$key.depth', _depth);
    await prefs.setBool('$key.includeAnnotations', _includeAnnotations);
  }

  void _openDocuments() {
    setState(() {
      _documentDraft = {..._selectedDocs};
      _searchController.clear();
      _panel = _GeneratePanel.documents;
    });
  }

  void _applyDocuments(StudySetContent content) {
    if (_documentDraft.isEmpty) return;
    final previousTitle = content.document(_selectedDocs.firstOrNull ?? '')?.title;
    setState(() {
      _selectedDocs
        ..clear()
        ..addAll(_documentDraft);
      if (_titleController.text.trim().isEmpty || _titleController.text == previousTitle) {
        _titleController.text = content.document(_selectedDocs.first)?.title ?? '';
      }
      _expandedDocument = null;
      if (!_userTouchedOrganization) {
        _organization = _selectedDocs.length > 1 ? MapOrganization.topic : MapOrganization.chapter;
      }
      _panel = _GeneratePanel.main;
    });
  }

  void _back() => setState(() {
    _panel = _GeneratePanel.main;
    _expandedDocument = null;
  });

  void _escape() {
    if (_panel != _GeneratePanel.main) {
      _back();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  MapDocumentSelection _selection(String id, StudySetContent content, String mapId) {
    final previous = widget.mergeCurrentMap
        ? content.map(mapId)?.generation?.sources.where((s) => s.documentId == id).firstOrNull
        : null;
    return MapDocumentSelection(documentId: id, chapters: _ranges[id] ?? previous?.chapters ?? []);
  }

  List<String>? _range(String id, StudySetContent content, String mapId) =>
      _ranges.containsKey(id) ? _ranges[id] : _selection(id, content, mapId).chapters;

  bool _scanned(Document document) {
    if (document.format != DocumentFormat.pdf) return false;
    final workspace = ref.read(workspaceProvider(widget.studySetId).notifier);
    return ref.read(readerOcrProvider(workspace.filePath(document))).document?.textPages.isEmpty == true;
  }

  Future<void> _start() async {
    if (_panel == _GeneratePanel.documents ||
        _selectedDocs.isEmpty ||
        _starting ||
        _selectedDocs.any((id) => _ranges.containsKey(id) && _ranges[id] == null)) {
      return;
    }
    final content = ref.read(workspaceProvider(widget.studySetId).notifier).content;
    if (content.documents.any((doc) => _selectedDocs.contains(doc.id) && _scanned(doc))) return;
    _starting = true;
    final credential = await ref.read(assistantCredentialStateProvider.future);
    if (!mounted) return;
    _starting = false;
    if (credential != AssistantCredentialState.ready) {
      setState(() => _needsSetup = true);
      return;
    }
    final workspace = ref.read(workspaceProvider(widget.studySetId).notifier);
    final snapshot = workspace.content;

    _savePrefs();

    final wsState = ref.read(workspaceProvider(widget.studySetId));
    final isNewMap = _destination == 'new';
    // Merging into the current map is reviewed as an update diff, not a detached branch.
    final merge = widget.mergeCurrentMap && !isNewMap;
    final targetMapId = isNewMap ? 'map-${DateTime.now().microsecondsSinceEpoch}' : wsState.activeMapId;
    final title = _titleController.text.trim().isNotEmpty
        ? _titleController.text.trim()
        : (snapshot.document(_selectedDocs.first)?.title ?? AppLocalizations.of(context).mapView);

    final text = _instructionsController.text.trim();
    widget.onInstructionsChanged?.call(text);

    ref
        .read(mapGenerationControllerProvider(widget.studySetId).notifier)
        .start(
          MapGenerationRequest(
            studySetId: widget.studySetId,
            mapId: targetMapId,
            title: title,
            sources: [for (final id in _selectedDocs) _selection(id, snapshot, targetMapId)],
            organization: _organization,
            depth: _depth,
            instructions: text.isEmpty ? null : text,
            includeAnnotations: _includeAnnotations,
            extractQuotes: _extractQuotes,
            destination: isNewMap
                ? MapGenerationDestination.newMap
                : (merge ? MapGenerationDestination.update : MapGenerationDestination.branch),
            parentId: isNewMap || merge ? null : targetMapId,
          ),
        );

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors, t = context.mmText, l = context.l10n;
    final workspace = ref.read(workspaceProvider(widget.studySetId).notifier);
    final snapshot = ref.watch(workspaceContentProvider(widget.studySetId)) ?? workspace.content;
    final documents = snapshot.documents;
    final wsState = ref.watch(workspaceProvider(widget.studySetId));
    final hasNodes = snapshot.nodes.any((n) => n.mapId == wsState.activeMapId);
    if (_selectedDocs.isEmpty && documents.isNotEmpty) {
      final active = wsState.activeDocumentId;
      _selectedDocs.add(active != null && snapshot.document(active) != null ? active : documents.first.id);
      if (_titleController.text.isEmpty) _titleController.text = snapshot.document(_selectedDocs.first)?.title ?? '';
    }
    final selected = _selectedDocs.map(snapshot.document).whereType<Document>().toList();
    final markCount = snapshot.annotations.where((a) => _selectedDocs.contains(a.documentId)).length;
    final outlines = <String, List<PdfOutlineEntry>>{};
    final scanned = <String>{};
    for (final doc in documents) {
      if (_selectedDocs.contains(doc.id) || _documentDraft.contains(doc.id)) {
        outlines[doc.id] = ref.watch(mapDocumentOutlineProvider((widget.studySetId, doc.id))).value ?? [];
      }
      if (doc.format == DocumentFormat.pdf) {
        final source = workspace.filePath(doc);
        ref.watch(readerOcrInspectionProvider(source));
        if (ref.watch(readerOcrProvider(source)).document?.textPages.isEmpty == true) scanned.add(doc.id);
      }
    }
    final hasScanned = _selectedDocs.any(scanned.contains);
    final totalPages = selected
        .where((d) => !scanned.contains(d.id))
        .fold<int>(
          0,
          (sum, doc) =>
              sum + mapSelectedPages(doc, outlines[doc.id] ?? [], _range(doc.id, snapshot, wsState.activeMapId)).length,
        );
    final valid =
        selected.isNotEmpty &&
        !hasScanned &&
        !_selectedDocs.any((id) => _ranges.containsKey(id) && _ranges[id] == null);
    final summary = [
      switch (_depth) {
        2 => l.mapGenerateDetailBrief,
        3 => l.mapGenerateDetailMedium,
        _ => l.mapGenerateDetailFull,
      },
      if (_includeAnnotations && markCount > 0) l.mapGenerateMarksSummary(markCount),
      if (_extractQuotes) l.mapGenerateQuotes,
    ].join(' · ');
    Widget leftPane() => switch (_panel) {
      _GeneratePanel.main => _mainPane(selected, snapshot, wsState.activeMapId, outlines, scanned, summary),
      _GeneratePanel.documents => _documentsPane(documents, snapshot, scanned),
      _GeneratePanel.advanced => _advancedPane(hasNodes, markCount),
      _GeneratePanel.range => _rangePane(snapshot, wsState.activeMapId, outlines),
    };
    return CallbackShortcuts(
      bindings: {
        primaryShortcut(LogicalKeyboardKey.enter): _start,
        const SingleActivator(LogicalKeyboardKey.escape): _escape,
      },
      child: Focus(
        autofocus: true,
        child: Material(
          color: c.windowBackground,
          borderRadius: BorderRadius.circular(MMRadii.sheet),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= MMSizes.mapGenerateTwoPaneWidth;
              final available = constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : MediaQuery.sizeOf(context).height;
              final desired = context.mmTouchPlatform ? MMSizes.mapGenerateTouchHeight : MMSizes.mapGenerateSheetHeight;
              return SizedBox(
                height: available.clamp(0.0, desired),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(MMSpacing.xl, MMSpacing.m, MMSpacing.m, MMSpacing.m),
                      child: Row(
                        children: [
                          Icon(MMIcons.generateMap, size: 16, color: c.research),
                          const SizedBox(width: MMSpacing.s),
                          Expanded(child: Text(l.mapGenerate, style: t.title3)),
                          MMIconButton(
                            icon: MMIcons.close,
                            tooltip: l.closePanel,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, thickness: MMSizes.hairline, color: c.separator),
                    if (_needsSetup)
                      const Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.all(MMSpacing.xl),
                          child: ModelSetupCard(inline: true),
                        ),
                      )
                    else
                      Expanded(
                        child: wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(
                                    width: MMSizes.mapGenerateSettingsWidth,
                                    child: SingleChildScrollView(
                                      key: ValueKey('map-generate-pane-${_panel.name}'),
                                      padding: const EdgeInsets.all(MMSpacing.xl),
                                      child: leftPane(),
                                    ),
                                  ),
                                  VerticalDivider(width: 1, thickness: MMSizes.hairline, color: c.separator),
                                  Expanded(child: _previewPane()),
                                ],
                              )
                            : SingleChildScrollView(
                                key: ValueKey('map-generate-compact-${_panel.name}'),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Padding(padding: const EdgeInsets.all(MMSpacing.xl), child: leftPane()),
                                    Divider(height: 1, thickness: MMSizes.hairline, color: c.separator),
                                    SizedBox(height: MMSizes.mapGenerateCompactPreviewHeight, child: _previewPane()),
                                  ],
                                ),
                              ),
                      ),
                    Divider(height: 1, thickness: MMSizes.hairline, color: c.separator),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: MMSpacing.xl, vertical: MMSpacing.m),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _destination == 'new' ? l.mapGenerateDestinationNew : l.mapGenerateDestinationBranch,
                                  style: t.footnote.copyWith(color: c.secondaryLabel),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (!_needsSetup)
                                  Text(
                                    l.mapGeneratePages(totalPages),
                                    key: const ValueKey('map-range-page-count'),
                                    style: t.footnote.copyWith(color: c.secondaryLabel),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: MMSpacing.s),
                          MMButton(label: l.cancel, onPressed: () => Navigator.of(context).pop()),
                          if (!_needsSetup) ...[
                            const SizedBox(width: MMSpacing.s),
                            Tooltip(
                              message: hasScanned ? l.mapBannerNeedsOcr : '',
                              child: MMButton(
                                key: const ValueKey('map-generate-sheet-start-button'),
                                label: l.mapGenerateStart,
                                color: c.research,
                                variant: MMButtonVariant.primary,
                                onPressed: valid && _panel != _GeneratePanel.documents ? _start : null,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _heading(String label, {Widget? trailing}) => Row(
    children: [
      Expanded(child: Text(label, style: context.mmText.headline)),
      ?trailing,
    ],
  );

  Widget _subheading(String label, {Widget? trailing}) => Row(
    children: [
      MMIconButton(icon: MMIcons.chevronLeft, tooltip: context.l10n.back, onPressed: _back),
      const SizedBox(width: MMSpacing.xs),
      Expanded(child: Text(label, style: context.mmText.headline)),
      ?trailing,
    ],
  );

  Widget _mainPane(
    List<Document> selected,
    StudySetContent content,
    String mapId,
    Map<String, List<PdfOutlineEntry>> outlines,
    Set<String> scanned,
    String summary,
  ) {
    final l = context.l10n, c = context.mmColors, t = context.mmText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          l.mapGenerateSource,
          trailing: MMButton(
            key: const ValueKey('map-generate-change-sources'),
            label: l.mapGenerateChangeSources,
            variant: MMButtonVariant.plain,
            color: c.research,
            onPressed: _openDocuments,
          ),
        ),
        const SizedBox(height: MMSpacing.m),
        if (selected.isEmpty)
          Text(l.mapGenerateNoSources, style: t.bodySecondary)
        else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                scanned.contains(selected.first.id)
                    ? MMReaderIcons.area
                    : selected.first.format == DocumentFormat.pdf
                    ? MMIcons.document
                    : MMIcons.ebook,
                size: 18,
                color: c.secondaryLabel,
              ),
              const SizedBox(width: MMSpacing.s),
              Expanded(
                child: Text(selected.first.title, style: t.body, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: MMSpacing.s),
          Align(
            alignment: Alignment.centerLeft,
            child: scanned.contains(selected.first.id)
                ? Text(l.mapGenerateNeedsOcr, style: t.callout.copyWith(color: c.caution))
                : _rangeButton(selected.first, content, mapId, outlines[selected.first.id] ?? []),
          ),
          if (selected.length > 1)
            Align(
              alignment: Alignment.centerLeft,
              child: MMButton(
                key: const ValueKey('map-generate-source-summary'),
                label: l.mapGenerateSourceCount(selected.length),
                variant: MMButtonVariant.plain,
                color: c.research,
                onPressed: _openDocuments,
              ),
            ),
        ],
        const SizedBox(height: MMSpacing.l),
        Divider(height: 1, thickness: MMSizes.hairline, color: c.separator),
        const SizedBox(height: MMSpacing.l),
        Text(l.mapGenerateOrganization, style: t.headline),
        const SizedBox(height: MMSpacing.s),
        Column(
          key: const ValueKey('map-generate-organization'),
          children: [
            for (final org in MapOrganization.values)
              Semantics(
                inMutuallyExclusiveGroup: true,
                checked: _organization == org,
                child: MMInteractive(
                  key: ValueKey('map-generate-organization-${org.name}'),
                  semanticLabel: _organizationLabel(org),
                  selected: _organization == org,
                  onTap: () => setState(() {
                    _organization = org;
                    _userTouchedOrganization = true;
                  }),
                  builder: (context, state) => Container(
                    constraints: BoxConstraints(minHeight: context.mmTouchPlatform ? MMSizes.touchTarget : 30),
                    padding: const EdgeInsets.symmetric(vertical: MMSpacing.xs),
                    decoration: BoxDecoration(
                      color: state.hovered ? c.hover : null,
                      borderRadius: BorderRadius.circular(MMRadii.row),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _organization == org ? MMIcons.success : MMIcons.inkEllipse,
                          size: 16,
                          color: _organization == org ? c.research : c.secondaryLabel,
                        ),
                        const SizedBox(width: MMSpacing.s),
                        Expanded(child: Text(_organizationLabel(org), style: t.body)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: MMSpacing.l),
        Divider(height: 1, thickness: MMSizes.hairline, color: c.separator),
        const SizedBox(height: MMSpacing.m),
        Align(
          alignment: Alignment.centerLeft,
          child: MMButton(
            key: const ValueKey('map-generate-more-settings'),
            label: l.mapGenerateMoreSettings,
            icon: MMIcons.chevronDown,
            variant: MMButtonVariant.plain,
            onPressed: () => setState(() => _panel = _GeneratePanel.advanced),
          ),
        ),
        Text(summary, style: t.footnote.copyWith(color: c.secondaryLabel), maxLines: 2),
      ],
    );
  }

  String _organizationLabel(MapOrganization org) => switch (org) {
    MapOrganization.chapter => context.l10n.mapGenerateByChapter,
    MapOrganization.topic =>
      _selectedDocs.length > 1 ? context.l10n.mapGenerateMergeByTopic : context.l10n.mapGenerateByTopic,
    MapOrganization.question => context.l10n.mapGenerateByQuestion,
  };

  Widget _rangeButton(Document doc, StudySetContent content, String mapId, List<PdfOutlineEntry> entries) {
    final l = context.l10n;
    final range = _range(doc.id, content, mapId);
    final pages = l.mapGeneratePages(mapSelectedPages(doc, entries, range).length);
    final label = range?.isEmpty == true
        ? '${l.mapGenerateWholeDocument} · $pages'
        : entries.isNotEmpty
        ? '${l.mapGenerateChapterCount(mapSelectedChapters(entries, range).length, entries.length)} · $pages'
        : pages;
    return MMButton(
      key: ValueKey('map-range-toggle-${doc.id}'),
      label: label,
      icon: MMIcons.chevronDown,
      variant: MMButtonVariant.plain,
      color: context.mmColors.secondaryLabel,
      onPressed: () => setState(() {
        _expandedDocument = doc.id;
        _panel = _GeneratePanel.range;
      }),
    );
  }

  Widget _documentsPane(List<Document> documents, StudySetContent content, Set<String> scanned) {
    final l = context.l10n, t = context.mmText, c = context.mmColors;
    final query = _searchController.text.trim().toLowerCase();
    final filtered = documents.where((d) => d.title.toLowerCase().contains(query)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _subheading(
          l.mapGenerateSelectSources,
          trailing: MMButton(
            key: const ValueKey('map-generate-apply-sources'),
            label: l.done,
            variant: MMButtonVariant.plain,
            color: c.research,
            onPressed: _documentDraft.isEmpty ? null : () => _applyDocuments(content),
          ),
        ),
        const SizedBox(height: MMSpacing.m),
        MMSearchField(
          controller: _searchController,
          placeholder: l.searchInSet,
          onChanged: (_) => setState(() {}),
          onEscape: _back,
        ),
        const SizedBox(height: MMSpacing.s),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.all(MMSpacing.l),
            child: Text(l.noResults, style: t.bodySecondary),
          ),
        for (final doc in filtered) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: MMSpacing.s),
            child: Row(
              children: [
                MMCheckbox(
                  key: ValueKey('map-document-check-${doc.id}'),
                  value: _documentDraft.contains(doc.id),
                  semanticLabel: doc.title,
                  color: c.research,
                  onChanged: (checked) => setState(() {
                    if (checked) {
                      _documentDraft.add(doc.id);
                    } else {
                      _documentDraft.remove(doc.id);
                    }
                  }),
                ),
                const SizedBox(width: MMSpacing.s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(doc.title, style: t.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: MMSpacing.xs),
                      Text(
                        scanned.contains(doc.id) ? l.mapGenerateNeedsOcr : l.mapGeneratePages(doc.pageCount),
                        style: t.footnote.copyWith(color: scanned.contains(doc.id) ? c.caution : c.secondaryLabel),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: MMSizes.hairline, color: c.separator),
        ],
      ],
    );
  }

  Widget _advancedPane(bool hasNodes, int markCount) {
    final l = context.l10n, t = context.mmText, c = context.mmColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _subheading(
          l.mapGenerateMoreSettings,
          trailing: MMButton(
            label: l.done,
            key: const ValueKey('map-generate-settings-done'),
            variant: MMButtonVariant.plain,
            color: c.research,
            onPressed: _back,
          ),
        ),
        const SizedBox(height: MMSpacing.l),
        Text(l.mapGenerateDetail, style: t.headline),
        const SizedBox(height: MMSpacing.s),
        MMSegmentedControl<int>(
          key: const ValueKey('map-generate-detail'),
          value: _depth,
          expand: true,
          onChanged: (d) => setState(() => _depth = d),
          segments: [
            MMSegment(value: 2, label: l.mapGenerateDetailBrief),
            MMSegment(value: 3, label: l.mapGenerateDetailMedium),
            MMSegment(value: 4, label: l.mapGenerateDetailFull),
          ],
        ),
        const SizedBox(height: MMSpacing.s),
        Text(l.mapGenerateStructureDepth(_depth), style: t.footnote.copyWith(color: c.secondaryLabel)),
        const SizedBox(height: MMSpacing.xl),
        Text(l.mapGenerateContent, style: t.headline),
        const SizedBox(height: MMSpacing.s),
        _switchRow(
          '${l.mapGenerateMyMarks} · ${l.mapGenerateMarkCount(markCount)}',
          _includeAnnotations,
          l.mapGenerateMyMarks,
          (value) => setState(() => _includeAnnotations = value),
        ),
        _switchRow(
          l.mapGenerateQuotes,
          _extractQuotes,
          l.mapGenerateQuotes,
          (value) => setState(() => _extractQuotes = value),
        ),
        const SizedBox(height: MMSpacing.l),
        Text(l.mapGenerateTarget, style: t.headline),
        const SizedBox(height: MMSpacing.s),
        Align(
          alignment: Alignment.centerLeft,
          child: MMDropdownButton<String>(
            key: const ValueKey('map-generate-target-dropdown'),
            child: Text(_destination == 'new' ? l.mapGenerateTargetNew : l.mapGenerateTargetBranch),
            onSelected: (value) => setState(() => _destination = value),
            itemBuilder: (_) => [
              MMDropdownItem(value: 'new', child: Text(l.mapGenerateTargetNew)),
              if (hasNodes) MMDropdownItem(value: 'branch', child: Text(l.mapGenerateTargetBranch)),
            ],
          ),
        ),
        if (_destination == 'new') ...[
          const SizedBox(height: MMSpacing.l),
          Text(l.mapGenerateMapTitle, style: t.headline),
          const SizedBox(height: MMSpacing.s),
          MMTextField(
            key: const ValueKey('map-generate-target-title'),
            controller: _titleController,
            semanticLabel: l.mapGenerateMapTitle,
          ),
        ],
      ],
    );
  }

  Widget _switchRow(String label, bool value, String semanticLabel, ValueChanged<bool> onChanged) => Padding(
    padding: const EdgeInsets.symmetric(vertical: MMSpacing.xs),
    child: Row(
      children: [
        Expanded(child: Text(label, style: context.mmText.body)),
        const SizedBox(width: MMSpacing.s),
        MMSwitch(value: value, semanticLabel: semanticLabel, color: context.mmColors.research, onChanged: onChanged),
      ],
    ),
  );

  Widget _rangePane(StudySetContent content, String mapId, Map<String, List<PdfOutlineEntry>> outlines) {
    final doc = content.document(_expandedDocument ?? '');
    if (doc == null) return const SizedBox.shrink();
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _subheading(
          l.mapGenerateSourceRange,
          trailing: MMButton(
            label: l.done,
            variant: MMButtonVariant.plain,
            key: const ValueKey('map-generate-range-done'),
            onPressed: _back,
          ),
        ),
        const SizedBox(height: MMSpacing.m),
        Text(doc.title, style: context.mmText.body, maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: MMSpacing.m),
        Align(
          alignment: Alignment.centerLeft,
          child: MMButton(
            label: l.mapGenerateResetRange,
            variant: MMButtonVariant.plain,
            color: context.mmColors.research,
            onPressed: () => setState(() {
              _ranges[doc.id] = [];
              _rangeRevision++;
            }),
          ),
        ),
        const SizedBox(height: MMSpacing.s),
        MapSourceRange(
          key: ValueKey('map-range-${doc.id}-$_rangeRevision'),
          document: doc,
          entries: outlines[doc.id] ?? [],
          selection: _range(doc.id, content, mapId),
          onChanged: (value) => setState(() => _ranges[doc.id] = value),
        ),
      ],
    );
  }

  Widget _previewPane() {
    final l = context.l10n, c = context.mmColors;
    return ColoredBox(
      color: c.quaternaryFill,
      child: Padding(
        padding: const EdgeInsets.all(MMSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.mapGenerateStructurePreview, style: context.mmText.headline.copyWith(color: c.secondaryLabel)),
            const SizedBox(height: MMSpacing.l),
            Expanded(
              child: MapGenerationStructurePreview(organization: _organization, depth: _depth),
            ),
            const SizedBox(height: MMSpacing.m),
            Text(
              l.mapGeneratePreviewDisclaimer,
              textAlign: TextAlign.center,
              style: context.mmText.footnote.copyWith(color: c.secondaryLabel),
            ),
            const SizedBox(height: MMSpacing.l),
            MMTextField(
              key: const ValueKey('map-generate-instructions'),
              controller: _instructionsController,
              semanticLabel: l.mapGenerateInstructions,
              placeholder: l.mapGenerateInstructionsHint,
              minLines: 2,
              maxLines: 3,
              onChanged: widget.onInstructionsChanged,
            ),
          ],
        ),
      ),
    );
  }
}
