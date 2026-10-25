import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../workspace_controller.dart';

/// Map pane: canvas plus floating glass controls (map picker and view
/// switch top-left, node actions top-right, zoom bottom-right). The canvas
/// itself arrives with mm_layout.
class MapPane extends ConsumerWidget {
  const MapPane({super.key, required this.studySetId});

  final String studySetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    final provider = workspaceProvider(studySetId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    void soon() => MMHud.show(context, l.comingSoon);

    return ColoredBox(
      color: state.mapView == MapViewMode.map ? c.canvas : c.windowBackground,
      child: Stack(
        children: [
          Positioned.fill(
            child: MMEmptyState(
              icon: state.mapView == MapViewMode.map ? MMIcons.mindMap : MMIcons.list,
              title: l.mapEmptyTitle,
              message: l.mapEmptyMessage,
            ),
          ),
          Positioned(
            left: 12,
            top: 10,
            child: MMGlass(
              borderRadius: BorderRadius.circular(20),
              padding: const EdgeInsets.fromLTRB(3, 3, 4, 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MMInteractive(
                    onTap: soon,
                    semanticLabel: l.mainMap,
                    builder: (context, s) => Container(
                      height: 34,
                      padding: const EdgeInsets.only(left: 12, right: 10),
                      decoration: BoxDecoration(
                        color: s.hovered ? c.hover : Colors.transparent,
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: Row(
                        children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l.mainMap, style: t.headline),
                              Text(l.newExcerptTarget(state.studySet?.title ?? ''), style: t.footnote),
                            ],
                          ),
                          const SizedBox(width: 10),
                          Icon(MMIcons.popUp, size: 11, color: c.label),
                        ],
                      ),
                    ),
                  ),
                  const MMToolbarDivider(),
                  MMSegmentedControl<MapViewMode>(
                    value: state.mapView,
                    onChanged: controller.setMapView,
                    segments: [
                      MMSegment(value: MapViewMode.map, label: l.mapView),
                      MMSegment(value: MapViewMode.outline, label: l.outlineView),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 12,
            top: 10,
            child: MMToolbarGroup(
              children: [
                MMToolbarButton(icon: MMIcons.addTopic, tooltip: l.addTopic, onPressed: soon),
                MMToolbarButton(icon: MMIcons.addNote, tooltip: l.addNote, onPressed: soon),
                MMToolbarButton(icon: MMIcons.trash, tooltip: l.removeFromMap, onPressed: null),
              ],
            ),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: MMGlass(
              borderRadius: BorderRadius.circular(16),
              padding: const EdgeInsets.all(3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MMIconButton(
                    icon: MMIcons.zoomOut,
                    tooltip: l.zoomOut,
                    size: 26,
                    iconSize: 13,
                    color: c.label,
                    onPressed: soon,
                  ),
                  SizedBox(
                    width: 44,
                    child: Text('100%', textAlign: TextAlign.center, style: t.callout),
                  ),
                  MMIconButton(
                    icon: MMIcons.zoomIn,
                    tooltip: l.zoomIn,
                    size: 26,
                    iconSize: 13,
                    color: c.label,
                    onPressed: soon,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
