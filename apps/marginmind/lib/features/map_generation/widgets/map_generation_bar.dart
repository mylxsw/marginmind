import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../../shared/l10n.dart';
import '../../workspace/workspace_controller.dart';
import '../../workspace/reader_ocr.dart';
import '../../workspace/widgets/reader_ocr_controls.dart';
import '../map_generation_controller.dart';

class MapGenerationBar extends ConsumerStatefulWidget {
  const MapGenerationBar({super.key, required this.studySetId, this.onKeep});

  final String studySetId;
  final VoidCallback? onKeep;

  @override
  ConsumerState<MapGenerationBar> createState() => _MapGenerationBarState();
}

class _MapGenerationBarState extends ConsumerState<MapGenerationBar> {
  final _adjustLink = LayerLink();
  final _adjustPortal = OverlayPortalController();

  void _toggleAdjust() {
    _adjustPortal.toggle();
  }

  void _closeAdjust() {
    _adjustPortal.hide();
  }

  @override
  Widget build(BuildContext context) {
    final preview = ref.watch(mapGenerationControllerProvider(widget.studySetId));
    if (preview == null) return const SizedBox.shrink();

    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;
    final controller = ref.read(mapGenerationControllerProvider(widget.studySetId).notifier);

    final needsTextId = preview.needsTextDocumentId;
    final workspace = ref.read(workspaceProvider(widget.studySetId).notifier);
    final needsTextDoc = needsTextId == null ? null : workspace.content.document(needsTextId);
    if (needsTextDoc != null) {
      final source = workspace.filePath(needsTextDoc);
      final ocr = ref.watch(readerOcrProvider(source));
      return Padding(
        padding: const EdgeInsets.all(MMSpacing.s),
        child: Row(
          children: [
            Expanded(child: Text(l.mapGenerateNeedsOcr, style: t.callout)),
            if (ocr.running)
              ReaderOcrProgress(source: source)
            else
              MMButton(
                label: l.ocrRecognize,
                onPressed: ref.read(pdfOcrServiceProvider).supported
                    ? () => showReaderOcrOptions(context, ref, widget.studySetId, documentId: needsTextId)
                    : null,
              ),
            MMButton(label: l.cancel, variant: MMButtonVariant.plain, onPressed: controller.discard),
          ],
        ),
      );
    }
    final phase = preview.phase;
    final isReview = phase == MapGenerationPhase.review || phase == MapGenerationPhase.stopped;
    final isFailed = phase == MapGenerationPhase.failed && preview.lines.isEmpty;
    final isStreaming = phase == MapGenerationPhase.streaming;
    final isReading = phase == MapGenerationPhase.reading;

    Widget titleArea;

    if (isFailed) {
      final isNetwork = preview.failure?.kind == ResearchFailureKind.network;
      final msg = isNetwork ? l.assistantErrorNetwork : (preview.failure?.message ?? l.mapGenerateNothing);
      titleArea = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isNetwork ? MMIcons.offline : MMIcons.warning, size: 14, color: c.critical),
          const SizedBox(width: 8),
          Text(msg, style: t.callout.copyWith(color: c.critical)),
        ],
      );
    } else if (isReading) {
      final docTitle = preview.request.sources.firstOrNull?.documentId != null ? preview.request.title : '';
      final currentSkeleton = preview.skeletons.where((s) => s.isCurrent).firstOrNull;
      final currentTitle = currentSkeleton?.title ?? (preview.skeletons.firstOrNull?.title ?? '');

      titleArea = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.research)),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              l.mapGenerateReading(docTitle),
              style: t.callout.copyWith(color: c.label),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          _ReadingSteps(skeletons: preview.skeletons, progress: preview.chapterProgress),
          if (currentTitle.isNotEmpty) ...[
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                currentTitle,
                style: t.callout.copyWith(color: c.secondaryLabel, fontWeight: FontWeight.w400),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      );
    } else if (isStreaming) {
      final count = preview.topicCount;
      titleArea = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.research)),
          const SizedBox(width: 8),
          Text(l.mapGenerateBuilding, style: t.callout.copyWith(color: c.label)),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Text(l.mapGenerateTopicCount(count), style: t.callout.copyWith(color: c.secondaryLabel)),
          ],
        ],
      );
    } else {
      // Review phase
      final keptCount = preview.selectedCount;
      final totalCount = preview.lines.length;
      final hasChapterFailure = preview.chapterFailures.isNotEmpty;
      final failedChapter = preview.failedChapterTitle;

      titleArea = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasChapterFailure && failedChapter != null) ...[
            Icon(MMIcons.warning, size: 14, color: c.critical),
            const SizedBox(width: 4),
            Text(l.mapGenerateChapterFailed(failedChapter), style: t.callout.copyWith(color: c.critical)),
            const SizedBox(width: 6),
            MMButton(
              key: const ValueKey('map-generation-retry-chapter-button'),
              label: l.assistantRetry,
              variant: MMButtonVariant.plain,
              onPressed: () {
                final failedId = preview.chapterFailures.keys.firstOrNull;
                if (failedId != null) controller.retryChapter(failedId);
              },
            ),
            const SizedBox(width: 8),
            Container(width: 1, height: 14, color: c.separator),
            const SizedBox(width: 8),
          ],
          Icon(MMIcons.generateMap, size: 16, color: c.research),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 90),
            child: Text(
              phase == MapGenerationPhase.stopped ? l.mapIdeaStopped : preview.request.title,
              style: t.callout.copyWith(color: c.label, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Text(l.mapIdeaKeptCount(keptCount, totalCount), style: t.callout.copyWith(color: c.secondaryLabel)),
        ],
      );
    }

    final actions = <Widget>[
      if (isFailed) ...[
        MMButton(
          key: const ValueKey('map-generation-failed-retry-button'),
          label: l.assistantRetry,
          icon: MMIcons.history,
          variant: MMButtonVariant.secondary,
          onPressed: controller.retry,
        ),
        const SizedBox(width: 8),
        MMButton(
          key: const ValueKey('map-generation-failed-close-button'),
          label: l.closePanel,
          variant: MMButtonVariant.plain,
          onPressed: controller.discard,
        ),
      ] else if (isReading || isStreaming) ...[
        MMButton(
          key: const ValueKey('map-generation-stop-button'),
          label: l.assistantStop,
          icon: MMIcons.stop,
          variant: MMButtonVariant.secondary,
          onPressed: controller.stop,
        ),
      ] else ...[
        // Review buttons
        MMButton(
          key: const ValueKey('map-generation-regenerate-button'),
          label: l.mapIdeaRegenerate,
          icon: MMIcons.history,
          variant: MMButtonVariant.plain,
          onPressed: () => controller.regenerate(),
        ),
        const SizedBox(width: 4),
        CompositedTransformTarget(
          link: _adjustLink,
          child: OverlayPortal(
            controller: _adjustPortal,
            overlayChildBuilder: (context) => CompositedTransformFollower(
              link: _adjustLink,
              targetAnchor: Alignment.topCenter,
              followerAnchor: Alignment.bottomCenter,
              offset: const Offset(0, -8),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: TapRegion(
                  onTapOutside: (_) => _closeAdjust(),
                  child: MapAdjustMenu(
                    request: preview.request,
                    onRegenerate: (updated) {
                      _closeAdjust();
                      controller.regenerate(updated);
                    },
                  ),
                ),
              ),
            ),
            child: MMButton(
              key: const ValueKey('map-generation-adjust-button'),
              label: l.mapIdeaAdjust,
              icon: MMIcons.adjust,
              variant: MMButtonVariant.plain,
              onPressed: _toggleAdjust,
            ),
          ),
        ),
        const SizedBox(width: 4),
        MMButton(
          key: const ValueKey('map-generation-discard-button'),
          label: l.mapIdeaDiscard,
          variant: MMButtonVariant.plain,
          onPressed: controller.discard,
        ),
        const SizedBox(width: 8),
        MMButton(
          key: const ValueKey('map-generation-keep-button'),
          label: l.mapIdeaDraftKeep,
          icon: MMIcons.check,
          color: c.research,
          variant: MMButtonVariant.primary,
          onPressed: (preview.selectedCount == 0 || preview.isApplying)
              ? null
              : () async {
                  final count = await controller.keep();
                  if (count > 0 && context.mounted) {
                    MMHud.show(
                      context,
                      l.mapGenerateCreated(preview.request.title, count),
                      action: (
                        l.undo,
                        () {
                          ref.read(workspaceProvider(widget.studySetId).notifier).undo();
                        },
                      ),
                    );
                    widget.onKeep?.call();
                  }
                },
        ),
      ],
    ];

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_adjustPortal.isShowing) {
            _closeAdjust();
          } else if (isReading || isStreaming) {
            controller.stop();
          } else if (isReview) {
            controller.discard();
          }
        },
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (isReview && preview.selectedCount > 0 && !preview.isApplying) {
            controller.keep().then((count) {
              if (count > 0 && context.mounted) {
                MMHud.show(
                  context,
                  l.mapGenerateCreated(preview.request.title, count),
                  action: (
                    l.undo,
                    () {
                      ref.read(workspaceProvider(widget.studySetId).notifier).undo();
                    },
                  ),
                );
                widget.onKeep?.call();
              }
            });
          }
        },
        primaryShortcut(LogicalKeyboardKey.enter): () {
          if (isReview && preview.selectedCount > 0 && !preview.isApplying) {
            controller.keep().then((count) {
              if (count > 0 && context.mounted) {
                MMHud.show(
                  context,
                  l.mapGenerateCreated(preview.request.title, count),
                  action: (
                    l.undo,
                    () {
                      ref.read(workspaceProvider(widget.studySetId).notifier).undo();
                    },
                  ),
                );
                widget.onKeep?.call();
              }
            });
          }
        },
      },
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.border, width: 0.5),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              titleArea,
              if (isReview && preview.request.sources.length > 1) ...[
                const SizedBox(width: 10),
                Container(width: .5, height: 16, color: c.border),
                const SizedBox(width: 10),
                MapDocumentLegend(
                  studySetId: widget.studySetId,
                  documentIds: preview.request.sources.map((s) => s.documentId).toList(),
                ),
              ],
              const SizedBox(width: 12),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadingSteps extends StatelessWidget {
  const _ReadingSteps({required this.skeletons, required this.progress});

  final List<MapSkeletonItem> skeletons;
  final Map<String, MapChapterStatus> progress;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;

    if (skeletons.length > 12) {
      final doneCount = progress.values.where((s) => s == MapChapterStatus.done).length;
      final val = skeletons.isEmpty ? 0.0 : doneCount / skeletons.length;
      return SizedBox(
        width: 120,
        height: 4,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: val,
            backgroundColor: c.fill,
            valueColor: AlwaysStoppedAnimation<Color>(c.research),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < skeletons.length; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          _StepBox(status: progress[skeletons[i].id] ?? MapChapterStatus.pending),
        ],
      ],
    );
  }
}

