import 'package:flutter/material.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_layout/mm_layout.dart';

import '../../../shared/l10n.dart';
import '../../workspace/widgets/mind_map_style.dart';

/// Illustrates organization, using the actual map layout and connector geometry.
/// Generic labels never imply that document content has already been generated.
class MapGenerationStructurePreview extends StatelessWidget {
  const MapGenerationStructurePreview({super.key, required this.organization, required this.depth});
  final MapOrganization organization;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n, c = context.mmColors, t = context.mmText;
    final labels = switch (organization) {
      MapOrganization.chapter => [for (var i = 1; i <= 3; i++) l.mapGeneratePreviewChapter(i)],
      MapOrganization.topic => [l.mapGeneratePreviewConcepts, l.mapGeneratePreviewLinks, l.mapGeneratePreviewMethods],
      MapOrganization.question => [l.mapGeneratePreviewWhat, l.mapGeneratePreviewWhy, l.mapGeneratePreviewHow],
    };
    final text = <String, String>{
      'root': l.mapGeneratePreviewRoot,
      for (var i = 0; i < labels.length; i++) 'branch-$i': labels[i],
      if (depth > 2) ...{'point-1': l.mapGeneratePreviewPoint(1), 'point-2': l.mapGeneratePreviewPoint(2)},
      if (depth > 3) 'point-3': l.mapGeneratePreviewPoint(3),
    };
    TextStyle style(String id) => id == 'root'
        ? t.headline
        : id.startsWith('point')
        ? t.footnote
        : t.body;
    LayoutNode node(String id, [List<LayoutNode> children = const []]) {
      final painter = TextPainter(
        text: TextSpan(text: text[id], style: style(id)),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      return LayoutNode(
        id: id,
        width: painter.width + MMSpacing.xl,
        height: painter.height + MMSpacing.l,
        children: children,
      );
    }

    final layout =
        const TreeLayout(
          levelGap: MMSpacing.xl,
          siblingGap: MMSpacing.xl,
          padding: MMSpacing.s,
          structure: LayoutStructure.logic,
        ).layout(
          node('root', [
            for (var i = 0; i < labels.length; i++)
              node('branch-$i', [
                if (i == 0 && depth > 2) ...[
                  node('point-1', [if (depth > 3) node('point-3')]),
                  node('point-2'),
                ],
              ]),
          ]),
        );
    Rect rect(String id) {
      final r = layout.rects[id]!;
      return Rect.fromLTWH(r.left, r.top, r.width, r.height);
    }

    return Semantics(
      label: l.mapGenerateStructurePreview,
      image: true,
      child: ExcludeSemantics(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: layout.width,
            height: layout.height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _StructureEdges(
                      mapConnectors(layout, rect, rootId: 'root'),
                      c.research.withValues(alpha: .65),
                    ),
                  ),
                ),
                for (final id in text.keys)
                  Positioned.fromRect(
                    rect: rect(id),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: id == 'root' ? c.research : c.researchTint,
                        border: Border.all(color: c.research.withValues(alpha: .4), width: MMSizes.hairline),
                        borderRadius: BorderRadius.circular(MMRadii.row),
                      ),
                      child: Center(
                        child: Text(text[id]!, style: style(id).copyWith(color: id == 'root' ? c.onAccent : c.label)),
                      ),
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

class _StructureEdges extends CustomPainter {
  const _StructureEdges(this.connectors, this.color);
  final List<MapConnector> connectors;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = MMSizes.nodeStroke
      ..style = PaintingStyle.stroke;
    for (final connector in connectors) {
      canvas.drawPath(connector.path, paint);
    }
  }

  @override
  bool shouldRepaint(_StructureEdges oldDelegate) => oldDelegate.connectors != connectors || oldDelegate.color != color;
}
