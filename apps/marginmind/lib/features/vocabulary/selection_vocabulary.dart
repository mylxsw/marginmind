import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';

/// Apply the addition and enrichment atomically so a single Undo restores both.
List<VocabularyEntry> saveSelectionVocabulary(
  List<VocabularyEntry> entries, {
  required String selected,
  required String language,
  required VocabularyContext context,
  WordLookupResult? lookup,
  String? translation,
}) {
  const editor = VocabularyEditor();
  final old = entries
      .where(
        (e) =>
            e.language == language &&
            (e.key == vocabularyKey(lookup?.lemma ?? selected) || e.forms.contains(vocabularyKey(selected))),
      )
      .firstOrNull;
  final term = old?.term ?? lookup?.lemma ?? selected;
  final kind = classifyVocabularySelection(selected) == VocabularySelectionKind.word
      ? VocabularyKind.word
      : VocabularyKind.phrase;
  final senses = [
    for (final s in lookup?.senses ?? <WordSense>[]) VocabularySense(partOfSpeech: s.pos, meaning: s.meaning),
  ];
  final input = VocabularyEntry(
    id: old?.id ?? newId(),
    term: term,
    language: language,
    kind: kind,
    createdAt: context.addedAt,
    updatedAt: context.addedAt,
    forms: vocabularyForms(
      term: term,
      selected: selected,
      language: language,
      kind: kind,
      supplied: lookup?.forms ?? [],
    ),
    senses: senses.isNotEmpty
        ? senses
        : translation == null
        ? []
        : [VocabularySense(partOfSpeech: '', meaning: translation)],
    ukPhonetic: lookup?.ukPhonetic,
    usPhonetic: lookup?.usPhonetic,
    gloss: lookup?.gloss ?? '',
    contexts: [context],
  );
  var result = editor.add(entries, input);
  if (old != null && lookup != null) {
    if (old.senses.isEmpty) result = editor.updateSenses(result, old.id, senses, context.addedAt);
    result = [
      for (final e in result)
        if (e.id != old.id)
          e
        else
          e.copyWith(
            ukPhonetic: (old.ukPhonetic ?? '').isEmpty ? lookup.ukPhonetic : old.ukPhonetic,
            usPhonetic: (old.usPhonetic ?? '').isEmpty ? lookup.usPhonetic : old.usPhonetic,
            gloss: old.gloss.isEmpty ? lookup.gloss : old.gloss,
            forms: old.senses.isEmpty && old.forms.length <= 1
                ? {...old.forms, ...input.forms}.take(16).toList()
                : old.forms,
          ),
    ];
  }
  return List.unmodifiable(result);
}
