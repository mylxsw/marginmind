import 'models.dart';
import 'research.dart';

/// Presentation only; changing it never changes the note's blocks.
enum NoteTemplate { reading, cornell, review }

/// How materials are grouped.
enum NoteOrganization { theme, source, map }

/// Allowed contribution from an organizer.
enum NoteDepth { none, context, deep }

/// A live user-authored source (research and images are optional materials).
enum OwnSource { marginNote, card, researchNote, image }

/// The purpose of generated prose.
enum TextKind { summary, gloss, paragraph, action }

/// Persisted selection used again when looking for new materials.
sealed class NoteScope {
  const NoteScope();
  Map<String, Object?> toJson();
  factory NoteScope.fromJson(Map<String, Object?> j) => switch (j['type']) {
    'selected' => SelectedAnnotations((j['ids'] as List).cast<String>()),
    'whole' => const WholeSet(),
    'document' => DocumentScope(j['id'] as String),
    'branch' => BranchScope(j['mapId'] as String, j['nodeId'] as String),
    'since' => SinceScope(DateTime.parse(j['date'] as String)),
    _ => throw const FormatException('Unknown note scope'),
  };
}

/// An explicit, stable selection; later unrelated highlights are excluded.
final class SelectedAnnotations extends NoteScope {
  SelectedAnnotations(List<String> ids) : ids = List.unmodifiable(ids);
  final List<String> ids;
  @override
  Map<String, Object?> toJson() => {'type': 'selected', 'ids': ids};
}

/// All documents and materials in the study set.
final class WholeSet extends NoteScope {
  const WholeSet();
  @override
  Map<String, Object?> toJson() => {'type': 'whole'};
}

/// Materials from a single document.
final class DocumentScope extends NoteScope {
  const DocumentScope(this.id);
  final String id;
  @override
  Map<String, Object?> toJson() => {'type': 'document', 'id': id};
}

/// A map card and all descendants, including folded descendants.
final class BranchScope extends NoteScope {
  const BranchScope(this.mapId, this.nodeId);
  final String mapId, nodeId;
  @override
  Map<String, Object?> toJson() => {'type': 'branch', 'mapId': mapId, 'nodeId': nodeId};
}

/// Materials created on or after a fixed date, e.g. seven days before creation.
final class SinceScope extends NoteScope {
  const SinceScope(this.date);
  final DateTime date;
  @override
  Map<String, Object?> toJson() => {'type': 'since', 'date': date.toIso8601String()};
}

/// Remembered collection and organization options. Highlights are always included.
class NoteSettings {
  NoteSettings({
    this.organization = NoteOrganization.theme,
    this.depth = NoteDepth.deep,
    this.contextSentences = 1,
    this.completeFragments = true,
    this.marginNotes = true,
    this.mapNotes = true,
    this.researchNotes = false,
    this.images = false,
    this.mapId = MindMap.defaultId,
  }) {
    if (contextSentences < 0 || contextSentences > 3) throw ArgumentError.value(contextSentences);
  }
  final NoteOrganization organization;
  final NoteDepth depth;
  final int contextSentences;
  final bool completeFragments, marginNotes, mapNotes, researchNotes, images;
  final String mapId;

  /// Disabling AI also disables thematic organization.
  NoteOrganization get effectiveOrganization =>
      depth == NoteDepth.none && organization == NoteOrganization.theme ? NoteOrganization.source : organization;
  Map<String, Object?> toJson() => {
    'organization': organization.name,
    'depth': depth.name,
    'contextSentences': contextSentences,
    'completeFragments': completeFragments,
    'marginNotes': marginNotes,
    'mapNotes': mapNotes,
    'researchNotes': researchNotes,
    'images': images,
    'mapId': mapId,
  };
  factory NoteSettings.fromJson(Map<String, Object?> j) => NoteSettings(
    organization: NoteOrganization.values.byName(j['organization'] as String? ?? 'theme'),
    depth: NoteDepth.values.byName(j['depth'] as String? ?? 'deep'),
    contextSentences: j['contextSentences'] as int? ?? 1,
    completeFragments: j['completeFragments'] as bool? ?? true,
    marginNotes: j['marginNotes'] as bool? ?? true,
    mapNotes: j['mapNotes'] as bool? ?? true,
    researchNotes: j['researchNotes'] as bool? ?? false,
    images: j['images'] as bool? ?? false,
    mapId: j['mapId'] as String? ?? MindMap.defaultId,
  );
}

