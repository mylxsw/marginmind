import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:mm_core/mm_core.dart';

import 'providers.dart';
import 'runtime.dart';
import 'quick_tasks.dart';

/// Lookup results are independent of the vocabulary repository and its entities.
class WordSense {
  const WordSense({required this.pos, required this.meaning});
  final String pos, meaning;
}

class WordContext {
  const WordContext({required this.contextMeaning, required this.sentenceTranslation});
  final String contextMeaning, sentenceTranslation;

  factory WordContext.parse(String text) => _context(_object(text));
}

class WordLookupResult {
  WordLookupResult({
    required this.lemma,
    required this.ukPhonetic,
    required this.usPhonetic,
    required List<WordSense> senses,
    required this.context,
    required this.gloss,
    required List<String> forms,
  }) : senses = List.unmodifiable(senses),
       forms = List.unmodifiable(forms);
  final String lemma, ukPhonetic, usPhonetic, gloss;
  final List<WordSense> senses;
  final WordContext context;
  final List<String> forms;

  factory WordLookupResult.parse(String text) {
    final j = _object(text);
    final lemma = _string(j, 'lemma', 64);
    final phonetics = j['phonetics'] is Map<String, dynamic> ? j['phonetics'] as Map<String, dynamic> : const {};
    final rawSenses = j['senses'];
    final senses = <WordSense>[];
    if (rawSenses is List) {
      for (final sense in rawSenses.take(6)) {
        try {
          senses.add(_sense(sense));
        } on ResearchFailure {
          // One malformed sense must not discard the remaining dictionary data.
        }
      }
    }
    if (senses.isEmpty) throw const ResearchFailure(ResearchFailureKind.protocol);
    // Reserve a slot for the lemma, even if all sixteen supplied forms differ.
    final forms = <String>{lemma.toLowerCase()};
    final rawForms = j['forms'];
    if (rawForms is List) {
      for (final form in rawForms.take(16)) {
        if (form is String && form.trim().isNotEmpty && form.runes.length <= 64 && forms.length < 16) {
          forms.add(form.trim().toLowerCase());
        }
      }
    }
    return WordLookupResult(
      lemma: lemma,
      ukPhonetic: _optionalString(phonetics['uk'], 128),
      usPhonetic: _optionalString(phonetics['us'], 128),
      senses: senses,
      context: _context(j),
      gloss: _optionalString(j['gloss'], 8),
      forms: forms.toList(),
    );
  }
}

Map<String, dynamic> _object(String text) {
  if (utf8.encode(text).length > 65536) throw const ResearchFailure(ResearchFailureKind.protocol);
  // Find balanced objects without mistaking braces inside JSON strings for
  // delimiters. This also handles fenced output and short model preambles.
  var start = -1, depth = 0;
  var quoted = false, escaped = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (start < 0) {
      if (ch != '{') continue;
      start = i;
      depth = 1;
      continue;
    }
    if (quoted) {
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == '"') {
        quoted = false;
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == '{') {
      depth++;
    } else if (ch == '}' && --depth == 0) {
      try {
        final value = jsonDecode(text.substring(start, i + 1));
        if (value is Map<String, dynamic>) return value;
      } on FormatException {
        // A non-JSON brace pair in introductory prose is not the answer.
      }
      start = -1;
    }
  }
  throw const ResearchFailure(ResearchFailureKind.protocol);
}

String _optionalString(dynamic value, int max) =>
    value is String ? String.fromCharCodes(value.trim().runes.take(max)) : '';

String _string(Map<String, dynamic> j, String key, int max) {
  final value = j[key];
  if (value is! String || value.trim().isEmpty || value.runes.length > max) {
    throw const ResearchFailure(ResearchFailureKind.protocol);
  }
  return value.trim();
}

WordSense _sense(dynamic j) {
  if (j is! Map<String, dynamic>) throw const ResearchFailure(ResearchFailureKind.protocol);
  return WordSense(pos: _string(j, 'pos', 32), meaning: _string(j, 'meaning', 2000));
}

WordContext _context(Map<String, dynamic> j) => WordContext(
  contextMeaning: _string(j, 'contextMeaning', 2000),
  sentenceTranslation: _string(j, 'sentenceTranslation', 24000),
);

typedef _Key = (String, String, String, String, String);

