import 'dart:convert';

import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';

import '../research/research_origin.dart' show researchCardTitle;

/// Builds model text from a single immutable map snapshot. Structural IDs stay local.
class ExpansionContextBuilder {
  const ExpansionContextBuilder(this.reader);
  final StudySetReader reader;

  Future<ExpansionContext> build(
    StudySetContent snapshot,
    ExpansionRequest request, {
    String? focusDocumentId,
    List<String> excludedTitles = const [],
    List<ExpansionDraft> draftTargets = const [],
    CancellationToken? cancellation,
    int tokenBudget = 6000,
    String draftPrefix = 'd',
  }) async {
    final cancel = cancellation ?? CancellationToken();
    cancel.check();
    if (snapshot.map(request.mapId) == null ||
        request.scope != ExpansionScope.children ||
        request.targetIds.length != 1) {
      throw const ResearchFailure(ResearchFailureKind.invalidRequest);
    }
    final target = request.targetIds.single;
    final drafts = {for (final d in draftTargets) 'new:${d.id}': d};
    String title(String id) => drafts[id]?.title ?? researchCardTitle(snapshot, id);
    String? parent(String id) => drafts[id]?.parentRef ?? snapshot.node(id, mapId: request.mapId)?.parentId;
    if (snapshot.node(target, mapId: request.mapId) == null && !drafts.containsKey(target)) {
      throw const ResearchFailure(ResearchFailureKind.invalidRequest);
    }
    var remaining = tokenBudget - 400 - utf8.encode(request.hint ?? '').length;
    String take(String text) {
      final result = StringBuffer();
      for (final rune in text.runes) {
        final char = String.fromCharCode(rune), cost = utf8.encode(String.fromCharCode(rune)).length;
        if (cost > remaining) break;
        remaining -= cost;
        result.write(char);
      }
      return result.toString();
    }

    final targetTitle = title(target);
    if (remaining < utf8.encode(targetTitle).length + 64) throw const ResearchFailure(ResearchFailureKind.budget);
    final path = <String>[];
    final visited = <String>{target};
    var ancestor = parent(target);
    while (ancestor != null && visited.add(ancestor)) {
      path.insert(0, title(ancestor));
      ancestor = parent(ancestor);
    }
    final rootTitle = snapshot.map(request.mapId)!.title;
    final safeTitle = take(targetTitle);
    final safePath = [
      for (final p in [rootTitle, ...path])
        if (remaining > 0) take(p),
    ];
    final children = [for (final n in snapshot.childrenOf(target, mapId: request.mapId)) title(n.cardId)];
    final siblings = [for (final n in snapshot.childrenOf(parent(target), mapId: request.mapId)) title(n.cardId)];
    List<String> bounded(List<String> values) => [
      for (final v in values)
        if (remaining > 0) take(v),
    ];
    final safeChildren = bounded(children), safeSiblings = bounded(siblings), excluded = bounded(excludedTitles);
    final pages = <int, String>{};
    if (request.grounded && remaining > 0) {
      // Closest branch excerpts first; one document prevents ambiguous page labels.
      var sourceTarget = target;
      final draftPath = <String>{};
      while (drafts.containsKey(sourceTarget) && draftPath.add(sourceTarget)) {
        sourceTarget = drafts[sourceTarget]!.parentRef;
      }
      final ids = <String>{sourceTarget}, queue = <String>[sourceTarget];
      for (var i = 0; i < queue.length; i++) {
        for (final node in snapshot.childrenOf(queue[i], mapId: request.mapId)) {
          if (ids.add(node.cardId)) queue.add(node.cardId);
        }
      }
      final annotations = [
        for (final id in ids.where((id) => snapshot.card(id)?.kind != CardKind.image))
          if (snapshot.card(id) case final card?)
            for (final segment in snapshot.segmentsOf(card)) ?snapshot.annotation(segment.annotationId ?? ''),
      ];
      final documentId = focusDocumentId ?? annotations.firstOrNull?.documentId;
      final document = documentId == null ? null : snapshot.document(documentId);
      if (document != null) {
        final requested = <int>{};
        for (final a in annotations.where((a) => a.documentId == documentId && !a.isText)) {
          for (var p = a.page - 1; p <= a.page + 1; p++) {
            if (p >= 1 && p <= document.pageCount) requested.add(p);
          }
        }
        final scope = ReadScope(studySetId: request.studySetId, pages: {document.id: requested});
        for (final p in requested) {
          cancel.check();
          if (remaining <= 0) break;
          for (final page in await reader.readPages(document.id, p, p, scope, cancel)) {
            final text = take(page.text);
            if (text.trim().isNotEmpty) pages[page.page] = text;
          }
        }
      }
    }
    cancel.check();
    return ExpansionContext(
      targets: {'T1': target},
      details: {
        'T1': ExpansionTargetContext(
          title: safeTitle,
          path: safePath,
          children: safeChildren,
          siblings: safeSiblings,
          pages: pages,
        ),
      },
      excludedTitles: excluded,
      draftPrefix: draftPrefix,
    );
  }
}
