import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:unorm_dart/unorm_dart.dart' as unicode;

import 'translation.dart';

/// Version of the independent translation journal and content key.
const translationStoreVersion = 1;

/// Canonical Unicode composition, collapsed Unicode whitespace, then trim.
String normalizeTranslationText(String text) => unicode
    .nfc(text)
    .replaceAll(RegExp(r'[\s\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]+'), ' ')
    .trim();

/// Content identity; deliberately excludes document, position, model and note.
String textKey(String text, String targetLang, {int splitVersion = translationSplitVersion}) => sha256
    .convert(
      utf8.encode(jsonEncode([translationStoreVersion, splitVersion, normalizeTranslationText(text), targetLang])),
    )
    .toString();

/// Provenance only: changing instructions does not invalidate [textKey].
String translationProfile(String note, {required int promptVersion}) =>
    sha256.convert(utf8.encode(jsonEncode([promptVersion, normalizeTranslationText(note)]))).toString();

/// Why a paragraph can be displayed verbatim without a model request.
enum TranslationSkipReason { repeatedMargin, pageNumber, nonLinguistic, targetLanguage }

/// Finds repeated text at the same margin position (within 3 PDF points).
/// [pageHeights] includes every page, including blank pages, in PDF coordinates.
/// Only the outer 10% of a page qualifies; at least two distinct pages must
/// match, and matches must occupy at least 30% of all pages.
Set<String> translationMarginFingerprints(
  Iterable<TranslationParagraph> paragraphs, {
  required Map<int, double> pageHeights,
}) {
  final candidates = paragraphs.where((p) {
    if (p.textAnchor != null || p.rects.isEmpty) return false;
    final height = pageHeights[p.page];
    return height != null && height > 0 && (p.bounds.top <= height * .1 || p.bounds.bottom >= height * .9);
  }).toList();
  final groups = <String, List<TranslationParagraph>>{};
  for (final p in candidates) {
    groups.putIfAbsent(normalizeTranslationText(p.text), () => []).add(p);
  }
  final result = <String>{};
  for (final group in groups.values) {
    for (final anchor in group) {
      final matches = group
          .where(
            (p) => (p.bounds.left - anchor.bounds.left).abs() <= 3 && (p.bounds.top - anchor.bounds.top).abs() <= 3,
          )
          .toList();
      final pages = matches.map((p) => p.page).toSet();
      if (pages.length >= 2 && pages.length / pageHeights.length >= .3) {
        result.addAll(matches.map((p) => p.fingerprint));
      }
    }
  }
  return Set.unmodifiable(result);
}

/// Conservative local script/word detection. Ambiguous Latin, shared Han and mixed
/// text returns null; callers may supply a trusted detector's language code to
/// [translationSkipReason]. In particular, Han alone cannot distinguish
/// simplified/traditional Chinese or Japanese.
String? detectTranslationLanguage(String text) {
  final letters = RegExp(r'\p{L}', unicode: true).allMatches(text).map((m) => m[0]!).toList();
  if (letters.length < 4) return null;
  double fraction(String pattern) =>
      letters.where((s) => RegExp(pattern, unicode: true).hasMatch(s)).length / letters.length;
  if (fraction(r'[\u3040-\u30ff]') >= .2 && fraction(r'[\u3040-\u30ff\u3400-\u9fff]') >= .9) return 'ja';
  if (fraction(r'[\uac00-\ud7af\u1100-\u11ff]') >= .9) return 'ko';
  if (fraction(r'[\u3400-\u9fff]') >= .9) {
    // Variant-specific characters are evidence; shared Han alone is ambiguous.
    final simplified = RegExp('[这们为个说对从书学习译语汉简体国与还进过来时会实]').hasMatch(text);
    final traditional = RegExp('[這們為個說對從書學習譯語漢簡體國與還進過來時會實]').hasMatch(text);
    if (simplified && !traditional) return 'zh';
    if (traditional && !simplified) return 'zh-Hant';
  }
  // Distinct common function words supply conservative Latin-language evidence.
  // Ties and short snippets stay unknown instead of dropping payable content.
  final words = RegExp(r'\p{L}+', unicode: true).allMatches(text.toLowerCase()).map((m) => m[0]!).toSet();
  const vocabularies = {
    'en': 'the this that these those is are was were have has with from and not your you of to',
    'fr': 'le la les des une un est sont dans pour avec sur pas nous vous et du',
    'de': 'der die das den dem des ist sind ein eine und nicht mit für auf wir sie',
    'es': 'el la los las una un es son para con por del que en no nosotros y',
    'pt': 'o os a as uma um são não para com dos das pelo pela você nós e',
    'it': 'il lo gli le una uno sono nella dello della non per con che noi voi e',
  };
  final scores = [
    for (final entry in vocabularies.entries)
      (language: entry.key, score: entry.value.split(' ').where(words.contains).length),
  ]..sort((a, b) => b.score.compareTo(a.score));
  if (scores.first.score >= 3 &&
      scores.first.score - scores[1].score >= 2 &&
      fraction(r'[A-Za-z\u00c0-\u024f]') >= .9) {
    return scores.first.language;
  }
  // Cyrillic and Arabic scripts are shared by multiple languages; a caller's
  // detector must distinguish Russian from Ukrainian, Arabic from Persian, etc.
  return null;
}

/// Pure no-send classification. Unknown language is never assumed to match.
/// [detectedLanguage] is a confident language/variant code, not a script label.
TranslationSkipReason? translationSkipReason(
  TranslationParagraph paragraph,
  String targetLang, {
  Set<String> marginFingerprints = const {},
  String? detectedLanguage,
}) {
  if (marginFingerprints.contains(paragraph.fingerprint)) return TranslationSkipReason.repeatedMargin;
  final text = normalizeTranslationText(paragraph.text);
  if (RegExp(r'^(?:page\s+)?\d+(?:\s*(?:/|of)\s*\d+)?$', caseSensitive: false).hasMatch(text) ||
      RegExp(r'^第?\s*\d+\s*页$').hasMatch(text)) {
    return TranslationSkipReason.pageNumber;
  }
  if (!RegExp(r'\p{L}', unicode: true).hasMatch(text) ||
      RegExp(r'^(?:(?:https?://|www\.)\S+)(?:\s+(?:https?://|www\.)\S+)*$', caseSensitive: false).hasMatch(text)) {
    return TranslationSkipReason.nonLinguistic;
  }
  if ((detectedLanguage ?? detectTranslationLanguage(text)) == targetLang) return TranslationSkipReason.targetLanguage;
  return null;
}
