import 'note_material.dart';
import 'research.dart';
import 'study_note.dart';

Map<String, Object?> _object(Object? value) {
  if (value is! Map || value.keys.any((k) => k is! String)) throw const FormatException('Expected object');
  return value.cast<String, Object?>();
}

String _string(Object? value) {
  if (value is! String || value.trim().isEmpty) throw const FormatException('Expected nonempty string');
  return value;
}

List<Object?> _list(Object? value) {
  if (value is! List) throw const FormatException('Expected array');
  return value;
}

void _keys(Map<String, Object?> j, Set<String> allowed) {
  if (j.keys.any((k) => !allowed.contains(k))) throw const FormatException('Unexpected field');
}

/// One proposed section; refs point exclusively into the supplied collection.
class NoteOutlineSection {
  NoteOutlineSection({required this.title, required List<String> refs, this.why}) : refs = List.unmodifiable(refs);
  final String title;
  final List<String> refs;
  final String? why;
  Map<String, Object?> toJson() => {'title': title, 'refs': refs, if (why != null) 'why': why};
}

/// Editable thematic outline, or the deterministic local outline.
class NoteOutline {
  NoteOutline(List<NoteOutlineSection> sections) : sections = List.unmodifiable(sections);
  final List<NoteOutlineSection> sections;
  Map<String, Object?> toJson() => {'sections': sections.map((s) => s.toJson()).toList()};
  factory NoteOutline.fromJson(Map<String, Object?> j) {
    _keys(j, {'sections'});
    return NoteOutline([
      for (final item in _list(j['sections']))
        (() {
          final s = _object(item);
          _keys(s, {'title', 'refs', 'why'});
          return NoteOutlineSection(
            title: _string(s['title']),
            refs: _list(s['refs']).map(_string).toList(),
            why: s['why'] == null ? null : _string(s['why']),
          );
        })(),
    ]);
  }
}

/// Validated model block. Quotes and own notes accept a ref only, never text.
class NoteDraftBlock {
  NoteDraftBlock._(this.type, this.ref, this.text, this.items, this.to);
  factory NoteDraftBlock.fromJson(Map<String, Object?> j) {
    final type = _string(j['type']);
    final allowed = switch (type) {
      'quote' || 'own' => {'type', 'ref'},
      'gloss' => {'type', 'ref', 'text'},
      'summary' || 'paragraph' || 'action' => {'type', 'text'},
      'points' => {'type', 'items'},
      'xref' => {'type', 'to', 'text'},
      _ => throw const FormatException('Unknown draft block'),
    };
    _keys(j, allowed);
    final ref = allowed.contains('ref') ? _string(j['ref']) : null;
    final text = allowed.contains('text') ? _string(j['text']) : null;
    final items = allowed.contains('items') ? _list(j['items']).map(_string).toList() : <String>[];
    final to = j['to'];
    if (type == 'xref' && (to is! int || to < 0)) throw const FormatException('Invalid cross-reference index');
    if (type == 'points' && items.isEmpty) throw const FormatException('Empty points');
    return NoteDraftBlock._(type, ref, text, List.unmodifiable(items), to as int?);
  }
  final String type;
  final String? ref, text;
  final List<String> items;
  final int? to;
  Map<String, Object?> toJson() => {
    'type': type,
    if (ref != null) 'ref': ref,
    if (text != null) 'text': text,
    if (type == 'points') 'items': items,
    if (to != null) 'to': to,
  };
}

/// Written section; question is generated prose, not a source quotation.
class NoteDraftSection {
  NoteDraftSection({required this.title, required List<NoteDraftBlock> blocks, this.why, this.question})
    : blocks = List.unmodifiable(blocks);
  final String title;
  final String? why, question;
  final List<NoteDraftBlock> blocks;
  Map<String, Object?> toJson() => {
    'title': title,
    if (why != null) 'why': why,
    if (question != null) 'question': question,
    'blocks': blocks.map((b) => b.toJson()).toList(),
  };
}

