import 'dart:convert';

import 'proposals.dart';

enum ExpansionScope { children, group, siblings, map }

enum ExpansionDirection { auto, why, example, counter, question, action }

/// Host-owned IDs never form part of the model payload.
class ExpansionRequest {
  ExpansionRequest({
    required this.studySetId,
    required this.mapId,
    required List<String> targetIds,
    this.scope = ExpansionScope.children,
    this.direction = ExpansionDirection.auto,
    this.depth = 1,
    this.breadth = 5,
    this.hint,
    this.grounded = true,
    Map<String, int> plan = const {},
    this.round = 0,
    this.commonParentId,
  }) : targetIds = List.unmodifiable(targetIds),
       plan = Map.unmodifiable(plan) {
    if (studySetId.isEmpty ||
        mapId.isEmpty ||
        targetIds.isEmpty ||
        targetIds.any((id) => id.isEmpty) ||
        targetIds.toSet().length != targetIds.length ||
        depth < 1 ||
        depth > 3 ||
        !{3, 5, 8}.contains(breadth) ||
        (hint?.runes.length ?? 0) > 200 ||
        round < 0 ||
        plan.values.any((n) => n < 1 || n > breadth) ||
        (scope != ExpansionScope.map && plan.isNotEmpty) ||
        ({ExpansionScope.group, ExpansionScope.siblings}.contains(scope) &&
            (commonParentId == null || commonParentId!.isEmpty))) {
      throw ArgumentError('Invalid expansion request');
    }
  }
  final String studySetId, mapId;
  final List<String> targetIds;
  final ExpansionScope scope;
  final ExpansionDirection direction;
  final int depth, breadth, round;
  final String? hint, commonParentId;
  final bool grounded;
  final Map<String, int> plan;
}

class ExpansionDraft {
  const ExpansionDraft({
    required this.id,
    required this.parentRef,
    required this.title,
    this.tag = ExpansionDirection.auto,
    this.page,
    this.kept = true,
    this.edited = false,
  });
  final String id, parentRef, title;
  final ExpansionDirection tag;
  final int? page;
  final bool kept, edited;
  ExpansionDraft copyWith({String? title, bool? kept, bool? edited}) => ExpansionDraft(
    id: id,
    parentRef: parentRef,
    title: title ?? this.title,
    tag: tag,
    page: page,
    kept: kept ?? this.kept,
    edited: edited ?? this.edited,
  );
}

String normalizeExpansionTitle(String title) {
  final halfWidth = String.fromCharCodes(
    title.runes.map(
      (r) => r == 0x3000
          ? 32
          : r >= 0xff01 && r <= 0xff5e
          ? r - 0xfee0
          : r,
    ),
  );
  return halfWidth.toLowerCase().replaceAll(RegExp(r'[\s\p{P}\p{S}]', unicode: true), '');
}

String expansionTitle(String title) {
  final clean = title.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (RegExp(r'[\u3400-\u9fff]').hasMatch(clean)) return String.fromCharCodes(clean.runes.take(24));
  return clean.split(' ').take(8).join(' ');
}

/// One instance per call. Aliases and provenance are host supplied, not model supplied.
/// Mutated only after a complete valid line. Prefixes must be unique per preview call.
class ExpansionLineContext {
  ExpansionLineContext({
    required Map<String, String> targets,
    required this.request,
    required this.draftPrefix,
    Iterable<String> existingTitles = const [],
    Set<int> pages = const {},
    Map<String, int> limits = const {},
    this.onInvalid,
  }) : targets = Map.unmodifiable(targets),
       pages = Set.unmodifiable(pages),
       limits = Map.unmodifiable(limits),
       _titles = existingTitles.map(normalizeExpansionTitle).toSet() {
    if (targets.isEmpty ||
        targets.keys.any((a) => !RegExp(r'^T[1-9][0-9]*$').hasMatch(a)) ||
        draftPrefix.isEmpty ||
        limits.values.any((n) => n < 1 || n > request.breadth)) {
      throw ArgumentError('Invalid expansion context');
    }
  }
  final ExpansionRequest request;
  final Map<String, String> targets;
  final Map<String, int> limits;
  final Set<int> pages;
  final String draftPrefix;
  final void Function(String reason)? onInvalid;
  final _refs = <String, ExpansionDraft>{};
  final _depths = <String, int>{}, _counts = <String, int>{};
  final Set<String> _titles;
  ExpansionDraft? invalid(String reason) {
    onInvalid?.call(reason);
    return null;
  }
}

