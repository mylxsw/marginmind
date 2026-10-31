import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../../shared/l10n.dart';
import '../../assistant/assistant_settings.dart';
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
  bool _onlyNew = true, _needsSetup = false, _starting = false;

  @override
  void initState() {
    super.initState();
    final g = ref.read(workspaceProvider(widget.studySetId).notifier).content.map(widget.mapId)!.generation!;
    _instructions = TextEditingController(text: g.instructions);
    _documents = g.sources.map((s) => s.documentId).toSet();
  }

  @override
  void dispose() {
    _instructions.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_starting || _documents.isEmpty) return;
    setState(() => _starting = true);
    final configured = await ref.read(assistantConfiguredProvider.future);
    if (!mounted) return;
    if (!configured) {
      setState(() {
        _needsSetup = true;
        _starting = false;
      });
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
    return CallbackShortcuts(
      bindings: {primaryShortcut(LogicalKeyboardKey.enter): _start},
      child: Material(
        color: context.mmColors.windowBackground,
        child: Padding(
          padding: const EdgeInsets.all(MMSpacing.l),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.mapUpdateTitle, style: context.mmText.headline),
                const SizedBox(height: MMSpacing.m),
                Text(l.mapUpdateSources, style: context.mmText.subheadline),
                for (final doc in c.documents)
                  Row(
                    children: [
                      MMCheckbox(
                        value: _documents.contains(doc.id),
                        onChanged: _starting
                            ? null
                            : (v) => setState(() {
                                if (v) {
                                  _documents.add(doc.id);
                                } else {
                                  _documents.remove(doc.id);
                                }
                              }),
                      ),
                      const SizedBox(width: MMSpacing.s),
                      Expanded(child: Text(doc.title, style: context.mmText.body)),
                    ],
                  ),
                const SizedBox(height: MMSpacing.m),
                Text(l.mapUpdateSince, style: context.mmText.subheadline),
                Text('${l.mapUpdateNewHighlights}  $highlights', style: context.mmText.body),
                Text('${l.mapUpdateNewNotes}  $notes', style: context.mmText.body),
                for (final source in g.sources)
                  if (c.document(source.documentId) case final doc?)
                    Text(
                      '${l.mapUpdateReadTo}  ${l.mapUpdateReadRange(source.readThrough, doc.lastPage)}',
                      style: context.mmText.body,
                    ),
                const SizedBox(height: MMSpacing.m),
                Text(l.mapUpdateScope, style: context.mmText.subheadline),
                MMDropdownButton<bool>(
                  child: Text(_onlyNew ? l.mapUpdateScopeNew : l.mapUpdateScopeAll),
                  onSelected: (v) => setState(() => _onlyNew = v),
                  itemBuilder: (_) => [
                    MMDropdownItem(value: true, child: Text(l.mapUpdateScopeNew)),
                    MMDropdownItem(value: false, child: Text(l.mapUpdateScopeAll)),
                  ],
                ),
                const SizedBox(height: MMSpacing.m),
                MMTextField(controller: _instructions, placeholder: l.mapIdeaHint, maxLines: 3, maxLength: 500),
                const SizedBox(height: MMSpacing.m),
                Text(l.mapUpdateProtected(protected), style: context.mmText.footnote),
                if (_needsSetup) const ModelSetupCard(inline: true),
                const SizedBox(height: MMSpacing.m),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: MMButton(
                    label: l.mapUpdatePreview,
                    variant: MMButtonVariant.primary,
                    onPressed: _starting || _documents.isEmpty ? null : _start,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