/// Validated ID-only result from write. Constructor never accepts quote text.
class NoteDraft {
  NoteDraft(List<NoteDraftSection> sections) : sections = List.unmodifiable(sections);
  final List<NoteDraftSection> sections;
  Map<String, Object?> toJson() => {'sections': sections.map((s) => s.toJson()).toList()};
  factory NoteDraft.fromJson(Map<String, Object?> j) {
    _keys(j, {'sections'});
    return NoteDraft([
      for (final item in _list(j['sections']))
        (() {
          final s = _object(item);
          _keys(s, {'title', 'why', 'question', 'blocks'});
          return NoteDraftSection(
            title: _string(s['title']),
            why: s['why'] == null ? null : _string(s['why']),
            question: s['question'] == null ? null : _string(s['question']),
            blocks: [for (final b in _list(s['blocks'])) NoteDraftBlock.fromJson(_object(b))],
          );
        })(),
    ]);
  }
}

/// Preview insertion. Null section creates a new section; null after appends.
class NotePlacement {
  const NotePlacement({
    required this.ref,
    this.sectionId,
    this.afterBlockId,
    this.beforeBlockId,
    this.newSectionKey,
    required this.title,
    required this.why,
  });
  final String ref, title, why;
  final String? sectionId, afterBlockId, beforeBlockId;

  /// Groups new sections without conflating identically titled chapters.
  final String? newSectionKey;
  Map<String, Object?> toJson() => {
    'ref': ref,
    'sectionId': sectionId,
    'afterBlockId': afterBlockId,
    if (beforeBlockId != null) 'beforeBlockId': beforeBlockId,
    if (newSectionKey != null) 'newSectionKey': newSectionKey,
    'title': title,
    'why': why,
  };
}

/// Validated placement plan; applying it is a separate user-confirmed edit.
class NotePlacements {
  NotePlacements(List<NotePlacement> items) : items = List.unmodifiable(items);
  final List<NotePlacement> items;
  Map<String, Object?> toJson() => {'placements': items.map((p) => p.toJson()).toList()};
  factory NotePlacements.fromJson(Map<String, Object?> j) {
    _keys(j, {'placements'});
    return NotePlacements([
      for (final item in _list(j['placements']))
        (() {
          final p = _object(item);
          _keys(p, {'ref', 'sectionId', 'afterBlockId', 'beforeBlockId', 'newSectionKey', 'title', 'why'});
          return NotePlacement(
            ref: _string(p['ref']),
            title: _string(p['title']),
            why: _string(p['why']),
            sectionId: p['sectionId'] == null ? null : _string(p['sectionId']),
            afterBlockId: p['afterBlockId'] == null ? null : _string(p['afterBlockId']),
            beforeBlockId: p['beforeBlockId'] == null ? null : _string(p['beforeBlockId']),
            newSectionKey: p['newSectionKey'] == null ? null : _string(p['newSectionKey']),
          );
        })(),
    ]);
  }
}

/// Model-independent port. Implementations must validate external JSON with the
/// DTO factories and retain the supplied short-ID dictionary for the whole run.
abstract interface class NoteOrganizer {
  Future<NoteOutline> outline(NoteMaterials materials, NoteSettings settings);
  Future<NoteDraft> write(NoteMaterials materials, NoteOutline outline, NoteSettings settings);
  Future<NotePlacements> place(NoteMaterials materials, StudyNote note);
}

/// No model calls: stable chapter or map-branch grouping and source references.
class LocalNoteOrganizer implements NoteOrganizer {
  const LocalNoteOrganizer();
  @override
  Future<NoteOutline> outline(NoteMaterials materials, NoteSettings settings) async {
    final map = settings.effectiveOrganization == NoteOrganization.map;
    final items = materials.items.toList();
    if (map) {
      final original = {for (final (i, m) in items.indexed) m.ref: i};
      items.sort((a, b) {
        final order = a.mapOrder.compareTo(b.mapOrder);
        return order != 0 ? order : original[a.ref]!.compareTo(original[b.ref]!);
      });
    }
    final groups = <String, List<NoteMaterial>>{};
    for (final m in items) {
      groups.putIfAbsent(map ? m.branchKey ?? m.groupKey : m.groupKey, () => []).add(m);
    }
    return NoteOutline([
      for (final group in groups.values)
        NoteOutlineSection(
          title: (map ? group.first.branchTitle : null) ?? group.first.groupTitle,
          refs: group.map((m) => m.ref).toList(),
        ),
    ]);
  }