/// Cached dictionary adapter. The executor owns routing, credentials and the
/// persisted lifecycle; this adapter never opens a model connection.
class WordLookup {
  WordLookup.tasks(this.execute, {this.timeout = const Duration(seconds: 90)});
  final QuickTaskExecutor execute;
  final Duration timeout;
  final _results = <_Key, WordLookupResult>{};
  final _contexts = <_Key, WordContext>{};
  final _aliases = <_Key, _Key>{};
  static const _cacheLimit = 128;

  /// [model] is retained for source compatibility; only the task route selects a model.
  /// [online] can further restrict the host network preference, never enable it.
  Future<WordLookupResult> lookup({
    required String term,
    required String sentence,
    String? sourceLanguage,
    required String targetLanguage,
    AssistantModel? model,
    required CancellationToken cancel,
    bool online = true,
    bool refresh = false,
  }) async {
    final key = _validate(term, sentence, sourceLanguage, targetLanguage, cancel);
    final cached = _results[_aliases[key] ?? key];
    if (!refresh && cached != null) return cached;
    final text = await _request(term, sentence, sourceLanguage, targetLanguage, online, cancel, contextOnly: false);
    cancel.check();
    final result = WordLookupResult.parse(text);
    final canonical = (_normalize(result.lemma), targetLanguage, key.$3, key.$4, key.$5);
    _put(_results, canonical, result);
    _put(_aliases, key, canonical);
    _put(_contexts, canonical, result.context);
    return result;
  }

  /// Existing entries retain their saved dictionary senses. Request only the
  /// meaning and translation for a new sentence; never overwrite the full result.
  Future<WordContext> lookupContext({
    required String lemma,
    required String sentence,
    String? sourceLanguage,
    required String targetLanguage,
    AssistantModel? model,
    required CancellationToken cancel,
    bool online = true,
  }) async {
    final key = _validate(lemma, sentence, sourceLanguage, targetLanguage, cancel);
    final canonical = _aliases[key] ?? key;
    final cached = _contexts[canonical];
    if (cached != null) return cached;
    final text = await _request(lemma, sentence, sourceLanguage, targetLanguage, online, cancel, contextOnly: true);
    cancel.check();
    final result = WordContext.parse(text);
    _put(_contexts, canonical, result);
    return result;
  }

  void clearCache() {
    _results.clear();
    _contexts.clear();
    _aliases.clear();
  }

  static String _normalize(String term) => term.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static void _put<T>(Map<_Key, T> cache, _Key key, T value) {
    cache.remove(key);
    cache[key] = value;
    if (cache.length > _cacheLimit) cache.remove(cache.keys.first);
  }

  _Key _validate(String term, String sentence, String? source, String target, CancellationToken cancel) {
    cancel.check();
    if (term.trim().isEmpty ||
        term.runes.length > 64 ||
        term.trim().split(RegExp(r'\s+')).length > 8 ||
        sentence.trim().isEmpty ||
        sentence.length > 24000 ||
        (source != null && TranslationLanguage.fromCode(source) == null) ||
        TranslationLanguage.fromCode(target) == null ||
        timeout <= Duration.zero) {
      throw const ResearchFailure(ResearchFailureKind.invalidRequest);
    }
    return (
      _normalize(term),
      target,
      sha256.convert(utf8.encode(sentence)).toString(),
      source ?? 'auto',
      quickPromptVersion,
    );
  }

  Future<String> _request(
    String term,
    String sentence,
    String? source,
    String target,
    bool online,
    CancellationToken cancel, {
    required bool contextOnly,
  }) async {
    final token = CancellationToken();
    var finished = false;
    unawaited(
      cancel.whenCancelled.then((_) {
        if (!finished) token.cancel();
      }),
    );
    try {
      return await token
          .bind(
            execute(TaskType.wordLookup, {
              'term': term,
              'sentence': sentence,
              'sourceLanguage': source,
              'targetLanguage': target,
              'contextOnly': contextOnly,
              'online': online,
            }, token),
          )
          .timeout(timeout);
    } on ConfigurationFailure {
      rethrow;
    } on TimeoutException {
      throw const ResearchFailure(ResearchFailureKind.timeout);
    } catch (error) {
      throw ResearchFailure(assistantFailureKind(error));
    } finally {
      finished = true;
      token.cancel();
    }
  }
}