ExpansionDraft? parseExpansionLine(String line, ExpansionLineContext ctx) {
  if (line.trim().isEmpty) return null;
  Object? raw;
  try {
    raw = jsonDecode(line);
  } on FormatException {
    return ctx.invalid('json');
  }
  if (raw is! Map<String, dynamic> || raw.keys.any((k) => !{'ref', 'parent', 'title', 'tag', 'page'}.contains(k))) {
    return ctx.invalid('fields');
  }
  final ref = raw['ref'], parent = raw['parent'], title = raw['title'], tag = raw['tag'] ?? 'auto', page = raw['page'];
  if (ref is! String ||
      !RegExp(r'^[a-zA-Z][a-zA-Z0-9_-]{0,63}$').hasMatch(ref) ||
      RegExp(r'^T[0-9]+$').hasMatch(ref) ||
      ctx._refs.containsKey(ref) ||
      parent is! String ||
      title is! String ||
      title.trim().isEmpty ||
      !ExpansionDirection.values.any((d) => d.name == tag) ||
      (page != null && page is! int)) {
    return ctx.invalid('value');
  }
  final ancestor = ctx._refs[parent];
  final parentRef = ctx.targets[parent] ?? (ancestor == null ? null : 'new:${ancestor.id}');
  if (parentRef == null) return ctx.invalid('parent');
  final depth = (ctx._depths[parent] ?? 0) + 1;
  final limit = ctx.request.scope == ExpansionScope.group && ctx.targets.containsKey(parent)
      ? 1
      : ctx.limits[parent] ?? ctx.request.breadth;
  if (depth > ctx.request.depth || (ctx._counts[parent] ?? 0) >= limit) return ctx.invalid('capacity');
  final short = expansionTitle(title), normalized = normalizeExpansionTitle(expansionTitle(title));
  if (normalized.isEmpty || ctx._titles.contains(normalized)) return ctx.invalid('duplicate');
  final draft = ExpansionDraft(
    id: '${ctx.draftPrefix}${ctx._refs.length + 1}',
    parentRef: parentRef,
    title: short,
    tag: ExpansionDirection.values.byName(tag as String),
    page: ctx.request.grounded && ctx.pages.contains(page) ? page as int? : null,
  );
  ctx._refs[ref] = draft;
  ctx._depths[ref] = depth;
  ctx._counts[parent] = (ctx._counts[parent] ?? 0) + 1;
  ctx._titles.add(normalized);
  return draft;
}

/// Cascade deselection; selecting or editing a child restores its ancestors.
List<ExpansionDraft> selectExpansionDraft(List<ExpansionDraft> drafts, String id, bool kept, {String? title}) {
  final byId = {for (final d in drafts) d.id: d};
  if (!byId.containsKey(id)) throw ArgumentError('Unknown draft');
  final affected = <String>{id};
  if (kept || title != null) {
    var current = byId[id]!;
    while (current.parentRef.startsWith('new:')) {
      final parent = byId[current.parentRef.substring(4)];
      if (parent == null || !affected.add(parent.id)) break;
      current = parent;
    }
  } else {
    var changed = true;
    while (changed) {
      changed = false;
      for (final d in drafts) {
        if (d.parentRef.startsWith('new:') && affected.contains(d.parentRef.substring(4)) && affected.add(d.id)) {
          changed = true;
        }
      }
    }
  }
  if (title != null && normalizeExpansionTitle(title).isEmpty) throw ArgumentError('Empty title');
  return List.unmodifiable([
    for (final d in drafts)
      affected.contains(d.id)
          ? d.copyWith(
              kept: title != null || kept,
              title: d.id == id ? title?.trim() : null,
              edited: d.id == id && title != null ? true : null,
            )
          : d,
  ]);
}

