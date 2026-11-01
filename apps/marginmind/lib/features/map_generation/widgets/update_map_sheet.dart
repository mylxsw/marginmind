import '../../assistant/map_task_route.dart';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../../shared/l10n.dart';
import '../../assistant/widgets/assistant_panel.dart' show ModelSetupCard;
import '../../workspace/workspace_controller.dart';
import '../map_generation_controller.dart';

Future<void> showUpdateMapSheet(BuildContext context, String studySetId, String mapId) => showMMSheet<void>(
  context: context,
  width: MMSizes.mapUpdatePopoverWidth,
  builder: (_) => UpdateMapSheet(studySetId: studySetId, mapId: mapId),
);

class UpdateMapSheet extends ConsumerStatefulWidget {
  const UpdateMapSheet({super.key, required this.studySetId, required this.mapId});
  final String studySetId, mapId;
  @override
  ConsumerState<UpdateMapSheet> createState() => _UpdateMapSheetState();
}

class _UpdateMapSheetState extends ConsumerState<UpdateMapSheet> {
  late final TextEditingController _instructions;
  late final Set<String> _documents;
  final _sourceScroll = ScrollController();
  final _bodyScroll = ScrollController();
  bool _onlyNew = true, _needsSetup = false, _starting = false;

  @override
  void initState() {
    super.initState();
    final g = ref.read(workspaceProvider(widget.studySetId).notifier).content.map(widget.mapId)!.generation!;
    _instructions = TextEditingController(text: g.instructions);
    final content = ref.read(workspaceProvider(widget.studySetId).notifier).content;
    _documents = g.sources.where((s) => content.document(s.documentId) != null).map((s) => s.documentId).toSet();
  }

