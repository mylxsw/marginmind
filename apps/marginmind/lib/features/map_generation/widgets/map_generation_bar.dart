import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../../shared/l10n.dart';
import '../../workspace/workspace_controller.dart';
import '../map_generation_controller.dart';
import '../../assistant/settings/ai_task_status.dart';
import 'map_generation_failure.dart';

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

    if (preview.needsTextDocumentId != null) return const SizedBox.shrink();
    final phase = preview.phase;
    final isReview = phase == MapGenerationPhase.review || phase == MapGenerationPhase.stopped;
    final isFailed = phase == MapGenerationPhase.failed && preview.lines.isEmpty;
    final isStreaming = phase == MapGenerationPhase.streaming;
    final isReading = phase == MapGenerationPhase.reading;

    Widget? titleArea;

    if (isFailed) {
      final isNetwork = preview.failure?.kind == ResearchFailureKind.network;
      final msg = mapGenerationFailureSummary(l, preview.failure);
      titleArea = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isNetwork ? MMIcons.offline : MMIcons.warning, size: 14, color: c.critical),
          const SizedBox(width: 8),
          Flexible(
            child: Tooltip(
              message: msg,
              child: Text(
                msg,
                style: t.callout.copyWith(color: c.critical),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      );
    } else if (isReading) {
      final docTitle = preview.request.sources.firstOrNull?.documentId != null ? preview.request.title : '';
      final currentSkeleton = preview.skeletons.where((s) => s.isCurrent).firstOrNull;
      final currentTitle = currentSkeleton?.title ?? (preview.skeletons.firstOrNull?.title ?? '');

      titleArea = Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.research)),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              l.mapGenerateReading(docTitle),
              style: t.callout.copyWith(color: c.label),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _ReadingSteps(skeletons: preview.skeletons, progress: preview.chapterProgress),
          if (currentTitle.isNotEmpty) ...[
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
      titleArea = Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.research)),
          Text(l.mapGenerateBuilding, style: t.callout.copyWith(color: c.label)),
          if (count > 0) Text(l.mapGenerateTopicCount(count), style: t.callout.copyWith(color: c.secondaryLabel)),
        ],
      );
    } else {
      final hasChapterFailure = preview.chapterFailures.isNotEmpty;
      final failedChapter = preview.failedChapterTitle;

      if (hasChapterFailure && failedChapter != null) {
        titleArea = Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(MMIcons.warning, size: 14, color: c.critical),
            Text(l.mapGenerateChapterFailed(failedChapter), style: t.callout.copyWith(color: c.critical)),
            MMButton(
              key: const ValueKey('map-generation-retry-chapter-button'),
              label: l.assistantRetry,
              variant: MMButtonVariant.plain,
              onPressed: () {
                final failedId = preview.chapterFailures.keys.firstOrNull;
                if (failedId != null) controller.retryChapter(failedId);
              },
            ),
          ],
        );
      }
    }

    final actions = <Widget>[
      if (preview.failure != null || preview.chapterFailures.isNotEmpty) ...[
        MMButton(
          key: const ValueKey('map-generation-error-details-button'),
          label: l.mapFailureDetails,
          variant: MMButtonVariant.plain,
          onPressed: () => showMapGenerationFailure(context, preview),
        ),
      ],
      if (isFailed) ...[
        MMButton(
          key: const ValueKey('map-generation-failed-retry-button'),
          label: l.assistantRetry,
          icon: MMIcons.history,
          variant: MMButtonVariant.secondary,
          onPressed: controller.retry,
        ),
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
        MMButton(
          key: const ValueKey('map-generation-discard-button'),
          label: l.mapIdeaDiscard,
          variant: MMButtonVariant.plain,
          onPressed: controller.discard,
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.border, width: 0.5),
        ),
        child: Wrap(
          spacing: 4,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TickerMode(
              enabled: !MMAppearance.reduceMotionOf(context),
              child: RunStatusCapsule(
                status: isReading || isStreaming
                    ? RunStatus.running
                    : isFailed
                    ? RunStatus.failed
                    : preview.failure != null || preview.chapterFailures.isNotEmpty
                    ? RunStatus.partial
                    : phase == MapGenerationPhase.stopped
                    ? RunStatus.cancelled
                    : RunStatus.awaitingUser,
                unfinished: preview.chapterFailures.isNotEmpty
                    ? preview.chapterFailures.length
                    : preview.failure is MapGenerationFailure
                    ? (preview.failure as MapGenerationFailure).rejections.values.fold<int>(0, (sum, n) => sum + n)
                    : 1,
              ),
            ),
            ?titleArea,
            if (isReview && preview.request.sources.length > 1)
              MapDocumentLegend(
                studySetId: widget.studySetId,
                documentIds: preview.request.sources.map((s) => s.documentId).toList(),
              ),
            ...actions,
          ],
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
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (index, id) in documentIds.take(3).indexed)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: MMSizes.mapSourceDot,
                height: MMSizes.mapSourceDot,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: MMSourceColors.of(Theme.of(context).brightness, index),
                ),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: MMSizes.mapDocumentLegendLabelWidth),
                  child: Text(
                    content.document(id)?.title ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.mmText.callout.copyWith(color: context.mmColors.secondaryLabel),
                  ),
                ),
              ),
            ],
          ),
        if (documentIds.length > 3) Text('+${documentIds.length - 3}', style: context.mmText.callout),
      ],
    );
  }
}
