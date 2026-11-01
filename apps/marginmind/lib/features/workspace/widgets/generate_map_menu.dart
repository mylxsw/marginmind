import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../../map_generation/map_generation_controller.dart';
import '../../map_generation/widgets/update_map_sheet.dart';
import '../../map_generation/widgets/generate_map_sheet.dart';
import '../workspace_controller.dart';

MMDropdownItem<VoidCallback> generateMapMenuItem(BuildContext context, WidgetRef ref, String studySetId) {
  final workspace = ref.watch(workspaceProvider(studySetId));
  final content = ref.read(workspaceProvider(studySetId).notifier).content;
  final map = content.map(workspace.activeMapId);
  final preview = ref.watch(mapGenerationControllerProvider(studySetId));
  final l = context.l10n;
  final isGenerating =
      preview != null && (preview.phase == MapGenerationPhase.reading || preview.phase == MapGenerationPhase.streaming);
  final label = isGenerating
      ? l.mapGenerateRunning
      : preview != null
      ? l.mapGenerateReviewing
      : map?.generation != null
      ? l.mapGenerateUpdate
      : l.mapGenerate;

  return MMDropdownItem<VoidCallback>(
    key: const ValueKey('map-generate-menu-item'),
    enabled: map != null && preview == null,
    value: () {
      if (map == null) return;
      if (map.generation != null) {
        showUpdateMapSheet(context, studySetId, map.id);
      } else {
        showGenerateMapSheet(context, ref, studySetId, preselectedDocId: workspace.activeDocumentId);
      }
    },
    child: Row(
      children: [
        const SizedBox.square(
          dimension: MMSizes.dropdownIcon,
          child: Center(child: Icon(MMIcons.generateMap)),
        ),
        const SizedBox(width: MMSpacing.s),
        Expanded(child: Text(label)),
        const SizedBox(width: MMSpacing.xs),
        const MMBetaBadge(),
      ],
    ),
  );
}
