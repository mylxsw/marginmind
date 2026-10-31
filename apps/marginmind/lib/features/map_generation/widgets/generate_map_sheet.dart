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
import '../map_generation_controller.dart';

Future<void> showGenerateMapSheet(
  BuildContext context,
  WidgetRef ref,
  String studySetId, {
  String? preselectedDocId,
  String initialInstructions = '',
  ValueChanged<String>? onInstructionsChanged,
}) async {
  await showMMSheet<void>(
    context: context,
    width: MMSizes.mapGenerateSheetWidth,
    builder: (_) => GenerateMapSheet(
      studySetId: studySetId,
      preselectedDocId: preselectedDocId,
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
    this.initialInstructions = '',
    this.onInstructionsChanged,
  });

  final String studySetId;
  final String? preselectedDocId;
  final String initialInstructions;
  final ValueChanged<String>? onInstructionsChanged;

  @override
  ConsumerState<GenerateMapSheet> createState() => _GenerateMapSheetState();
}

class _GenerateMapSheetState extends ConsumerState<GenerateMapSheet> {
  final _selectedDocs = <String>{};
  MapOrganization _organization = MapOrganization.chapter;
  bool _userTouchedOrganization = false;
  int _depth = 3;
  bool _includeAnnotations = true;
  String _destination = 'new'; // 'new' or 'branch'
  late final TextEditingController _titleController;
  late final TextEditingController _instructionsController;

  @override
  void initState() {
    super.initState();
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

  void _start() {
    if (_selectedDocs.isEmpty) return;
    final workspace = ref.read(workspaceProvider(widget.studySetId).notifier);
    final snapshot = workspace.content;

    _savePrefs();

    final wsState = ref.read(workspaceProvider(widget.studySetId));
    final isNewMap = _destination == 'new';
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
            sources: [for (final id in _selectedDocs) MapDocumentSelection(documentId: id)],
            organization: _organization,
            depth: _depth,
            instructions: text.isEmpty ? null : text,
            includeAnnotations: _includeAnnotations,
            destination: isNewMap ? MapGenerationDestination.newMap : MapGenerationDestination.branch,
            parentId: isNewMap ? null : targetMapId,
          ),
        );

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;

    final credential = ref.watch(assistantCredentialStateProvider).value;
    final isUnconfigured =
        credential == AssistantCredentialState.unavailable || credential == AssistantCredentialState.missingKey;

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

    // Total pages
    final totalPages = _selectedDocs.fold<int>(0, (sum, id) => sum + (snapshot.document(id)?.pageCount ?? 0));

    return CallbackShortcuts(
      bindings: {primaryShortcut(LogicalKeyboardKey.enter): _start},
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.all(20),
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

                                  return SizedBox(
                                    height: MMSizes.mapGenerateDocumentRow,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      child: Row(
                                        children: [
                                          MMCheckbox(
                                            value: isSelected,
                                            color: c.research,
                                            semanticLabel: doc.title,
                                            onChanged: isLast ? null : (val) => _onToggleDoc(doc.id, val),
                                          ),
                                          const SizedBox(width: 10),
                                          Icon(
                                            doc.format == DocumentFormat.pdf ? MMIcons.document : MMIcons.ebook,
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
                                          if (hasMap) ...[
                                            Icon(MMIcons.mindMap, size: 12, color: c.secondaryLabel),
                                            const SizedBox(width: 6),
                                          ],
                                          Text(
                                            l.mapGeneratePages(doc.pageCount),
                                            style: t.callout.copyWith(color: c.secondaryLabel),
                                          ),
                                        ],
                                      ),
                                    ),
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
                                    MMSwitch(value: false, semanticLabel: l.mapGenerateQuotes, onChanged: null),
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
                                child: Text(_destination == 'new' ? l.mapGenerateTargetNew : l.mapGenerateTargetBranch),
                                onSelected: (val) => setState(() => _destination = val),
                                itemBuilder: (_) => [
                                  MMDropdownItem(value: 'new', child: Text(l.mapGenerateTargetNew)),
                                  if (hasNodes) MMDropdownItem(value: 'branch', child: Text(l.mapGenerateTargetBranch)),
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
                            maxLength: 500,
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
                    Text(l.mapGeneratePages(totalPages), style: t.callout.copyWith(color: c.secondaryLabel)),
                    const Spacer(),
                    MMButton(
                      label: l.cancel,
                      variant: MMButtonVariant.secondary,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    MMButton(
                      key: const ValueKey('map-generate-sheet-start-button'),
                      label: l.mapGenerateStart,
                      color: c.research,
                      variant: MMButtonVariant.primary,
                      onPressed: _start,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
