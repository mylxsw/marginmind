import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

/// Transient source decoration, independent of saved annotations and undo.
class VocabularySourceFlash extends Notifier<VocabularyContext?> {
  Timer? _timer;
  @override
  VocabularyContext? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  void show(VocabularyContext source) {
    _timer?.cancel();
    state = source;
    _timer = Timer(MMMotion.flash, () => state = null);
  }
}

final vocabularySourceFlashProvider = NotifierProvider<VocabularySourceFlash, VocabularyContext?>(
  VocabularySourceFlash.new,
);
