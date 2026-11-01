import '../../assistant/map_task_route.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../app/providers.dart';
import '../../../settings/app_settings.dart';
import '../../../shared/l10n.dart';
import '../../assistant/assistant_controller.dart';
import '../../assistant/expansion_controller.dart';
import '../../workspace/workspace_controller.dart';
import '../document_map_navigation.dart';
import '../map_generation_controller.dart';
import 'generate_map_sheet.dart';

class DocumentMapBanner extends ConsumerWidget {
  const DocumentMapBanner({super.key, required this.studySetId});
  final String studySetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(documentMapNavigationProvider(studySetId));
    final workspace = ref.read(workspaceProvider(studySetId).notifier);
    final content = ref.watch(workspaceContentProvider(studySetId)) ?? workspace.content;
    final navigation = ref.read(documentMapNavigationProvider(studySetId).notifier);
    final l = context.l10n;
    final c = context.mmColors;
    final map = content.map(notice.switchedMapId ?? '');
    if (map != null) {
      return Align(
        alignment: Alignment.topRight,
        child: Container(
          key: const ValueKey('map-follow-notice'),
          height: MMSizes.mapFollowNotice,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.border, width: .5),
            borderRadius: BorderRadius.circular(MMRadii.capsule),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(MMIcons.mindMap, size: 14, color: c.research),
              const SizedBox(width: MMSpacing.s),
              Flexible(
                child: Text(
                  l.mapFollowSwitched(map.title),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.mmText.callout,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (!ref.watch(settingsProvider.select((s) => s.betaFeaturesEnabled))) return const SizedBox.shrink();
    final document = content.document(notice.documentId ?? '');
    if (document == null) return const SizedBox.shrink();
    final activeMapId = ref.watch(workspaceProvider(studySetId).select((s) => s.activeMapId));
    final hasNodes = content.nodes.any((n) => n.mapId == activeMapId);
    final busy =
        ref.watch(mapGenerationControllerProvider(studySetId)) != null ||
        ref.watch(expansionBusyProvider) ||
        ref.watch(assistantControllerProvider.select((s) => s.running)) ||
        ref.watch(assistantBackgroundProvider) != null;
    final generate = MMButton(
      key: const ValueKey('document-map-generate'),
      label: l.mapBannerGenerate,
      variant: MMButtonVariant.primary,
      onPressed: busy
          ? null
          : () async {
              navigation.dismiss();
              final configured = await ref.read(mapTaskReadyProvider((studySetId, TaskType.mapGenerate)).future);
              if (!context.mounted) return;
              if (!configured) {
                await showGenerateMapSheet(
                  context,
                  ref,
                  studySetId,
                  preselectedDocId: document.id,
                  initialNeedsSetup: true,
                );
                return;
              }
              if (ref.read(assistantControllerProvider.notifier).busy) return;
              final prefs = ref.read(sharedPreferencesProvider);
              final key = 'map_gen.$studySetId';
              await ref
                  .read(mapGenerationControllerProvider(studySetId).notifier)
                  .start(
                    MapGenerationRequest(
                      studySetId: studySetId,
                      mapId: 'map-${DateTime.now().microsecondsSinceEpoch}',
                      title: document.title,
                      sources: [MapDocumentSelection(documentId: document.id)],
                      organization:
                          MapOrganization.values
                              .where((o) => o.name == prefs.getString('$key.organization'))
                              .firstOrNull ??
                          MapOrganization.chapter,
                      depth: (prefs.getInt('$key.depth') ?? 3).clamp(2, 4),
                      includeAnnotations: prefs.getBool('$key.includeAnnotations') ?? true,
                    ),
                  );
            },
    );
    final merge = MMButton(
      key: const ValueKey('document-map-merge'),
      label: l.mapBannerMerge,
      icon: MMIcons.mergeIntoMap,
      variant: MMButtonVariant.secondary,
      onPressed: busy
          ? null
          : () {
              navigation.dismiss();
              showGenerateMapSheet(context, ref, studySetId, preselectedDocId: document.id, mergeCurrentMap: true);
            },
    );
    final close = MMIconButton(icon: MMIcons.close, tooltip: l.closePanel, onPressed: navigation.dismiss);
    Widget message() => Expanded(
      child: Text(
        l.mapBannerNoMap(document.title),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.mmText.body,
      ),
    );
    final icon = Icon(MMIcons.generateMap, size: 16, color: c.research);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < MMSizes.mapDocumentBannerCompactWidth;
        final phoneActions = compact && MMInput.of(context).phone && MMSizeClass.of(context) == MMSizeClass.compact;
        final actions = [
          compact ? Flexible(child: generate) : generate,
          if (hasNodes) ...[const SizedBox(width: 10), compact ? Flexible(child: merge) : merge],
        ];
        return Container(
          key: const ValueKey('document-map-banner'),
          height: compact
              ? MMSizes.mapDocumentBanner * 2 + (phoneActions ? MMSizes.hairline * 2 : 0)
              : MMSizes.mapDocumentBanner,
          padding: const EdgeInsets.only(left: 12, right: 6),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.border, width: .5),
            borderRadius: BorderRadius.circular(MMRadii.card),
          ),
          child: compact
              ? Column(
                  children: [
                    Expanded(child: Row(children: [icon, const SizedBox(width: 10), message(), close])),
                    Expanded(
                      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
                    ),
                  ],
                )
              : Row(
                  children: [icon, const SizedBox(width: 10), message(), const SizedBox(width: 10), ...actions, close],
                ),
        );
      },
    );
  }
}
