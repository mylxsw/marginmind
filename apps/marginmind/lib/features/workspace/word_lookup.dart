import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';

import '../assistant/quick_tasks.dart';
import '../assistant/assistant_settings.dart';
import '../assistant/assistant_routing.dart';

/// Study-set scoped caches preserve existing saved vocabulary. Only explicit
/// requests enter the runtime; settings changes never regenerate saved entries.
final wordLookupProvider = Provider.family<WordLookup, String>((ref, studySetId) {
  ref.watch(assistantKeysProvider);
  ref.watch(assistantRoutingProvider);
  return WordLookup.tasks(ref.watch(quickTaskExecutorProvider(studySetId)));
});
