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
    super.dispose();
  }

  Future<void> _savePrefs() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final key = 'map_gen.${widget.studySetId}';
    await prefs.setString('$key.organization', _organization.name);
    await prefs.setInt('$key.depth', _depth);
    await prefs.setBool('$key.includeAnnotations', _includeAnnotations);
  }

  void _onToggleDoc(String docId, bool selected) {
    if (!selected && _selectedDocs.length <= 1) return;
    setState(() {
      if (selected) {
        _selectedDocs.add(docId);
      } else {
        _selectedDocs.remove(docId);
      }
      _expandedDocument = null;
      if (!_userTouchedOrganization) {
        _organization = _selectedDocs.length > 1 ? MapOrganization.topic : MapOrganization.chapter;
      }
    });
  }

  int _estimateCount(int depth) => switch (depth) {
    2 => 20,
    3 => 40,
    _ => 80,
  };

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
    if (_selectedDocs.isEmpty ||
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
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;

    final isUnconfigured = _needsSetup;

    final loaded = ref.watch(workspaceContentProvider(widget.studySetId));
    final workspace = ref.read(workspaceProvider(widget.studySetId).notifier);
    final snapshot = loaded ?? workspace.content;
    final documents = snapshot.documents;

    final wsState = ref.watch(workspaceProvider(widget.studySetId));
    final hasNodes = snapshot.nodes.any((n) => n.mapId == wsState.activeMapId);

    if (_selectedDocs.isEmpty && documents.isNotEmpty) {
      final active = wsState.activeDocumentId;
      if (active != null && snapshot.document(active) != null) {
        _selectedDocs.add(active);
      } else {
        _selectedDocs.add(documents.first.id);
      }
      if (_titleController.text.isEmpty) {
        _titleController.text = snapshot.document(_selectedDocs.first)?.title ?? '';
      }
    }

    // Compute mark count on selected docs
    final markCount = snapshot.annotations.where((a) => _selectedDocs.contains(a.documentId)).length;

    final outlines = <String, List<PdfOutlineEntry>>{};
    final scanned = <String>{};
    for (final doc in documents) {
      if (_selectedDocs.contains(doc.id)) {
        outlines[doc.id] = ref.watch(mapDocumentOutlineProvider((widget.studySetId, doc.id))).value ?? [];
      }
      if (doc.format == DocumentFormat.pdf) {
        final source = workspace.filePath(doc);
        ref.watch(readerOcrInspectionProvider(source));
        final ocr = ref.watch(readerOcrProvider(source));
        if (ocr.document?.textPages.isEmpty == true) scanned.add(doc.id);
      }
    }
    final hasScanned = _selectedDocs.any(scanned.contains);
    final totalPages = documents
        .where((doc) => _selectedDocs.contains(doc.id) && !scanned.contains(doc.id))
        .fold<int>(
          0,
          (sum, doc) =>
              sum + mapSelectedPages(doc, outlines[doc.id] ?? [], _range(doc.id, snapshot, wsState.activeMapId)).length,
        );

    return CallbackShortcuts(
      bindings: {primaryShortcut(LogicalKeyboardKey.enter): _start},
      child: Material(
        color: c.windowBackground,
        borderRadius: BorderRadius.circular(MMRadii.sheet),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Icon(MMIcons.generateMap, size: 16, color: c.research),
                    const SizedBox(width: 8),
                    Text(l.mapGenerate, style: t.title3.copyWith(color: c.label)),
                  ],
                ),
                const SizedBox(height: 16),

                if (isUnconfigured) ...[
                  const Center(child: SizedBox(width: 360, child: ModelSetupCard(inline: true))),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: MMButton(
                      label: l.cancel,
                      variant: MMButtonVariant.secondary,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ] else ...[
                  // Form Rows
                  Table(
                    columnWidths: const {0: FixedColumnWidth(MMSizes.mapGenerateLabelWidth), 1: FlexColumnWidth()},
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: [
                      // Documents row
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 14, top: 6, bottom: 14),
                            child: Align(
                              alignment: Alignment.topRight,
                              child: Text(l.mapGenerateDocuments, style: t.body.copyWith(color: c.secondaryLabel)),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Container(
                              constraints: BoxConstraints(maxHeight: 5 * MMSizes.mapGenerateDocumentRow),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: c.separator, width: 1),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(9),
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  padding: EdgeInsets.zero,
                                  itemCount: documents.length,
                                  separatorBuilder: (_, _) => Divider(height: 1, color: c.separator),
                                  itemBuilder: (context, index) {
                                    final doc = documents[index];
                                    final isSelected = _selectedDocs.contains(doc.id);
                                    final isLast = isSelected && _selectedDocs.length == 1;
                                    final hasMap = snapshot.maps.any(
                                      (m) => m.generation?.sources.any((s) => s.documentId == doc.id) == true,
                                    );

                                    final range = _range(doc.id, snapshot, wsState.activeMapId);
                                    final entries = outlines[doc.id] ?? <PdfOutlineEntry>[];
                                    final single = isSelected && _selectedDocs.length == 1;
                                    final isScanned = scanned.contains(doc.id);
                                    final partial = isSelected && range?.isNotEmpty == true;
                                    final count = mapSelectedChapters(entries, range).length;
                                    final label = range?.isEmpty == true
                                        ? l.mapGenerateWholeDocument
                                        : entries.isNotEmpty
                                        ? l.mapGenerateChapterCount(count, entries.length)
                                        : l.mapGeneratePages(mapSelectedPages(doc, entries, range).length);
                                    return Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          height: MMSizes.mapGenerateDocumentRow,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 10),
                                            child: Row(
                                              children: [
                                                MMCheckbox(
                                                  key: ValueKey('map-document-check-${doc.id}'),
                                                  value: isSelected && range != null,
                                                  mixed: partial,
                                                  color: c.research,
                                                  semanticLabel: doc.title,
                                                  onChanged: isSelected && (partial || range == null)
                                                      ? (_) => setState(() => _ranges[doc.id] = [])
                                                      : isLast
                                                      ? null
                                                      : (val) => _onToggleDoc(doc.id, val),
                                                ),
                                                const SizedBox(width: 10),
                                                Icon(
                                                  isScanned
                                                      ? MMReaderIcons.area
                                                      : doc.format == DocumentFormat.pdf
                                                      ? MMIcons.document
                                                      : MMIcons.ebook,
                                                  size: 14,
                                                  color: c.icon,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    doc.title,
                                                    style: t.body,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (single && !isScanned) ...[
                                                  MMInteractive(
                                                    key: ValueKey('map-range-toggle-${doc.id}'),
                                                    semanticLabel: label,
                                                    onTap: () => setState(
                                                      () => _expandedDocument = _expandedDocument == doc.id
                                                          ? null
                                                          : doc.id,
                                                    ),
                                                    builder: (context, state) => Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Text(label, style: t.callout.copyWith(color: c.accent)),
                                                        const SizedBox(width: MMSpacing.xs),
                                                        Icon(MMIcons.chevronDown, size: 10, color: c.accent),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(width: MMSpacing.s),
                                                ],
                                                if (isScanned) ...[
                                                  Icon(MMIcons.warning, size: 12, color: c.caution),
                                                  const SizedBox(width: MMSpacing.xs),
                                                  Text(
                                                    l.mapGenerateNeedsOcr,
                                                    style: t.callout.copyWith(color: c.caution),
                                                  ),
                                                ] else ...[
                                                  if (hasMap) ...[
                                                    Icon(MMIcons.mindMap, size: 12, color: c.secondaryLabel),
                                                    const SizedBox(width: 6),
                                                  ],
                                                  Text(
                                                    l.mapGeneratePages(doc.pageCount),
                                                    style: t.callout.copyWith(color: c.secondaryLabel),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ),
                                        if (single && !isScanned && _expandedDocument == doc.id)
                                          MapSourceRange(
                                            key: ValueKey('map-range-${doc.id}'),
                                            document: doc,
                                            entries: entries,
                                            selection: range,
                                            onChanged: (value) => setState(() => _ranges[doc.id] = value),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Organization row
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 14, bottom: 14),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Text(l.mapGenerateOrganization, style: t.body.copyWith(color: c.secondaryLabel)),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: MMSegmentedControl<MapOrganization>(
                              key: const ValueKey('map-generate-organization'),
                              value: _organization,
                              expand: true,
                              onChanged: (org) {
                                setState(() {
                                  _organization = org;
                                  _userTouchedOrganization = true;
                                });
                              },
                              segments: [
                                MMSegment(value: MapOrganization.chapter, label: l.mapGenerateByChapter),
                                MMSegment(
                                  value: MapOrganization.topic,
                                  label: _selectedDocs.length > 1 ? l.mapGenerateMergeByTopic : l.mapGenerateByTopic,
                                ),
                                MMSegment(value: MapOrganization.question, label: l.mapGenerateByQuestion),
                              ],
                            ),
                          ),
                        ],
                      ),

                      // Detail row
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 14, bottom: 14),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Text(l.mapGenerateDetail, style: t.body.copyWith(color: c.secondaryLabel)),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: MMSegmentedControl<int>(
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
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  l.mapGenerateEstimate(_depth, _estimateCount(_depth)),
                                  style: t.callout.copyWith(color: c.secondaryLabel),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      // Content row
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 14, bottom: 14),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Text(l.mapGenerateContent, style: t.body.copyWith(color: c.secondaryLabel)),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  height: 26,
                                  child: Row(
                                    children: [
                                      Text(l.mapGenerateMyMarks, style: t.body),
                                      const SizedBox(width: 6),
                                      Text(
                                        l.mapGenerateMarkCount(markCount),
                                        style: t.footnote.copyWith(color: c.secondaryLabel),
                                      ),
                                      const Spacer(),
                                      MMSwitch(
                                        value: _includeAnnotations,
                                        semanticLabel: l.mapGenerateMyMarks,
                                        color: c.research,
                                        onChanged: (val) => setState(() => _includeAnnotations = val),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 6),
                                SizedBox(
                                  height: 26,
                                  child: Row(
                                    children: [
                                      Text(l.mapGenerateQuotes, style: t.body),
                                      const Spacer(),
                                      MMSwitch(
                                        value: _extractQuotes,
                                        color: c.research,
                                        semanticLabel: l.mapGenerateQuotes,
                                        onChanged: (value) => setState(() => _extractQuotes = value),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      // Target row
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 14, bottom: 14),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Text(l.mapGenerateTarget, style: t.body.copyWith(color: c.secondaryLabel)),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Row(
                              children: [
                                MMDropdownButton<String>(
                                  key: const ValueKey('map-generate-target-dropdown'),
                                  child: Text(
                                    _destination == 'new' ? l.mapGenerateTargetNew : l.mapGenerateTargetBranch,
                                  ),
                                  onSelected: (val) => setState(() => _destination = val),
                                  itemBuilder: (_) => [
                                    MMDropdownItem(value: 'new', child: Text(l.mapGenerateTargetNew)),
                                    if (hasNodes)
                                      MMDropdownItem(value: 'branch', child: Text(l.mapGenerateTargetBranch)),
                                  ],
                                ),
                                if (_destination == 'new') ...[
                                  const SizedBox(width: 12),
                                  SizedBox(
                                    width: 220,
                                    child: MMTextField(
                                      key: const ValueKey('map-generate-target-title'),
                                      controller: _titleController,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),

                      // Instructions row
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 14, top: 6),
                            child: Align(
                              alignment: Alignment.topRight,
                              child: Text(l.mapGenerateInstructions, style: t.body.copyWith(color: c.secondaryLabel)),
                            ),
                          ),
                          ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 60, maxHeight: 120),
                            child: TextField(
                              key: const ValueKey('map-generate-instructions'),
                              controller: _instructionsController,
                              minLines: 2,
                              maxLines: 6,
                              buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                              style: t.body,
                              decoration: InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: c.separator),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: c.separator),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: c.research),
                                ),
                                contentPadding: const EdgeInsets.all(10),
                              ),
                              onChanged: (text) {
                                widget.onInstructionsChanged?.call(text);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Footer
                  Row(
                    children: [
                      Icon(MMIcons.document, size: 14, color: c.secondaryLabel),
                      const SizedBox(width: 4),
                      Text(
                        l.mapGeneratePages(totalPages),
                        key: const ValueKey('map-range-page-count'),
                        style: t.callout.copyWith(color: c.secondaryLabel),
                      ),
                      const Spacer(),
                      MMButton(
                        label: l.cancel,
                        variant: MMButtonVariant.secondary,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: hasScanned ? l.mapBannerNeedsOcr : '',
                        child: MMButton(
                          key: const ValueKey('map-generate-sheet-start-button'),
                          label: l.mapGenerateStart,
                          color: c.research,
                          variant: MMButtonVariant.primary,
                          onPressed:
                              hasScanned || _selectedDocs.any((id) => _ranges.containsKey(id) && _ranges[id] == null)
                              ? null
                              : _start,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
