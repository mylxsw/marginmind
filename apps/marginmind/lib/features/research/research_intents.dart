import 'package:mm_core/mm_core.dart';

/// What the user wants from a research, chosen on the launcher. It presets
/// the question, the method and the kinds of sources.
enum ResearchIntent { explain, interpret, verify, video, paper, deep, translate }

/// How a research runs. Stored in the session as `mode`.
enum ResearchMethod {
  /// Find sources only: no AI, no AI cost.
  search,

  /// Ask the AI with the confirmed context only; nothing is searched.
  offline,

  /// The AI searches and reads, then answers from what it read.
  web;

  static ResearchMethod parse(String? name) => values.where((m) => m.name == name).firstOrNull ?? ResearchMethod.search;

  ResearchMode? get mode => switch (this) {
    search => null,
    offline => ResearchMode.offline,
    web => ResearchMode.web,
  };
}

/// Kinds of sources a search covers. Only papers have a built-in index
/// (OpenAlex); the others are searched in the browser.
enum ResearchSourceKind { web, paper, video, image }

extension ResearchIntentDefaults on ResearchIntent {
  /// The method this intent suggests when every method is available.
  ResearchMethod get method => switch (this) {
    ResearchIntent.explain || ResearchIntent.interpret || ResearchIntent.translate => ResearchMethod.offline,
    ResearchIntent.video => ResearchMethod.search,
    ResearchIntent.verify || ResearchIntent.paper || ResearchIntent.deep => ResearchMethod.web,
  };

  Set<ResearchSourceKind> get kinds => switch (this) {
    ResearchIntent.verify || ResearchIntent.deep => {ResearchSourceKind.web, ResearchSourceKind.paper},
    ResearchIntent.video => {ResearchSourceKind.video, ResearchSourceKind.image},
    ResearchIntent.paper => {ResearchSourceKind.paper},
    _ => {ResearchSourceKind.web},
  };
}

/// The method to preselect: the intent's own, or the closest one available.
ResearchMethod defaultMethod(ResearchIntent intent, {required bool ai, required bool web}) {
  final wanted = intent.method;
  if (wanted == ResearchMethod.web && !web) return ai ? ResearchMethod.offline : ResearchMethod.search;
  if (wanted == ResearchMethod.offline && !ai) return ResearchMethod.search;
  return wanted;
}

final _latin = RegExp(r'[A-Za-z]');
final _cjk = RegExp(r'[㐀-鿿]');
final _claim = RegExp(r'\d|竟|证明|表明|显著|导致|一倍|发现|必然|总是|从不|proves?|shows?|causes?|always|never');

/// The intent marked "recommended" for [text]: a node is explained; a short
/// selection explained; mostly Latin text translated; a number or claim
/// verified; a long passage interpreted.
ResearchIntent recommendIntent(String text, {required bool fromMap}) {
  final value = text.trim();
  if (fromMap) return ResearchIntent.explain;
  final latin = _latin.allMatches(value).length;
  final cjk = _cjk.allMatches(value).length;
  if (latin > cjk * 2 && value.length > 12) return ResearchIntent.translate;
  if (value.runes.length <= 10) return ResearchIntent.explain;
  if (_claim.hasMatch(value)) return ResearchIntent.verify;
  if (value.runes.length > 50) return ResearchIntent.interpret;
  return ResearchIntent.explain;
}

/// The term a question is about: a node's title, a short selection itself,
/// or the first quoted or Latin phrase of a longer one; else its opening
/// words. Never the whole passage.
String researchTerm(String text, {required bool fromMap}) {
  final value = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (fromMap || value.runes.length <= 16) return _cut(value, 24);
  final quoted = RegExp(r'[「“"《]([^」”"》]{2,24})[」”"》]').firstMatch(value);
  if (quoted != null) return quoted[1]!.trim();
  final phrase = RegExp(r"[A-Za-z][A-Za-z\-']+(?: [A-Za-z][A-Za-z\-']+){0,2}").firstMatch(value);
  if (phrase != null && _cjk.hasMatch(value)) return phrase[0]!;
  final clause = value.split(RegExp(r'[，。；：！？,.;:!?]')).firstWhere((p) => p.trim().isNotEmpty, orElse: () => value);
  return _cut(clause.trim(), 12);
}

String _cut(String value, int max) => value.runes.length <= max ? value : String.fromCharCodes(value.runes.take(max));

/// Search keywords to start from: the term, plus any Latin phrase the text
/// names (an English term next to Chinese text). The user edits them.
List<String> suggestKeywords(String text, {required bool fromMap}) {
  final term = researchTerm(text, fromMap: fromMap);
  final keywords = <String>[if (term.isNotEmpty) term];
  if (!fromMap && _cjk.hasMatch(text)) {
    for (final m in RegExp(r"[A-Za-z][A-Za-z\-']+(?: [A-Za-z][A-Za-z\-']+){0,3}").allMatches(text)) {
      final phrase = m[0]!.trim();
      if (phrase.length > 2 && !keywords.contains(phrase)) keywords.add(phrase);
      if (keywords.length >= 3) break;
    }
  }
  return keywords;
}
