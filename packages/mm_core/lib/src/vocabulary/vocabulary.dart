import '../content/models.dart';
import '../content/text_anchor.dart';

/// Learning state, independent of study sets and review scheduling.
enum VocabularyStatus { learning, known }

/// A dictionary word or a short expression.
enum VocabularyKind { word, phrase }

/// Canonical spelling used with language as the entry's identity.
String vocabularyKey(String value) => value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// One dictionary meaning.
class VocabularySense {
  const VocabularySense({required this.partOfSpeech, required this.meaning});
  final String partOfSpeech, meaning;
  Map<String, Object?> toJson() => {'partOfSpeech': partOfSpeech, 'meaning': meaning};
  factory VocabularySense.fromJson(Map<String, Object?> j) =>
      VocabularySense(partOfSpeech: j['partOfSpeech'] as String, meaning: j['meaning'] as String);
}

/// A source snapshot that survives deletion of its document.
class VocabularyContext {
  VocabularyContext({
    required this.id,
    required this.studySetId,
    required this.documentId,
    required this.studySetTitle,
    required this.documentTitle,
    required this.sentence,
    required this.hit,
    required this.addedAt,
    this.sentenceTranslation,
    this.textAnchor,
    this.page,
    List<PageRect> rects = const [],
  }) : rects = List.unmodifiable(rects) {
    if (id.isEmpty ||
        studySetId.isEmpty ||
        documentId.isEmpty ||
        sentence.trim().isEmpty ||
        hit.trim().isEmpty ||
        (page != null && page! < 1)) {
      throw ArgumentError('Invalid vocabulary context');
    }
    textAnchor?.validate();
  }
  final String id, studySetId, documentId, studySetTitle, documentTitle, sentence, hit;
  final String? sentenceTranslation;
  final TextAnchor? textAnchor;
  final int? page;
  final List<PageRect> rects;
  final DateTime addedAt;

  /// Sentence identity includes its source; repeated locations in one document merge.
  (String, String, String) get identity => (studySetId, documentId, sentence.trim().replaceAll(RegExp(r'\s+'), ' '));
  Map<String, Object?> toJson() => {
    'id': id,
    'studySetId': studySetId,
    'documentId': documentId,
    'studySetTitle': studySetTitle,
    'documentTitle': documentTitle,
    'sentence': sentence,
    'hit': hit,
    'addedAt': addedAt.toIso8601String(),
    if (sentenceTranslation != null) 'sentenceTranslation': sentenceTranslation,
    if (textAnchor != null) 'textAnchor': textAnchor!.toJson(),
    if (page != null) 'page': page,
    'rects': rects.map((r) => r.toJson()).toList(),
  };
  factory VocabularyContext.fromJson(Map<String, Object?> j) => VocabularyContext(
    id: j['id'] as String,
    studySetId: j['studySetId'] as String,
    documentId: j['documentId'] as String,
    studySetTitle: j['studySetTitle'] as String,
    documentTitle: j['documentTitle'] as String,
    sentence: j['sentence'] as String,
    hit: j['hit'] as String,
    addedAt: DateTime.parse(j['addedAt'] as String),
    sentenceTranslation: j['sentenceTranslation'] as String?,
    page: j['page'] as int?,
    textAnchor: j['textAnchor'] == null ? null : TextAnchor.fromJson((j['textAnchor'] as Map).cast()),
    rects: (j['rects'] as List).map((r) => PageRect.fromJson((r as Map).cast())).toList(),
  );
}

/// Immutable application-wide entry. Collections cannot be mutated by callers.
class VocabularyEntry {
  VocabularyEntry({
    required this.id,
    required this.term,
    required this.language,
    required this.kind,
    required this.createdAt,
    required this.updatedAt,
    required List<String> forms,
    this.ukPhonetic,
    this.usPhonetic,
    List<VocabularySense> senses = const [],
    this.gloss = '',
    this.note = '',
    this.status = VocabularyStatus.learning,
    List<VocabularyContext> contexts = const [],
  }) : forms = List.unmodifiable(forms),
       senses = List.unmodifiable(senses),
       contexts = List.unmodifiable(contexts) {
    if (id.isEmpty ||
        key.isEmpty ||
        language.isEmpty ||
        forms.isEmpty ||
        forms.length > 16 ||
        forms.any((f) => f.isEmpty || f != vocabularyKey(f)) ||
        forms.toSet().length != forms.length ||
        !forms.contains(key) ||
        senses.length > 6 ||
        gloss.runes.length > 8 ||
        contexts.length > 20) {
      throw ArgumentError('Invalid vocabulary entry');
    }
  }
  final String id, term, language, gloss, note;
  String get key => vocabularyKey(term);
  final VocabularyKind kind;
  final List<String> forms;
  final String? ukPhonetic, usPhonetic;
  final List<VocabularySense> senses;
  final VocabularyStatus status;
  final List<VocabularyContext> contexts;
  final DateTime createdAt, updatedAt;

  /// Editable fields; identity and creation time stay stable.
  VocabularyEntry copyWith({
    List<String>? forms,
    List<VocabularySense>? senses,
    String? gloss,
    String? note,
    VocabularyStatus? status,
    List<VocabularyContext>? contexts,
    DateTime? updatedAt,
  }) => VocabularyEntry(
    id: id,
    term: term,
    language: language,
    kind: kind,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    forms: forms ?? this.forms,
    senses: senses ?? this.senses,
    gloss: gloss ?? this.gloss,
    note: note ?? this.note,
    status: status ?? this.status,
    contexts: contexts ?? this.contexts,
    ukPhonetic: ukPhonetic,
    usPhonetic: usPhonetic,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'term': term,
    'key': key,
    'language': language,
    'kind': kind.name,
    'forms': forms,
    'ukPhonetic': ukPhonetic,
    'usPhonetic': usPhonetic,
    'senses': senses.map((s) => s.toJson()).toList(),
    'gloss': gloss,
    'note': note,
    'status': status.name,
    'contexts': contexts.map((c) => c.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
  factory VocabularyEntry.fromJson(Map<String, Object?> j) {
    final entry = VocabularyEntry(
      id: j['id'] as String,
      term: j['term'] as String,
      language: j['language'] as String,
      kind: VocabularyKind.values.byName(j['kind'] as String),
      forms: (j['forms'] as List).cast<String>(),
      ukPhonetic: j['ukPhonetic'] as String?,
      usPhonetic: j['usPhonetic'] as String?,
      senses: (j['senses'] as List).map((s) => VocabularySense.fromJson((s as Map).cast())).toList(),
      gloss: j['gloss'] as String,
      note: j['note'] as String,
      status: VocabularyStatus.values.byName(j['status'] as String),
      contexts: (j['contexts'] as List).map((c) => VocabularyContext.fromJson((c as Map).cast())).toList(),
      createdAt: DateTime.parse(j['createdAt'] as String),
      updatedAt: DateTime.parse(j['updatedAt'] as String),
    );
    if (j['key'] != entry.key) {
      throw const FormatException('Invalid vocabulary key');
    }
    return entry;
  }
}

/// Persistence port. Watch emits an initial snapshot and successful commits only.
abstract interface class VocabularyRepository {
  /// Load the latest committed snapshot; malformed storage must throw.
  Future<List<VocabularyEntry>> load();

  /// Persist a complete snapshot, acknowledging only successful commits.
  Future<void> save(List<VocabularyEntry> entries);

  /// Emit the initial snapshot, then each successful commit.
  Stream<List<VocabularyEntry>> watch();
}
