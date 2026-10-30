import 'vocabulary.dart';
import 'words.dart';

/// Half-open UTF-16 offsets into the original paragraph, suitable for TextAnchor.
typedef VocabularyMatch = ({int start, int end, String entryId});

final _tokens = RegExp(r"[\p{L}\p{M}\p{N}]+(?:['’][\p{L}\p{M}\p{N}]+)*", unicode: true);
final _whitespace = RegExp(r'^\s+$');

/// Immutable first-token index. At each position the longest non-overlapping
/// candidate wins; identical spans are ordered by entry ID. Work is proportional
/// to text plus candidates sharing a first token, rather than all entries.
class VocabularyMatcher {
  VocabularyMatcher(Iterable<VocabularyEntry> entries, {bool showKnown = false}) {
    for (final entry in entries) {
      if (!showKnown && entry.status == VocabularyStatus.known) continue;
      for (final form in entry.forms) {
        if (vocabularyCjk.hasMatch(form)) {
          final first = form.runes.first;
          (_cjk[first] ??= []).add((form, entry.id));
        } else {
          final parts = _tokens.allMatches(form).map((m) => m.group(0)!).toList();
          if (parts.isEmpty || parts.join(' ') != form) continue;
          (_index[parts.first] ??= []).add((parts, entry.id));
        }
      }
    }
  }
  final _index = <String, List<(List<String>, String)>>{};
  final _cjk = <int, List<(String, String)>>{};

  /// Match without normalizing the paragraph, preserving offsets even when case
  /// conversion changes string length. Phrase gaps must contain only whitespace.
  List<VocabularyMatch> match(String text) {
    final matches = <VocabularyMatch>[];
    final tokens = _tokens.allMatches(text).toList();
    for (var i = 0; i < tokens.length; i++) {
      final first = tokens[i];
      for (final (parts, id) in _index[first.group(0)!.toLowerCase()] ?? const <(List<String>, String)>[]) {
        if (i + parts.length > tokens.length) continue;
        var valid = true;
        for (var j = 1; j < parts.length; j++) {
          if (tokens[i + j].group(0)!.toLowerCase() != parts[j] ||
              !_whitespace.hasMatch(text.substring(tokens[i + j - 1].end, tokens[i + j].start))) {
            valid = false;
            break;
          }
        }
        if (valid) {
          matches.add((start: first.start, end: tokens[i + parts.length - 1].end, entryId: id));
        }
      }
    }
    var offset = 0;
    for (final rune in text.runes) {
      for (final (form, id)
          in _cjk[String.fromCharCode(rune).toLowerCase().runes.first] ?? const <(String, String)>[]) {
        if (offset + form.length <= text.length && text.substring(offset, offset + form.length).toLowerCase() == form) {
          matches.add((start: offset, end: offset + form.length, entryId: id));
        }
      }
      offset += rune > 0xffff ? 2 : 1;
    }
    matches.sort((a, b) {
      final start = a.start.compareTo(b.start);
      if (start != 0) return start;
      final length = b.end.compareTo(a.end);
      return length != 0 ? length : a.entryId.compareTo(b.entryId);
    });
    var end = 0;
    return List.unmodifiable(
      matches.where((m) {
        if (m.start < end) return false;
        end = m.end;
        return true;
      }),
    );
  }
}

/// Bounded LRU cache. Callers increment version for every committed vocabulary
/// change; full text in the key prevents paragraph fingerprint collisions.
class VocabularyMatchCache {
  VocabularyMatchCache({this.capacity = 128}) {
    if (capacity < 1) throw ArgumentError.value(capacity, 'capacity');
  }
  final int capacity;
  final _cache = <(String, int, bool), List<VocabularyMatch>>{};
  (int, bool)? _indexed;
  VocabularyMatcher? _matcher;
  List<VocabularyMatch> match(
    String text, {
    required int version,
    required Iterable<VocabularyEntry> entries,
    bool showKnown = false,
  }) {
    final key = (text, version, showKnown);
    if (_indexed != (version, showKnown)) {
      _matcher = VocabularyMatcher(entries, showKnown: showKnown);
      _indexed = (version, showKnown);
    }
    final result = _cache.remove(key) ?? _matcher!.match(text);
    _cache[key] = result;
    if (_cache.length > capacity) _cache.remove(_cache.keys.first);
    return result;
  }

  /// Release cached paragraph text when the reader closes.
  void clear() {
    _cache.clear();
    _matcher = null;
    _indexed = null;
  }
}
