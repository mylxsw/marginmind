import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

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

  String _documentTitle() {
    final workspace = ref.watch(workspaceProvider(widget.studySetId));
    final loaded = ref.watch(workspaceContentProvider(widget.studySetId));
    final content = loaded ?? ref.read(workspaceProvider(widget.studySetId).notifier).content;
    final activeDocId = workspace.activeDocumentId;
    if (activeDocId != null) {
      final doc = content.document(activeDocId);
      if (doc != null) return doc.title;
    }
    final firstDoc = content.documents.firstOrNull;
    return firstDoc?.title ?? '';
  }

  String _documentId() {
    final workspace = ref.watch(workspaceProvider(widget.studySetId));
    final loaded = ref.watch(workspaceContentProvider(widget.studySetId));
    final content = loaded ?? ref.read(workspaceProvider(widget.studySetId).notifier).content;
    return workspace.activeDocumentId ?? content.documents.firstOrNull?.id ?? '';
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
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;

    final isUnconfigured = _needsSetup;

    final docTitle = _documentTitle();
    final scanned = _scanned(listen: true);

    final suggestions = [
      l.mapGenerateSuggestExam,
      l.mapGenerateSuggestExplain,
      l.mapGenerateSuggestQuotes,
      l.mapGenerateSuggestExamples,
    ];

    return CallbackShortcuts(
      bindings: {primaryShortcut(LogicalKeyboardKey.enter): _startGeneration},
      child: ColoredBox(
        color: c.canvas,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: MMSpacing.l, vertical: MMSpacing.xl),
            child: Transform.translate(
              offset: const Offset(0, -MMSizes.ideaBarBottomInset / 2),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: MMSizes.mapEmptyStateWidth),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Icon glyph
                    Container(
                      width: MMSizes.mapEmptyGlyph,
                      height: MMSizes.mapEmptyGlyph,
                      decoration: BoxDecoration(
                        color: c.researchTint,
                        borderRadius: BorderRadius.circular(MMRadii.mapEmptyGlyph),
                      ),
                      alignment: Alignment.center,
                      child: Icon(MMIcons.generateMap, size: 24, color: c.research),
                    ),
                    const SizedBox(height: 14),

                    // Title
                    Semantics(
                      header: true,
                      child: Text(
                        l.mapGenerateFrom(docTitle),
                        style: t.title3.copyWith(color: c.label),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // AI configured vs unconfigured
                    if (isUnconfigured) ...[
                      const SizedBox(width: 360, child: ModelSetupCard(inline: true)),
                    ] else ...[
                      // Input box
                      Container(
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _focused ? c.research : c.separator, width: 1),
                          boxShadow: [if (_focused) BoxShadow(color: c.researchTint, spreadRadius: 3)],
                        ),
                        padding: const EdgeInsets.fromLTRB(10, 10, 8, 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Semantics(
                              label: l.mapIdeaHint,
                              child: TextField(
                                key: const ValueKey('map-empty-state-instructions'),
                                controller: _controller,
                                focusNode: _focusNode,
                                minLines: 2,
                                maxLines: 6,
                                maxLength: 500,
                                buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
                                    null,
                                style: t.body.copyWith(height: 20 / 14),
                                decoration: InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: l.mapIdeaHint,
                                  hintStyle: t.body.copyWith(color: c.secondaryLabel),
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onChanged: (text) {
                                  widget.onInstructionsChanged?.call(text);
                                  setState(() {});
                                },
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Wraps instead of overflowing in a narrow map pane.
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              runSpacing: 6,
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
                                    label: l.mapGenerateStart,
                                    color: c.research,
                                    variant: MMButtonVariant.primary,
                                    onPressed: scanned ? null : _startGeneration,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Suggestion chips
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 6,
                        runSpacing: 6,
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

                    const SizedBox(height: 22),

                    // Blank topic button
                    MMButton(
                      key: const ValueKey('map-empty-state-blank-button'),
                      label: l.mapGenerateBlank,
                      variant: MMButtonVariant.plain,
                      onPressed: () {
                        ref.read(workspaceProvider(widget.studySetId).notifier).addTopic('');
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
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
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
            child: Center(
              widthFactor: 1.0,
              child: Text(text, style: t.callout.copyWith(color: fg, height: 1)),
            ),
          );
        },
      ),
    );
  }
}
