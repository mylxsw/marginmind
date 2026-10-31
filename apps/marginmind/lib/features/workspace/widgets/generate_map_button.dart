import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../../map_generation/map_generation_controller.dart';
import '../../map_generation/map_updates.dart';
import '../../map_generation/widgets/update_map_sheet.dart';
import '../../map_generation/widgets/generate_map_sheet.dart';
import '../workspace_controller.dart';

class GenerateMapButton extends ConsumerWidget {
  const GenerateMapButton({super.key, required this.studySetId, this.compact = false});

  final String studySetId;

  /// Icon only, for a narrow header; the label stays in the tooltip.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(workspaceProvider(studySetId));
    final controller = ref.read(workspaceProvider(studySetId).notifier);
    final content = controller.content;
    final map = content.map(workspace.activeMapId);
    if (map == null) return const SizedBox.shrink();

    final preview = ref.watch(mapGenerationControllerProvider(studySetId));
    final l = context.l10n;
    final c = context.mmColors;

    final isGenerating =
        preview != null &&
        (preview.phase == MapGenerationPhase.reading || preview.phase == MapGenerationPhase.streaming);
    final isReviewing = preview != null && !isGenerating;
    final hasGeneration = map.generation != null;

    final String label;
    final Widget? iconWidget;
    final IconData? icon;
    final bool selected;
    final VoidCallback? onPressed;

    if (isGenerating) {
      label = l.mapGenerateRunning;
      iconWidget = SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.research));
      icon = null;
      selected = true;
      onPressed = null;
    } else if (isReviewing) {
      label = l.mapGenerateReviewing;
      iconWidget = null;
      icon = MMIcons.generateMap;
      selected = true;
      onPressed = null;
    } else if (hasGeneration) {
      label = l.mapGenerateUpdate;
      iconWidget = null;
      icon = MMIcons.generateMap;
      selected = false;
      onPressed = () {
        showUpdateMapSheet(context, studySetId, map.id);
      };
    } else {
      label = l.mapGenerate;
      iconWidget = null;
      icon = MMIcons.generateMap;
      selected = false;
      onPressed = () {
        showGenerateMapSheet(context, ref, studySetId, preselectedDocId: workspace.activeDocumentId);
      };
    }

    final hasUpdates = ref.watch(mapHasUpdatesProvider((studySetId, map.id)));

    Widget button = MMToolbarButton(
      key: ValueKey(compact ? 'map-generate-header-button-compact' : 'map-generate-header-button'),
      label: compact ? null : label,
      tooltip: isGenerating || isReviewing ? l.mapGenerateBlocked : label,
      icon: icon,
      iconWidget: iconWidget,
      tint: c.research,
      selected: selected,
      onPressed: onPressed,
    );

    if (hasUpdates && !isGenerating && !isReviewing) {
      button = Stack(
        clipBehavior: Clip.none,
        children: [
          button,
          Positioned(
            top: 3,
            right: 3,
            child: Semantics(
              value: l.mapHasUpdates,
              child: Container(
                width: MMSizes.mapUpdateBadge,
                height: MMSizes.mapUpdateBadge,
                decoration: BoxDecoration(
                  color: c.research,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.windowBackground, width: MMSizes.mapUpdateBadgeRing),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Semantics(
      button: true,
      enabled: !isGenerating && !isReviewing,
      value: hasUpdates ? l.mapHasUpdates : null,
      child: button,
    );
  }
}
