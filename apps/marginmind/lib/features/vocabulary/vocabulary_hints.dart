import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

/// Reader decoration preference; it never changes document annotations.
enum VocabularyHintMode { off, underline, gloss }

/// Global defaults with per-document suppression.
class VocabularyHints {
  VocabularyHints({
    this.mode = VocabularyHintMode.underline,
    this.lastMode = VocabularyHintMode.underline,
    this.showKnown = false,
    Set<String> hiddenDocuments = const {},
  }) : hiddenDocuments = Set.unmodifiable(hiddenDocuments);
  final VocabularyHintMode mode, lastMode;
  final bool showKnown;
  final Set<String> hiddenDocuments;

  /// Settings > Reading uses the same global default as the reader toggle.
  VocabularyHintMode get defaultMode => mode;
  VocabularyHintMode modeFor(String documentId) => hiddenDocuments.contains(documentId) ? VocabularyHintMode.off : mode;
}

final vocabularyHintProvider = NotifierProvider<VocabularyHintController, VocabularyHints>(
  VocabularyHintController.new,
);

/// Persists the four documented preferences; changes do not create undo entries.
class VocabularyHintController extends Notifier<VocabularyHints> {
  Future<void> _queue = Future.value();
  @override
  VocabularyHints build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    VocabularyHintMode mode(String key) {
      final value = prefs.get(key);
      return VocabularyHintMode.values.where((m) => m.name == value).firstOrNull ?? VocabularyHintMode.underline;
    }

    final last = mode('vocabulary.lastHintMode');
    final hidden = prefs.get('vocabulary.hiddenDocuments');
    return VocabularyHints(
      mode: mode('vocabulary.hintMode'),
      lastMode: last == VocabularyHintMode.off ? VocabularyHintMode.underline : last,
      showKnown: prefs.get('vocabulary.showKnown') == true,
      hiddenDocuments: hidden is List<String> ? hidden.toSet() : {},
    );
  }

  Future<void> _serial(Future<void> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> _write(Map<String, Object> values) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final before = {for (final key in values.keys) key: prefs.get(key)};
    Future<bool> put(String key, Object? value) => switch (value) {
      String v => prefs.setString(key, v),
      bool v => prefs.setBool(key, v),
      List<String> v => prefs.setStringList(key, v),
      _ => prefs.remove(key),
    };
    try {
      for (final entry in values.entries) {
        if (!await put(entry.key, entry.value)) throw StateError('Vocabulary preference write failed');
      }
    } catch (_) {
      // SharedPreferences updates its local cache before awaiting the platform.
      // Restore that cache and attempt to restore disk, preserving the first error.
      for (final entry in before.entries) {
        try {
          await put(entry.key, entry.value);
        } catch (_) {
          /* Best effort rollback. */
        }
      }
      rethrow;
    }
  }

  Future<void> _mode(VocabularyHintMode mode) async {
    final last = mode == VocabularyHintMode.off ? state.lastMode : mode;
    await _write({'vocabulary.lastHintMode': last.name, 'vocabulary.hintMode': mode.name});
    if (ref.mounted) {
      state = VocabularyHints(
        mode: mode,
        lastMode: last,
        showKnown: state.showKnown,
        hiddenDocuments: state.hiddenDocuments,
      );
    }
  }

  /// Change the global mode from the reader.
  Future<void> setMode(VocabularyHintMode mode) => _serial(() => _mode(mode));

  /// Settings > Reading: read the global default.
  VocabularyHintMode get defaultMode => state.defaultMode;

  /// Settings > Reading: write the global default, updating active readers too.
  Future<void> setDefaultMode(VocabularyHintMode mode) => setMode(mode);

  /// Switch off or resume the last non-off mode.
  Future<void> toggle() =>
      _serial(() => _mode(state.mode == VocabularyHintMode.off ? state.lastMode : VocabularyHintMode.off));

  /// Include mastered words; defaults to false.
  Future<void> setShowKnown(bool value) => _serial(() async {
    await _write({'vocabulary.showKnown': value});
    if (ref.mounted) {
      state = VocabularyHints(
        mode: state.mode,
        lastMode: state.lastMode,
        showKnown: value,
        hiddenDocuments: state.hiddenDocuments,
      );
    }
  });

  /// Hide decorations for a single document without changing the global default.
  Future<void> setDocumentHidden(String documentId, bool hidden) => _serial(() async {
    final documents = {...state.hiddenDocuments};
    if (hidden) {
      documents.add(documentId);
    } else {
      documents.remove(documentId);
    }
    await _write({'vocabulary.hiddenDocuments': documents.toList()..sort()});
    if (ref.mounted) {
      state = VocabularyHints(
        mode: state.mode,
        lastMode: state.lastMode,
        showKnown: state.showKnown,
        hiddenDocuments: documents,
      );
    }
  });
}
