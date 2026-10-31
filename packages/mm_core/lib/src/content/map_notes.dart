import 'models.dart';
import 'study_set_content.dart';

/// Presentation of ordinary notes as part of their owning map node. Storage
/// stays unchanged, so review, clipboard, history and older packages retain
/// their note identities. Notes used as relation/summary anchors remain nodes:
/// folding those into another node would erase a meaningful connection.
class MapNoteAttachments {
  MapNoteAttachments(StudySetContent content, {String mapId = MindMap.defaultId}) {
    final cards = {for (final c in content.cards) c.id: c};
    final placed = {
      for (final n in content.nodes)
        if (n.mapId == mapId) n.cardId: n,
    };
    final anchors = <String>{
      for (final r in content.relations.where((r) => r.mapId == mapId)) ...[r.fromId, r.toId],
      for (final s in content.summaries.where((s) => s.mapId == mapId)) ...[s.fromId, s.toId, ?s.parentId, ?s.cardId],
    };
    bool attachable(String id) =>
        cards[id]?.kind == CardKind.note && placed[id]?.parentId != null && !anchors.contains(id);
    for (final n in placed.values) {
      if (!attachable(n.cardId)) continue;
      var parent = n.parentId;
      final seen = {n.cardId};
      while (parent != null && placed.containsKey(parent) && seen.add(parent)) {
        if (!attachable(parent)) {
          if (cards.containsKey(parent)) owners[n.cardId] = parent;
          break;
        }
        parent = placed[parent]?.parentId;
      }
    }
    // Flatten note-only levels without dropping the topics underneath them.
    // Lexicographic order paths preserve the original visual reading order.
    List<double> path(MapNode n) {
      final result = [n.order];
      var parent = n.parentId;
      final seen = {n.cardId};
      while (parent != null && owners.containsKey(parent) && seen.add(parent)) {
        final ancestor = placed[parent]!;
        result.insert(0, ancestor.order);
        parent = ancestor.parentId;
      }
      return result;
    }

    int compare(MapNode a, MapNode b) {
      final pa = path(a), pb = path(b);
      for (var i = 0; i < pa.length && i < pb.length; i++) {
        final order = pa[i].compareTo(pb[i]);
        if (order != 0) return order;
      }
      return pa.length.compareTo(pb.length);
    }

    final ordered = placed.values.toList()..sort(compare);
    final orders = <String?, int>{};
    for (final n in ordered) {
      final owner = owners[n.cardId];
      if (owner != null) {
        notes.putIfAbsent(owner, () => []).add(cards[n.cardId]!);
      } else {
        final parent = owners[n.parentId] ?? n.parentId;
        final order = orders.update(parent, (v) => v + 1, ifAbsent: () => 0);
        nodes.add(n.copyWith(parentId: parent, order: order.toDouble()));
      }
    }
  }

  final Map<String, String> owners = {};
  final Map<String, List<Card>> notes = {};
  final List<MapNode> nodes = [];
}