/// Immutable blocks with stable IDs; [edited] blocks are protected during organization.
sealed class StudyNoteBlock {
  const StudyNoteBlock({required this.id, required this.origin, this.edited = false});
  final String id;
  final NoteOrigin origin;
  final bool edited;
  Map<String, Object?> toJson();
  Map<String, Object?> get baseJson => {'id': id, 'origin': origin.name, 'edited': edited};
  factory StudyNoteBlock.fromJson(Map<String, Object?> j) {
    final id = j['id'] as String, edited = j['edited'] as bool? ?? false;
    final origin = NoteOrigin.values.byName(j['origin'] as String);
    return switch (j['type']) {
      'quote' => QuoteBlock(
        id: id,
        annotationId: j['annotationId'] as String,
        contextOpen: j['contextOpen'] as bool? ?? false,
        edited: edited,
      ),
      'own' => OwnBlock(
        id: id,
        sourceId: j['sourceId'] as String,
        source: OwnSource.values.byName(j['source'] as String),
        origin: origin,
        edited: edited,
      ),
      'text' => TextBlock(
        id: id,
        text: j['text'] as String,
        kind: TextKind.values.byName(j['kind'] as String),
        annotationId: j['annotationId'] as String?,
        origin: origin,
        edited: edited,
      ),
      'points' => PointsBlock(id: id, items: (j['items'] as List).cast<String>(), origin: origin, edited: edited),
      'xref' => XrefBlock(
        id: id,
        toSectionId: j['toSectionId'] as String,
        text: j['text'] as String,
        origin: origin,
        edited: edited,
      ),
      _ => throw const FormatException('Unknown study note block'),
    };
  }
}

/// A live reference; source text is never copied into this block.
final class QuoteBlock extends StudyNoteBlock {
  const QuoteBlock({required super.id, required this.annotationId, this.contextOpen = false, super.edited})
    : super(origin: NoteOrigin.excerpt);
  final String annotationId;
  final bool contextOpen;
  @override
  Map<String, Object?> toJson() => {
    ...baseJson,
    'type': 'quote',
    'annotationId': annotationId,
    'contextOpen': contextOpen,
  };
}

/// A live reference to a user's note or an optional saved material.
final class OwnBlock extends StudyNoteBlock {
  const OwnBlock({
    required super.id,
    required this.sourceId,
    required this.source,
    super.origin = NoteOrigin.user,
    super.edited,
  });
  final String sourceId;
  final OwnSource source;
  @override
  Map<String, Object?> toJson() => {...baseJson, 'type': 'own', 'sourceId': sourceId, 'source': source.name};
}

/// Prose written by an organizer or the user; glosses may refer to a highlight.
final class TextBlock extends StudyNoteBlock {
  const TextBlock({
    required super.id,
    required this.text,
    this.kind = TextKind.paragraph,
    this.annotationId,
    super.origin = NoteOrigin.ai,
    super.edited,
  });
  final String text;
  final TextKind kind;
  final String? annotationId;
  @override
  Map<String, Object?> toJson() => {
    ...baseJson,
    'type': 'text',
    'text': text,
    'kind': kind.name,
    if (annotationId != null) 'annotationId': annotationId,
  };
}

/// An ordered set of takeaways.
final class PointsBlock extends StudyNoteBlock {
  PointsBlock({required super.id, required List<String> items, super.origin = NoteOrigin.ai, super.edited})
    : items = List.unmodifiable(items);
  final List<String> items;
  @override
  Map<String, Object?> toJson() => {...baseJson, 'type': 'points', 'items': items};
}

/// A stable cross-section link, independent of display order.
final class XrefBlock extends StudyNoteBlock {
  const XrefBlock({
    required super.id,
    required this.toSectionId,
    required this.text,
    super.origin = NoteOrigin.ai,
    super.edited,
  });
  final String toSectionId, text;
  @override
  Map<String, Object?> toJson() => {...baseJson, 'type': 'xref', 'toSectionId': toSectionId, 'text': text};
}