  @override
  void dispose() {
    _instructions.dispose();
    _sourceScroll.dispose();
    _bodyScroll.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_starting || _documents.isEmpty) return;
    setState(() => _starting = true);
    final configured = await ref.read(mapTaskReadyProvider((widget.studySetId, TaskType.mapGenerate)).future);
    if (!mounted) return;
    if (!configured) {
      setState(() {
        _needsSetup = true;
        _starting = false;
      });
      if (_bodyScroll.hasClients) _bodyScroll.jumpTo(0);
      return;
    }
    final c = ref.read(workspaceProvider(widget.studySetId).notifier).content;
    final map = c.map(widget.mapId)!;
    final g = map.generation!;
    final request = MapGenerationRequest(
      studySetId: widget.studySetId,
      mapId: map.id,
      title: map.title,
      sources: [
        for (final id in _documents)
          if (c.document(id) != null)
            MapDocumentSelection(
              documentId: id,
              chapters: g.sources.where((s) => s.documentId == id).firstOrNull?.chapters ?? const [],
            ),
      ],
      organization: g.organization,
      depth: g.depth,
      instructions: _instructions.text.trim(),
      destination: MapGenerationDestination.update,
      onlyNewContent: _onlyNew,
    );
    if (request.sources.isEmpty) {
      setState(() => _starting = false);
      return;
    }
    ref.read(mapGenerationControllerProvider(widget.studySetId).notifier).start(request);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c =
        ref.watch(workspaceContentProvider(widget.studySetId)) ??
        ref.read(workspaceProvider(widget.studySetId).notifier).content;
    final g = c.map(widget.mapId)!.generation!;
    final l = context.l10n;
    final protected = c.nodes
        .where((n) => n.mapId == widget.mapId && isMapNodeProtected(c, widget.mapId, n.cardId))
        .length;
    final highlights = c.annotations
        .where((a) => _documents.contains(a.documentId) && a.createdAt.isAfter(g.generatedAt))
        .length;
    final notes = c.marginNotes
        .where((n) => _documents.contains(n.documentId) && n.createdAt.isAfter(g.generatedAt))
        .length;
    final colors = context.mmColors, text = context.mmText;
    void close() => Navigator.of(context).pop();
    return CallbackShortcuts(
      bindings: {
        primaryShortcut(LogicalKeyboardKey.enter): _start,
        const SingleActivator(LogicalKeyboardKey.escape): close,
      },
      child: Focus(
        autofocus: true,
        child: Material(
          color: colors.windowBackground,
          borderRadius: BorderRadius.circular(MMRadii.sheet),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (context, constraints) => ConstrainedBox(
              constraints: BoxConstraints(maxHeight: constraints.maxHeight.clamp(0.0, 700.0)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 16, 12, 16),
                    child: Row(
                      children: [
                        Icon(MMIcons.generateMap, size: 20, color: colors.research),
                        const SizedBox(width: MMSpacing.m),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Semantics(header: true, child: Text(l.mapUpdateTitle, style: text.title3)),
                              const SizedBox(height: MMSpacing.xs),
                              Text(
                                c.map(widget.mapId)!.title.trim().isEmpty ? l.mainMap : c.map(widget.mapId)!.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.footnote.copyWith(color: colors.secondaryLabel),
                              ),
                            ],
                          ),
                        ),
                        MMIconButton(
                          key: const ValueKey('map-update-close'),
                          icon: MMIcons.close,
                          tooltip: l.closePanel,
                          onPressed: close,
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, thickness: MMSizes.hairline, color: colors.separator),
                  Flexible(
                    child: SingleChildScrollView(
                      key: const ValueKey('map-update-body'),
                      controller: _bodyScroll,
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Text(l.aiTasksModel),
                              const SizedBox(width: MMSpacing.m),
                              Expanded(
                                child: MapTaskRoute(studySetId: widget.studySetId, type: TaskType.mapGenerate),
                              ),
                            ],
                          ),
                          const SizedBox(height: MMSpacing.l),
                          if (_needsSetup) ...[const ModelSetupCard(inline: true), const SizedBox(height: MMSpacing.m)],
                          Text(l.mapUpdateDescription, style: text.callout.copyWith(color: colors.secondaryLabel)),
                          const SizedBox(height: MMSpacing.l),
                          _heading(l.mapUpdateSources),
                          Container(
                            decoration: BoxDecoration(
                              color: colors.surface,
                              border: Border.all(color: colors.separator, width: MMSizes.hairline),
                              borderRadius: BorderRadius.circular(MMRadii.row),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 192),
                              child: Scrollbar(
                                controller: _sourceScroll,
                                child: SingleChildScrollView(
                                  controller: _sourceScroll,
                                  child: Column(
                                    children: [
                                      for (var i = 0; i < c.documents.length; i++) ...[
                                        if (i > 0)
                                          Divider(height: 1, thickness: MMSizes.hairline, color: colors.separator),
                                        _document(c.documents[i], g),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: MMSpacing.l),
                          _heading(l.mapUpdateSince),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: colors.surface,
                              borderRadius: BorderRadius.circular(MMRadii.row),
                            ),
                            child: Row(
                              children: [
                                Expanded(child: _stat(l.mapUpdateNewHighlights, highlights, MMIcons.highlight)),
                                const SizedBox(width: MMSpacing.m),
                                Expanded(child: _stat(l.mapUpdateNewNotes, notes, MMIcons.organizeNote)),
                              ],
                            ),
                          ),
                          const SizedBox(height: MMSpacing.l),
                          _heading(l.mapUpdateScope),
                          MMDropdownButton<bool>(
                            key: const ValueKey('map-update-scope'),
                            enabled: !_starting,
                            tooltip: l.mapUpdateScope,
                            onSelected: (v) => setState(() => _onlyNew = v),
                            itemBuilder: (_) => [
                              MMDropdownItem(value: true, child: Text(l.mapUpdateScopeNew)),
                              MMDropdownItem(value: false, child: Text(l.mapUpdateScopeAll)),
                            ],
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                color: colors.surface,
                                border: Border.all(color: colors.separator, width: MMSizes.hairline),
                                borderRadius: BorderRadius.circular(MMRadii.row),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(_onlyNew ? l.mapUpdateScopeNew : l.mapUpdateScopeAll, style: text.body),
                                  ),
                                  const Icon(MMIcons.chevronDown, size: 12),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: MMSpacing.l),
                          _heading(l.mapGenerateInstructions),
                          MMTextField(
                            controller: _instructions,
                            placeholder: l.mapGenerateInstructionsHint,
                            maxLines: 3,
                          ),
                          const SizedBox(height: MMSpacing.m),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(MMIcons.shield, size: 14, color: colors.secondaryLabel),
                              const SizedBox(width: MMSpacing.s),
                              Expanded(
                                child: Text(
                                  l.mapUpdateProtected(protected),
                                  style: text.footnote.copyWith(color: colors.secondaryLabel),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Divider(height: 1, thickness: MMSizes.hairline, color: colors.separator),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        MMButton(key: const ValueKey('map-update-cancel'), label: l.cancel, onPressed: close),
                        const SizedBox(width: MMSpacing.s),
                        MMButton(
                          key: const ValueKey('map-update-preview'),
                          label: l.mapUpdatePreview,
                          variant: MMButtonVariant.primary,
                          onPressed: _starting || _documents.isEmpty ? null : _start,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading(String label) => Padding(
    padding: const EdgeInsets.only(bottom: MMSpacing.s),
    child: Text(label, style: context.mmText.headline),
  );

  Widget _stat(String label, int value, IconData icon) => Row(
    children: [
      Icon(icon, size: 16, color: context.mmColors.secondaryLabel),
      const SizedBox(width: MMSpacing.s),
      Expanded(child: Text(label, style: context.mmText.callout)),
      const SizedBox(width: MMSpacing.xs),
      Text('$value', style: context.mmText.headline),
    ],
  );

  Widget _document(Document doc, MapGeneration generation) {
    final source = generation.sources.where((s) => s.documentId == doc.id).firstOrNull;
    final selected = _documents.contains(doc.id);
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: MMCheckbox(
              value: selected,
              label: doc.title,
              onChanged: _starting
                  ? null
                  : (value) => setState(() {
                      if (value) {
                        _documents.add(doc.id);
                      } else {
                        _documents.remove(doc.id);
                      }
                    }),
            ),
          ),
          if (selected && source != null) ...[
            const SizedBox(height: MMSpacing.xs),
            Padding(
              padding: const EdgeInsets.only(left: 23),
              child: Text(
                doc.lastPage > source.readThrough
                    ? '${l.mapUpdateReadTo}  ${l.mapUpdateReadRange(source.readThrough, doc.lastPage)}'
                    : l.mapUpdateReadBaseline(source.readThrough),
                style: context.mmText.footnote.copyWith(color: context.mmColors.secondaryLabel),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
