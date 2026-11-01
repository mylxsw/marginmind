import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../../shared/document_icon.dart';
import '../../../shared/l10n.dart';
import '../../assistant/assistant_settings.dart';
import '../../assistant/widgets/assistant_panel.dart' show ModelSetupCard;
import '../../workspace/workspace_controller.dart';
import '../../workspace/reader_ocr.dart';
import '../map_generation_controller.dart';
import 'generate_map_sheet.dart';

class MapEmptyState extends ConsumerStatefulWidget {
  const MapEmptyState({
    super.key,
    required this.studySetId,
    required this.mapId,
    this.initialInstructions = '',
    this.onInstructionsChanged,
  });

  final String studySetId;
  final String mapId;
  final String initialInstructions;
  final ValueChanged<String>? onInstructionsChanged;

  @override
  ConsumerState<MapEmptyState> createState() => _MapEmptyStateState();
}

class _MapEmptyStateState extends ConsumerState<MapEmptyState> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialInstructions);
    _focusNode.addListener(() {
      if (mounted && _focused != _focusNode.hasFocus) {
        setState(() => _focused = _focusNode.hasFocus);
      }
    });
  }

  @override
  void didUpdateWidget(MapEmptyState old) {
    super.didUpdateWidget(old);
    if (widget.initialInstructions != old.initialInstructions && widget.initialInstructions != _controller.text) {
      _controller.text = widget.initialInstructions;
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  Document? _document() {
    final workspace = ref.watch(workspaceProvider(widget.studySetId));
    final loaded = ref.watch(workspaceContentProvider(widget.studySetId));
    final content = loaded ?? ref.read(workspaceProvider(widget.studySetId).notifier).content;
    return content.document(workspace.activeDocumentId ?? '') ?? content.documents.firstOrNull;
  }

  String _documentTitle() => _document()?.title ?? '';
  String _documentId() => _document()?.id ?? '';

  void _createBlankTopic() {
    ref.read(workspaceProvider(widget.studySetId).notifier).addTopic('');
  }

  void _toggleSuggestion(String text) {
    final sep = Localizations.localeOf(context).languageCode == 'zh' ? '；' : '; ';
    final current = _controller.text.trim();
    final parts = current.isEmpty
        ? <String>[]
        : current.split(RegExp(r'[；;]\s*')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    if (parts.contains(text)) {
      parts.remove(text);
    } else {
      parts.add(text);
    }

    final next = parts.join(sep);
    _controller.text = next;
    widget.onInstructionsChanged?.call(next);
    setState(() {});
  }

  bool _isSuggestionSelected(String text) {
    final current = _controller.text.trim();
    if (current.isEmpty) return false;
    final parts = current.split(RegExp(r'[；;]\s*')).map((s) => s.trim()).toSet();
    return parts.contains(text);
  }

  /// Set once a start finds no usable model. Credentials are only read when
  /// the user asks for a map, never just because the empty map is shown.
  bool _needsSetup = false;

  bool _scanned({bool listen = false}) {
    final workspace = ref.read(workspaceProvider(widget.studySetId).notifier);
    final document = workspace.content.document(_documentId());
    if (document == null || document.format != DocumentFormat.pdf) return false;
    final source = workspace.filePath(document);
    if (listen) ref.watch(readerOcrInspectionProvider(source));
    final ocr = listen ? ref.watch(readerOcrProvider(source)) : ref.read(readerOcrProvider(source));
    return ocr.document?.textPages.isEmpty == true;
  }

  Future<void> _startGeneration() async {
    if (_scanned()) return;
    final docId = _documentId();
    if (docId.isEmpty) return;
    final configured = await ref.read(assistantConfiguredProvider.future);
    if (!mounted) return;
    if (!configured) {
      setState(() => _needsSetup = true);
      return;
    }
    final docTitle = _documentTitle();
    final text = _controller.text.trim();

    ref
        .read(mapGenerationControllerProvider(widget.studySetId).notifier)
        .start(
          MapGenerationRequest(
            studySetId: widget.studySetId,
            mapId: widget.mapId,
            title: docTitle,
            sources: [MapDocumentSelection(documentId: docId)],
            instructions: text.isEmpty ? null : text,
            destination: MapGenerationDestination.branch,
            parentId: widget.mapId,
          ),
        );
  }

  void _openSettings() {
    showGenerateMapSheet(
      context,
      ref,
      widget.studySetId,
      preselectedDocId: _documentId(),
      initialInstructions: _controller.text,
      onInstructionsChanged: (val) {
        _controller.text = val;
        widget.onInstructionsChanged?.call(val);
        if (mounted) setState(() {});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;
    final document = _document();
    final scanned = _scanned(listen: true);
    final suggestions = [l.mapGenerateSuggestQuotes, l.mapGenerateSuggestExplain, l.mapGenerateSuggestExamples];

    return CallbackShortcuts(
      bindings: {primaryShortcut(LogicalKeyboardKey.enter): _startGeneration},
      child: ColoredBox(
        color: c.canvas,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Center within the scrollable extent; short windows must not clip
            // the first controls above the viewport.
            final compact = constraints.maxWidth < 420 || constraints.maxHeight < 600;
            final gap = compact ? MMSpacing.xl : MMSpacing.xxxl;
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: MMSpacing.xl, vertical: MMSpacing.xxxl),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: (constraints.maxHeight - 64).clamp(0, double.infinity)),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: MMSizes.mapEmptyStateWidth),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            l.mapEmptyGenerateTitle,
                            style: t.largeTitle.copyWith(
                              fontSize: compact ? 26 : 32,
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: MMSpacing.s),
                        Text(
                          l.mapEmptyGenerateSubtitle,
                          style: t.body.copyWith(fontSize: 16, color: c.secondaryLabel, height: 1.5),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: compact ? gap : 48),
                        if (document != null) ...[
                          _SourceTopic(document: document, onAdd: _createBlankTopic),
                          SizedBox(height: gap),
                        ],
                        if (_needsSetup)
                          const SizedBox(width: 360, child: ModelSetupCard(inline: true))
                        else ...[
                          Container(
                            key: const ValueKey('map-empty-state-composer'),
                            decoration: BoxDecoration(
                              color: c.surface,
                              borderRadius: BorderRadius.circular(MMRadii.cover),
                              border: Border.all(color: _focused ? c.research : c.separator),
                              boxShadow: [if (_focused) BoxShadow(color: c.researchTint, spreadRadius: 3)],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(MMSpacing.l),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        l.mapGenerateInstructionsHint,
                                        style: t.body.copyWith(fontSize: 14, color: c.secondaryLabel),
                                      ),
                                      const SizedBox(height: MMSpacing.s),
                                      TextField(
                                        key: const ValueKey('map-empty-state-instructions'),
                                        controller: _controller,
                                        focusNode: _focusNode,
                                        minLines: compact ? 2 : 3,
                                        maxLines: 6,
                                        style: t.body.copyWith(fontSize: 14, height: 1.6),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          border: InputBorder.none,
                                          hintText: l.mapEmptyInstructionsPlaceholder,
                                          hintStyle: t.body.copyWith(
                                            fontSize: 14,
                                            color: c.secondaryLabel,
                                            height: 1.6,
                                          ),
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                        onChanged: (text) {
                                          widget.onInstructionsChanged?.call(text);
                                          setState(() {});
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                Divider(height: 1, thickness: MMSizes.hairline, color: c.separator),
                                Padding(
                                  padding: const EdgeInsets.all(MMSpacing.s),
                                  child: Wrap(
                                    alignment: WrapAlignment.spaceBetween,
                                    runSpacing: MMSpacing.s,
                                    children: [
                                      MMButton(
                                        key: const ValueKey('map-empty-state-settings-button'),
                                        label: l.mapGenerateSettings,
                                        icon: MMIcons.adjust,
                                        variant: MMButtonVariant.plain,
                                        onPressed: _openSettings,
                                      ),
                                      Tooltip(
                                        message: scanned ? l.mapBannerNeedsOcr : '',
                                        child: MMButton(
                                          key: const ValueKey('map-empty-state-start-button'),
                                          label: l.mapGenerate,
                                          color: c.research,
                                          foregroundColor: c.onResearch,
                                          variant: MMButtonVariant.primary,
                                          onPressed: scanned || document == null ? null : _startGeneration,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: MMSpacing.l),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: MMSpacing.s,
                            runSpacing: MMSpacing.s,
                            children: [
                              for (final suggestion in suggestions)
                                _SuggestionChip(
                                  text: suggestion,
                                  selected: _isSuggestionSelected(suggestion),
                                  onTap: () => _toggleSuggestion(suggestion),
                                ),
                            ],
                          ),
                        ],
                        SizedBox(height: gap),
                        MMButton(
                          key: const ValueKey('map-empty-state-blank-button'),
                          label: l.mapGenerateBlank,
                          icon: MMIcons.chevronRight,
                          variant: MMButtonVariant.plain,
                          onPressed: _createBlankTopic,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A prospective root topic, grounded in the real source, not an AI summary.
class _SourceTopic extends StatelessWidget {
  const _SourceTopic({required this.document, required this.onAdd});
  final Document document;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;
    final origin = document.origin;
    final source = origin == null ? document.format.name.toUpperCase() : Uri.parse(origin.url).host;
    final icon = documentIcon(document);
    return Column(
      children: [
        Text(l.mapEmptySourceStart, style: t.callout.copyWith(fontSize: 14, color: c.secondaryLabel)),
        const SizedBox(height: MMSpacing.m),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 480;
            final connector = wide ? 76.0 : 24.0;
            final control = context.mmTouchPlatform ? MMSizes.tabletControlVisual : 32.0;
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(width: connector + control),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: MMSizes.mapEmptySourceWidth),
                    child: Tooltip(
                      message: document.title,
                      child: Container(
                        key: const ValueKey('map-empty-state-source'),
                        constraints: const BoxConstraints(
                          minWidth: MMSizes.mapEmptySourceMinWidth,
                          minHeight: MMSizes.mapEmptySourceHeight,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: MMSpacing.xl, vertical: MMSpacing.l),
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(MMRadii.mapEmptyGlyph),
                          border: Border.all(color: c.research, width: 1.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 26, color: c.research),
                            const SizedBox(width: MMSpacing.m),
                            Flexible(
                              child: Text(
                                document.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: t.headline.copyWith(fontSize: 16, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: connector,
                  child: Divider(height: 1, color: c.research, thickness: 1),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(color: c.fill, shape: BoxShape.circle),
                  child: MMIconButton(
                    key: const ValueKey('map-empty-state-source-add'),
                    icon: MMIcons.add,
                    size: 32,
                    tooltip: l.mapGenerateBlank,
                    onPressed: onAdd,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: MMSpacing.s),
        Text('${l.mapGenerateSource}：$source', style: t.footnote.copyWith(fontSize: 13, color: c.secondaryLabel)),
      ],
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.text, required this.selected, required this.onTap});

  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;

    return Semantics(
      button: true,
      toggled: selected,
      child: MMInteractive(
        onTap: onTap,
        builder: (context, state) {
          final hovered = state.hovered || state.pressed;
          final bg = selected ? c.research : (hovered ? c.fill : c.quaternaryFill);
          final fg = selected ? c.onResearch : (hovered ? c.label : c.secondaryLabel);

          return Container(
            constraints: BoxConstraints(minHeight: context.mmTouchPlatform ? MMSizes.touchTarget : 32),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
            child: Center(
              widthFactor: 1.0,
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: t.callout.copyWith(fontSize: 14, color: fg),
              ),
            ),
          );
        },
      ),
    );
  }
}