  @override
  Future<NoteDraft> write(NoteMaterials materials, NoteOutline outline, NoteSettings settings) async => NoteDraft([
    for (final section in outline.sections)
      NoteDraftSection(
        title: section.title,
        why: section.why,
        blocks: [
          for (final ref in section.refs)
            if (materials[ref] case final m?)
              NoteDraftBlock.fromJson({'type': m.isHighlight ? 'quote' : 'own', 'ref': ref}),
        ],
      ),
  ]);
  @override
  Future<NotePlacements> place(NoteMaterials materials, StudyNote note) async {
    final map = note.settings.effectiveOrganization == NoteOrganization.map;
    final ordered = materials.catalog.toList();
    if (map) {
      final ranks = {for (final (i, m) in ordered.indexed) m.ref: i};
      ordered.sort((a, b) {
        final byMap = a.mapOrder.compareTo(b.mapOrder);
        return byMap != 0 ? byMap : ranks[a.ref]!.compareTo(ranks[b.ref]!);
      });
    }
    final rank = {for (final (i, m) in ordered.indexed) m.sourceId: i};
    String group(NoteMaterial m) => map ? m.branchKey ?? m.groupKey : m.groupKey;
    final bySource = {for (final m in ordered) '${m.source}:${m.sourceId}': m};
    return NotePlacements([
      for (final m in materials.items)
        (() {
          final title = map ? m.branchTitle ?? m.groupTitle : m.groupTitle;
          final section = note.sections
              .where(
                (s) => s.blocks.any((b) {
                  final sourceKey = switch (b) {
                    QuoteBlock() => 'null:${b.annotationId}',
                    OwnBlock() => '${b.source}:${b.sourceId}',
                    _ => null,
                  };
                  final source = bySource[sourceKey];
                  return source != null && group(source) == group(m);
                }),
              )
              .firstOrNull;
          final quotes = section?.blocks.whereType<QuoteBlock>().toList() ?? <QuoteBlock>[];
          final following = quotes.where((q) => (rank[q.annotationId] ?? -1) > rank[m.sourceId]!).firstOrNull;
          return NotePlacement(
            ref: m.ref,
            sectionId: section?.id,
            beforeBlockId: m.isHighlight ? following?.id : null,
            newSectionKey: group(m),
            title: title,
            why: '按原文或脑图顺序',
          );
        })(),
    ]);
  }
}

/// Assembly diagnostics are visible to the caller; unknown IDs are never guessed.
class NoteAssembly {
  NoteAssembly({
    required List<NoteSection> sections,
    required List<String> unusedAnnotationIds,
    required List<String> rejectedRefs,
    required this.usedHighlights,
  }) : sections = List.unmodifiable(sections),
       unusedAnnotationIds = List.unmodifiable(unusedAnnotationIds),
       rejectedRefs = List.unmodifiable(rejectedRefs);
  final List<NoteSection> sections;
  final List<String> unusedAnnotationIds, rejectedRefs;
  final int usedHighlights;
}

