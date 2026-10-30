import 'vocabulary.dart';

/// Selection eligibility; sentence includes empty or otherwise ineligible text.
enum VocabularySelectionKind { word, phrase, sentence }

/// Strip surrounding punctuation, then enforce the word / 8-word, 64-rune phrase limits.
VocabularySelectionKind classifyVocabularySelection(String selection) {
  final text = selection.trim().replaceAll(RegExp(r"^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$", unicode: true), '');
  if (text.isEmpty) return VocabularySelectionKind.sentence;
  if (RegExp(r"^[\p{L}]+(?:['’][\p{L}]+)*$", unicode: true).hasMatch(text)) {
    // CJK has no whitespace word boundaries; treat it as a phrase.
    if (!vocabularyCjk.hasMatch(text)) return VocabularySelectionKind.word;
  }
  if (text.runes.length <= 64 &&
      text.split(RegExp(r'\s+')).length <= 8 &&
      !RegExp(r'[.!?;:—。！？；：]').hasMatch(selection.trim())) {
    return VocabularySelectionKind.phrase;
  }
  return VocabularySelectionKind.sentence;
}

/// Scripts matched as substrings rather than Latin word tokens.
final vocabularyCjk = RegExp(r'[\u3400-\u9fff\uf900-\ufaff\u3040-\u30ff]');

/// Small heuristic supplement, not a lemmatizer. Model forms take priority;
/// lemma and selected spelling always have reserved slots (maximum sixteen).
List<String> vocabularyForms({
  required String term,
  required String selected,
  required String language,
  required VocabularyKind kind,
  Iterable<String> supplied = const [],
}) {
  final word = vocabularyKey(term);
  final forms = <String>{word, vocabularyKey(selected), ...supplied.map(vocabularyKey)}..remove('');
  if (language == 'en' && kind == VocabularyKind.word && RegExp(r'^[a-z]+$').hasMatch(word)) {
    final consonantY = RegExp(r'[^aeiou]y$').hasMatch(word);
    final sibilant = RegExp(r'(s|x|z|ch|sh)$').hasMatch(word);
    forms.add(
      consonantY
          ? '${word.substring(0, word.length - 1)}ies'
          : sibilant
          ? '${word}es'
          : '${word}s',
    );
    forms.add(
      consonantY
          ? '${word.substring(0, word.length - 1)}ied'
          : word.endsWith('e')
          ? '${word}d'
          : '${word}ed',
    );
    final cvc = word.length <= 4 && RegExp(r'[^aeiou][aeiou][^aeiouwxy]$').hasMatch(word);
    final stem = cvc ? '$word${word[word.length - 1]}' : word;
    if (cvc) forms.add('${stem}ed');
    forms.add(
      word.endsWith('ie')
          ? '${word.substring(0, word.length - 2)}ying'
          : word.endsWith('e') && !word.endsWith('ee')
          ? '${word.substring(0, word.length - 1)}ing'
          : '${stem}ing',
    );
    final comparison = consonantY
        ? '${word.substring(0, word.length - 1)}i'
        : word.endsWith('e')
        ? word.substring(0, word.length - 1)
        : stem;
    forms.addAll(['${comparison}er', '${comparison}est']);
    forms.add(consonantY ? '${word.substring(0, word.length - 1)}ily' : '${word}ly');
  }
  return List.unmodifiable(forms.take(16));
}
