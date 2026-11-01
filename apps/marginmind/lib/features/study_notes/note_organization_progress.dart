import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../shared/l10n.dart';
import '../assistant/settings/ai_task_status.dart';

enum NoteOrganizationPhase { outline, write, verify }

/// Reports completed sections, rather than estimating model or total run time.
class NoteOrganizationProgress extends StatefulWidget {
  const NoteOrganizationProgress({
    super.key,
    required this.phase,
    required this.materials,
    required this.sections,
    required this.draft,
    required this.local,
    required this.busy,
    this.error,
    this.status,
    this.sources = const {},
    this.quoteColors = const {},
  });

  final NoteOrganizationPhase phase;
  final NoteMaterials materials;
  final List<NoteOutlineSection> sections;
  final List<NoteDraftSection> draft;
  final bool local, busy;
  final String? error;
  final RunStatus? status;
  final Map<String, String> sources;
  final Map<String, Color> quoteColors;

  @override
  State<NoteOrganizationProgress> createState() => _NoteOrganizationProgressState();
}

class _NoteOrganizationProgressState extends State<NoteOrganizationProgress> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(NoteOrganizationProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follow new sections only while the reader is already at the bottom.
    if (oldWidget.draft.length != widget.draft.length && (!_scroll.hasClients || _scroll.position.extentAfter < 72)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  int get _active => widget.local ? 2 : widget.phase.index + 2;
  double? get _fraction => widget.sections.isEmpty ? null : widget.draft.length / widget.sections.length;

  String _activity(BuildContext context) {
    final l = context.l10n;
    if (widget.phase == NoteOrganizationPhase.outline) return widget.local ? l.noteStepLayout : l.noteStepOutline;
    if (widget.phase == NoteOrganizationPhase.verify) return l.noteStepVerify;
    if (widget.error != null) return widget.local ? l.noteStepLayout : l.noteStepCompose;
    final index = (widget.draft.length + 1).clamp(1, widget.sections.length.clamp(1, 100000));
    return widget.local ? l.noteProgressLayoutSection(index) : l.noteProgressWriting(index);
  }

  Widget _bar(BuildContext context) => LinearProgressIndicator(
    key: const ValueKey('note-section-progress'),
    value: _fraction,
    minHeight: 4,
    borderRadius: BorderRadius.circular(2),
    color: context.mmColors.research,
    backgroundColor: context.mmColors.fill,
    semanticsLabel: context.l10n.noteProgressCompleted(widget.draft.length, widget.sections.length),
  );

  Widget _indicator(BuildContext context, int index) {
    final c = context.mmColors;
    if (index == _active && widget.error != null) return Icon(MMIcons.warning, color: c.caution, size: 23);
    if (index < _active) return Icon(CupertinoIcons.checkmark_circle_fill, color: c.accent, size: 24);
    if (index == _active && widget.busy && !MMAppearance.reduceMotionOf(context)) {
      return SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2, color: c.research, backgroundColor: c.researchTint),
      );
    }
    return Icon(CupertinoIcons.circle, color: index == _active ? c.research : c.secondaryLabel, size: 24);
  }

  Widget _steps(BuildContext context) {
    final l = context.l10n;
    final labels = [
      l.noteStepCollect,
      l.noteStepContext,
      if (!widget.local) l.noteStepOutline,
      widget.local ? l.noteStepLayout : l.noteStepCompose,
      if (!widget.local) l.noteStepVerify,
    ];
    return SingleChildScrollView(
      key: const ValueKey('note-progress-steps'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 22, 24, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, label) in labels.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 42),
                child: Semantics(
                  selected: index == _active,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 28, height: 24, child: Center(child: _indicator(context, index))),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                label,
                                style: context.mmText.body.copyWith(
                                  fontWeight: index == _active ? FontWeight.w600 : FontWeight.w500,
                                  color: index > _active ? context.mmColors.secondaryLabel : context.mmColors.label,
                                ),
                              ),
                            ),
                            if (index == (widget.local ? 2 : 3) && widget.sections.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                l.noteProgressCompleted(widget.draft.length, widget.sections.length),
                                style: context.mmText.footnote.copyWith(color: context.mmColors.secondaryLabel),
                              ),
                              const SizedBox(height: 12),
                              _bar(context),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _block(BuildContext context, NoteDraftBlock block) {
    final c = context.mmColors;
    final material = block.ref == null ? null : widget.materials[block.ref!];
    final text = switch (block.type) {
      'quote' || 'own' => material?.text ?? '',
      'points' => block.items.join('\n'),
      _ => block.text ?? '',
    };
    if (text.isEmpty) return const SizedBox.shrink();
    final quote = block.type == 'quote';
    final own = block.type == 'own';
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Container(
        padding: quote || own ? const EdgeInsets.only(left: 16) : null,
        decoration: quote || own
            ? BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: quote ? widget.quoteColors[block.ref] ?? c.research : c.separator,
                    width: quote ? 3 : 2,
                  ),
                ),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!quote && !own && !widget.local) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(color: c.research, borderRadius: BorderRadius.circular(4)),
                child: Text(
                  'AI',
                  style: context.mmText.footnote.copyWith(color: c.onResearch, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              text,
              style: (quote ? MMNoteTypography.quote : MMNoteTypography.body).copyWith(
                color: c.label,
                fontSize: 16,
                height: 1.7,
              ),
            ),
            if (material != null) ...[
              const SizedBox(height: 8),
              Text(
                widget.sources[material.ref] ?? material.groupTitle,
                style: context.mmText.footnote.copyWith(color: c.secondaryLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _preview(BuildContext context, {bool showActivity = true}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.status case final status?)
        Align(
          alignment: Alignment.centerLeft,
          child: RunStatusCapsule(status: status, unfinished: widget.sections.length - widget.draft.length),
        ),
      if (showActivity)
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
          child: Semantics(
            liveRegion: true,
            child: Text(
              _activity(context),
              style: context.mmText.callout.copyWith(color: context.mmColors.secondaryLabel),
            ),
          ),
        ),
      if (widget.error != null)
        Flexible(
          child: SingleChildScrollView(
            key: const ValueKey('note-progress-error'),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Semantics(
              liveRegion: true,
              child: Text(
                widget.error!,
                style: context.mmText.body.copyWith(color: context.mmColors.critical, height: 1.5),
              ),
            ),
          ),
        ),
      Expanded(
        child: Scrollbar(
          controller: _scroll,
          child: SingleChildScrollView(
            key: const ValueKey('note-progress-preview'),
            controller: _scroll,
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.draft.isEmpty) ...[
                  if (widget.sections.isNotEmpty) Text(widget.sections.first.title, style: context.mmText.title2),
                  const SizedBox(height: 18),
                  Text(
                    context.l10n.noteProgressPreviewEmpty,
                    style: context.mmText.body.copyWith(color: context.mmColors.secondaryLabel, height: 1.5),
                  ),
                ],
                for (final (index, section) in widget.draft.indexed) ...[
                  Padding(
                    padding: EdgeInsets.only(top: index == 0 ? 0 : 24, bottom: 20),
                    child: Text(section.title, style: context.mmText.title2),
                  ),
                  for (final block in section.blocks) _block(context, block),
                ],
              ],
            ),
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 620 || MediaQuery.textScalerOf(context).scale(13) > 20;
      final height = (MediaQuery.sizeOf(context).height * .55).clamp(120.0, 440.0);
      return Container(
        height: height,
        decoration: BoxDecoration(
          border: Border.symmetric(horizontal: BorderSide(color: context.mmColors.separator, width: .5)),
        ),
        child: narrow
            ? Column(
                key: const ValueKey('note-progress-compact'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            SizedBox(width: 24, height: 24, child: _indicator(context, _active)),
                            const SizedBox(width: 10),
                            Expanded(child: Text(_activity(context), style: context.mmText.headline)),
                          ],
                        ),
                        if (widget.sections.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            context.l10n.noteProgressCompleted(widget.draft.length, widget.sections.length),
                            style: context.mmText.footnote,
                          ),
                          const SizedBox(height: 10),
                          _bar(context),
                        ],
                      ],
                    ),
                  ),
                  Expanded(child: _preview(context, showActivity: false)),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 200, child: _steps(context)),
                  VerticalDivider(width: 1, thickness: .5, color: context.mmColors.separator),
                  Expanded(child: _preview(context)),
                ],
              ),
      );
    },
  );
}