/// Resolves short IDs to stable source IDs and constructs safe domain blocks.
class NoteAssembler {
  const NoteAssembler();
  NoteAssembly assemble(
    NoteDraft draft,
    NoteMaterials materials, {
    required String Function() newId,
    NoteOrigin generatedOrigin = NoteOrigin.ai,
  }) {
    final used = <String>{}, ownUsed = <String>{}, rejected = <String>[];
    final sectionIds = [for (final _ in draft.sections) newId()];
    final sections = <NoteSection>[];
    OwnBlock own(NoteMaterial m) => OwnBlock(id: newId(), sourceId: m.sourceId, source: m.source!, origin: m.origin);
    for (final (index, section) in draft.sections.indexed) {
      final blocks = <StudyNoteBlock>[];
      for (final b in section.blocks) {
        final m = b.ref == null ? null : materials[b.ref!];
        if (b.ref != null &&
            (m == null ||
                ((b.type == 'quote' || b.type == 'gloss') && !m.isHighlight) ||
                (b.type == 'own' && m.isHighlight))) {
          rejected.add(b.ref!);
          continue;
        }
        switch (b.type) {
          case 'quote':
            if (!used.add(m!.sourceId)) break;
            blocks.add(QuoteBlock(id: newId(), annotationId: m.sourceId, contextOpen: m.context.fragment));
            for (final n in materials.items.where((n) => !n.isHighlight && n.annotationId == m.sourceId)) {
              if (ownUsed.add('${n.source}:${n.sourceId}')) blocks.add(own(n));
            }
          case 'own':
            if (ownUsed.add('${m!.source}:${m.sourceId}')) blocks.add(own(m));
          case 'points':
            blocks.add(PointsBlock(id: newId(), items: b.items, origin: generatedOrigin));
          case 'xref':
            if (b.to! >= sectionIds.length || b.to == index) {
              rejected.add('section:${b.to}');
              break;
            }
            blocks.add(XrefBlock(id: newId(), toSectionId: sectionIds[b.to!], text: b.text!, origin: generatedOrigin));
          default:
            blocks.add(
              TextBlock(
                id: newId(),
                text: b.text!,
                kind: TextKind.values.byName(b.type),
                annotationId: b.type == 'gloss' ? m!.sourceId : null,
                origin: generatedOrigin,
              ),
            );
        }
      }
      if (blocks.isNotEmpty) {
        sections.add(
          NoteSection(
            id: sectionIds[index],
            title: section.title,
            why: section.why,
            question: section.question,
            questionOrigin: generatedOrigin,
            blocks: blocks,
          ),
        );
      }
    }
    // Remove dangling xrefs, including chains whose destination becomes empty.
    var clean = sections;
    while (true) {
      final ids = clean.map((s) => s.id).toSet();
      final next = [
        for (final s in clean)
          s.copyWith(blocks: s.blocks.where((b) => b is! XrefBlock || ids.contains(b.toSectionId)).toList()),
      ].where((s) => s.blocks.isNotEmpty).toList();
      if (next.length == clean.length) {
        clean = next;
        break;
      }
      clean = next;
    }
    return NoteAssembly(
      sections: clean,
      unusedAnnotationIds: materials.highlights
          .map((m) => m.sourceId)
          .where((id) => !used.contains(id))
          .toSet()
          .toList(),
      rejectedRefs: rejected,
      usedHighlights: used.length,
    );
  }
}

/// Retry malformed structured output once, then fall back to local organization.
/// Transport/cancellation errors propagate so a caller can retain streamed work.
class NoteOrganizationResult {
  const NoteOrganizationResult(this.assembly, {required this.usedFallback});
  final NoteAssembly assembly;
  final bool usedFallback;
}

/// Stateless orchestration for both production and fake organizers in tests.
class NoteOrganizationRunner {
  const NoteOrganizationRunner();
  Future<NoteOrganizationResult> run(
    NoteOrganizer organizer,
    NoteMaterials materials,
    NoteSettings settings, {
    required String Function() newId,
  }) async {
    if (settings.depth != NoteDepth.none) {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final outline = NoteOutline.fromJson((await organizer.outline(materials, settings)).toJson());
          final draft = NoteDraft.fromJson((await organizer.write(materials, outline, settings)).toJson());
          return NoteOrganizationResult(
            const NoteAssembler().assemble(draft, materials, newId: newId),
            usedFallback: false,
          );
        } on FormatException {
          /* Retry only invalid structured output. */
        }
      }
    }
    const local = LocalNoteOrganizer();
    final localSettings = NoteSettings(
      organization: settings.effectiveOrganization == NoteOrganization.map
          ? NoteOrganization.map
          : NoteOrganization.source,
      depth: NoteDepth.none,
    );
    final draft = await local.write(materials, await local.outline(materials, localSettings), localSettings);
    return NoteOrganizationResult(
      const NoteAssembler().assemble(draft, materials, newId: newId, generatedOrigin: NoteOrigin.user),
      usedFallback: settings.depth != NoteDepth.none,
    );
  }
}