/// One section, including an optional review question.
class NoteSection {
  NoteSection({
    required this.id,
    required this.title,
    this.why,
    this.question,
    this.questionOrigin = NoteOrigin.ai,
    List<StudyNoteBlock> blocks = const [],
  }) : blocks = List.unmodifiable(blocks);
  final String id, title;
  final String? why, question;
  final NoteOrigin questionOrigin;
  final List<StudyNoteBlock> blocks;
  NoteSection copyWith({String? title, List<StudyNoteBlock>? blocks}) => NoteSection(
    id: id,
    title: title ?? this.title,
    why: why,
    question: question,
    questionOrigin: questionOrigin,
    blocks: blocks ?? this.blocks,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'why': why,
    'question': question,
    'questionOrigin': questionOrigin.name,
    'blocks': [for (final b in blocks) b.toJson()],
  };
  factory NoteSection.fromJson(Map<String, Object?> j) => NoteSection(
    id: j['id'] as String,
    title: j['title'] as String,
    why: j['why'] as String?,
    question: j['question'] as String?,
    questionOrigin: NoteOrigin.values.byName(j['questionOrigin'] as String? ?? 'ai'),
    blocks: [for (final b in j['blocks'] as List) StudyNoteBlock.fromJson((b as Map).cast())],
  );
}

/// A written study note stored alongside mind maps in a study set.
class StudyNote {
  StudyNote({
    required this.id,
    required this.title,
    required this.scope,
    this.template = NoteTemplate.reading,
    required this.settings,
    List<NoteSection> sections = const [],
    List<String> unusedAnnotationIds = const [],
    required this.createdAt,
    required this.updatedAt,
    required this.organizedAt,
  }) : sections = List.unmodifiable(sections),
       unusedAnnotationIds = List.unmodifiable(unusedAnnotationIds);
  final String id, title;
  final NoteScope scope;
  final NoteTemplate template;
  final NoteSettings settings;
  final List<NoteSection> sections;
  final List<String> unusedAnnotationIds;
  final DateTime createdAt, updatedAt, organizedAt;
  StudyNote copyWith({
    String? title,
    NoteScope? scope,
    NoteTemplate? template,
    NoteSettings? settings,
    List<NoteSection>? sections,
    List<String>? unusedAnnotationIds,
    DateTime? updatedAt,
    DateTime? organizedAt,
  }) => StudyNote(
    id: id,
    title: title ?? this.title,
    scope: scope ?? this.scope,
    template: template ?? this.template,
    settings: settings ?? this.settings,
    sections: sections ?? this.sections,
    unusedAnnotationIds: unusedAnnotationIds ?? this.unusedAnnotationIds,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    organizedAt: organizedAt ?? this.organizedAt,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'scope': scope.toJson(),
    'template': template.name,
    'settings': settings.toJson(),
    'sections': [for (final s in sections) s.toJson()],
    'unusedAnnotationIds': unusedAnnotationIds,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'organizedAt': organizedAt.toIso8601String(),
  };
  factory StudyNote.fromJson(Map<String, Object?> j) => StudyNote(
    id: j['id'] as String,
    title: j['title'] as String,
    scope: NoteScope.fromJson((j['scope'] as Map).cast()),
    template: NoteTemplate.values.byName(j['template'] as String),
    settings: NoteSettings.fromJson((j['settings'] as Map).cast()),
    sections: [for (final s in j['sections'] as List) NoteSection.fromJson((s as Map).cast())],
    unusedAnnotationIds: (j['unusedAnnotationIds'] as List? ?? []).cast<String>(),
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: DateTime.parse(j['updatedAt'] as String),
    organizedAt: DateTime.parse(j['organizedAt'] as String),
  );
}

/// Only deleted, still-referenced sources are retained; never a second live copy.
class NoteSourceArchive {
  const NoteSourceArchive({required this.annotation, required this.documentTitle});
  final Annotation annotation;
  final String documentTitle;
  Map<String, Object?> toJson() => {'annotation': annotation.toJson(), 'documentTitle': documentTitle};
  factory NoteSourceArchive.fromJson(Map<String, Object?> j) => NoteSourceArchive(
    annotation: Annotation.fromJson((j['annotation'] as Map).cast()),
    documentTitle: j['documentTitle'] as String,
  );
}