class _StepBox extends StatelessWidget {
  const _StepBox({required this.status});
  final MapChapterStatus status;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;

    final color = switch (status) {
      MapChapterStatus.done => c.research,
      MapChapterStatus.reading => c.research.withValues(alpha: 0.45),
      MapChapterStatus.failed => c.critical,
      MapChapterStatus.pending => c.fill,
    };

    return Container(
      width: MMSizes.mapReadingStep.width,
      height: MMSizes.mapReadingStep.height,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
    );
  }
}

class MapAdjustMenu extends StatefulWidget {
  const MapAdjustMenu({super.key, required this.request, required this.onRegenerate});

  final MapGenerationRequest request;
  final ValueChanged<MapGenerationRequest> onRegenerate;

  @override
  State<MapAdjustMenu> createState() => _MapAdjustMenuState();
}

class _MapAdjustMenuState extends State<MapAdjustMenu> {
  late MapOrganization _organization;
  late int _depth;
  late final TextEditingController _instructionsController;

  @override
  void initState() {
    super.initState();
    _organization = widget.request.organization;
    _depth = widget.request.depth;
    _instructionsController = TextEditingController(text: widget.request.instructions ?? '');
  }

  @override
  void dispose() {
    _instructionsController.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _instructionsController.text.trim();
    widget.onRegenerate(
      widget.request.copyWith(organization: _organization, depth: _depth, instructions: text.isEmpty ? null : text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final l = context.l10n;

    return Container(
      width: MMSizes.ideaAdjustWidth,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(MMRadii.dropdown),
        border: Border.all(color: c.border, width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Organization
          MMSegmentedControl<MapOrganization>(
            key: const ValueKey('map-adjust-organization'),
            value: _organization,
            expand: true,
            onChanged: (org) => setState(() => _organization = org),
            segments: [
              MMSegment(value: MapOrganization.chapter, label: l.mapGenerateByChapter),
              MMSegment(value: MapOrganization.topic, label: l.mapGenerateByTopic),
              MMSegment(value: MapOrganization.question, label: l.mapGenerateByQuestion),
            ],
          ),
          const SizedBox(height: 10),

          // Detail
          MMSegmentedControl<int>(
            key: const ValueKey('map-adjust-detail'),
            value: _depth,
            expand: true,
            onChanged: (d) => setState(() => _depth = d),
            segments: [
              MMSegment(value: 2, label: l.mapGenerateDetailBrief),
              MMSegment(value: 3, label: l.mapGenerateDetailMedium),
              MMSegment(value: 4, label: l.mapGenerateDetailFull),
            ],
          ),
          const SizedBox(height: 10),

          // Instructions textfield
          TextField(
            key: const ValueKey('map-adjust-instructions'),
            controller: _instructionsController,
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
            style: t.body,
            decoration: InputDecoration(
              isDense: true,
              hintText: l.mapIdeaHint,
              hintStyle: t.body.copyWith(color: c.secondaryLabel),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: c.separator),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: c.separator),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: c.research),
              ),
              contentPadding: const EdgeInsets.all(8),
            ),
          ),
          const SizedBox(height: 12),

          // Bottom submit button
          Align(
            alignment: Alignment.centerRight,
            child: MMButton(
              key: const ValueKey('map-adjust-regenerate-button'),
              label: l.mapIdeaRegenerateAdjusted,
              icon: MMIcons.history,
              color: c.research,
              variant: MMButtonVariant.primary,
              onPressed: _submit,
            ),
          ),
        ],
      ),
    );
  }
}

class MapDocumentLegend extends ConsumerWidget {
  const MapDocumentLegend({super.key, required this.studySetId, required this.documentIds});
  final String studySetId;
  final List<String> documentIds;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = ref.read(workspaceProvider(studySetId).notifier).content;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, id) in documentIds.take(3).indexed) ...[
          if (index > 0) const SizedBox(width: 10),
          Container(
            width: MMSizes.mapSourceDot,
            height: MMSizes.mapSourceDot,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: MMSourceColors.of(Theme.of(context).brightness, index),
            ),
          ),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: MMSizes.mapDocumentLegendLabelWidth),
            child: Text(
              content.document(id)?.title ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.mmText.callout.copyWith(color: context.mmColors.secondaryLabel),
            ),
          ),
        ],
        if (documentIds.length > 3) ...[
          const SizedBox(width: 10),
          Text('+${documentIds.length - 3}', style: context.mmText.callout),
        ],
      ],
    );
  }
}