MapEditProposal expansionToProposal(
  ExpansionRequest request,
  List<ExpansionDraft> drafts, {
  required String proposalId,
  required int baseRevision,
  Map<String, String?> parents = const {},
}) {
  final byId = {for (final d in drafts) d.id: d};
  if (byId.length != drafts.length || drafts.any((d) => d.id.isEmpty || d.id.startsWith('new:'))) {
    throw ArgumentError('Duplicate or invalid draft ID');
  }
  final state = <String, bool>{}, visiting = <String>{};
  final ordered = <ExpansionDraft>[];
  bool visit(ExpansionDraft d) {
    if (state.containsKey(d.id)) return state[d.id]!;
    if (!visiting.add(d.id)) throw ArgumentError('Draft cycle');
    var keep = d.kept;
    if (d.parentRef.startsWith('new:')) {
      final parent = byId[d.parentRef.substring(4)];
      if (parent == null) throw ArgumentError('Missing draft parent');
      keep = visit(parent) && keep;
    }
    visiting.remove(d.id);
    state[d.id] = keep;
    if (keep) {
      if (d.title.trim().isEmpty) throw ArgumentError('Empty draft title');
      ordered.add(d);
    }
    return keep;
  }

  for (final d in drafts) {
    visit(d);
  }
  final roots = ordered.where((d) => !d.parentRef.startsWith('new:')).toList();
  final destinations = {
    if ({ExpansionScope.group, ExpansionScope.siblings}.contains(request.scope))
      request.commonParentId!
    else
      ...request.targetIds,
    if (request.scope == ExpansionScope.map) ...request.plan.keys,
  };
  if (roots.any((d) => !destinations.contains(d.parentRef))) throw ArgumentError('Invalid destination');
  final ops = [
    for (final d in ordered)
      MapEditOperation(id: d.id, kind: MapEditKind.addTopic, parentId: d.parentRef, title: d.title),
  ];
  if ({ExpansionScope.group, ExpansionScope.siblings}.contains(request.scope)) {
    if (request.targetIds.any(
      (id) => !parents.containsKey(id) || (parents[id] ?? request.mapId) != request.commonParentId,
    )) {
      throw ArgumentError('Selection must share a parent');
    }
  }
  if (request.scope == ExpansionScope.group && ordered.isNotEmpty) {
    if (roots.length != 1) throw ArgumentError('Grouping requires one parent');
    for (var i = 0; i < request.targetIds.length; i++) {
      var moveId = 'move:$i';
      while (byId.containsKey(moveId)) {
        moveId = '$moveId:';
      }
      ops.add(
        MapEditOperation(
          id: moveId,
          kind: MapEditKind.move,
          nodeId: request.targetIds[i],
          parentId: 'new:${roots.single.id}',
        ),
      );
    }
  }
  if (ops.isEmpty) throw ArgumentError('No selected drafts');
  return MapEditProposal.expansion(
    id: proposalId,
    studySetId: request.studySetId,
    mapId: request.mapId,
    baseRevision: baseRevision,
    operations: ops,
  );
}

class ExpansionPlanItem {
  const ExpansionPlanItem({required this.targetId, required this.add, required this.reason, this.title});
  final String targetId;
  final int add;

  /// empty | thin | newBranch; title is present only for a proposed new root branch.
  final String reason;
  final String? title;
}

ExpansionPlanItem? parseExpansionPlanLine(
  String line, {
  required Map<String, String> targets,
  required String rootAlias,
  required int breadth,
}) {
  try {
    final j = jsonDecode(line);
    if (j is! Map<String, dynamic> ||
        j.keys.any((k) => !{'branch', 'add', 'reason', 'title'}.contains(k)) ||
        j['branch'] is! String ||
        !targets.containsKey(j['branch']) ||
        j['add'] is! int ||
        j['add'] < 1 ||
        j['add'] > breadth ||
        !{'empty', 'thin', 'newBranch'}.contains(j['reason'])) {
      return null;
    }
    final fresh = j['reason'] == 'newBranch';
    if (fresh
        ? j['branch'] != rootAlias || j['title'] is! String || normalizeExpansionTitle(j['title']).isEmpty
        : j.containsKey('title') || j['branch'] == rootAlias) {
      return null;
    }
    return ExpansionPlanItem(
      targetId: targets[j['branch']]!,
      add: j['add'],
      reason: j['reason'],
      title: fresh ? expansionTitle(j['title']) : null,
    );
  } on FormatException {
    return null;
  }
}
