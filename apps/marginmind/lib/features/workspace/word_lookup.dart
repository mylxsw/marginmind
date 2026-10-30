import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';

import '../assistant/assistant_settings.dart';

/// Shares selection translation's default model, online preference and secret
/// resolution. Callers pass the current model and assistantOnlineDefault for the
/// study set to lookup/lookupContext; no document metadata enters the request.
final wordLookupProvider = Provider<WordLookup>((ref) {
  final secrets = ref.watch(assistantSecretsProvider);
  // A changed model or credential starts a new in-memory cache.
  ref.watch(assistantDefaultModelProvider);
  ref.watch(assistantKeysProvider);
  return WordLookup(
    connect: (model) async {
      final key = await assistantModelKey(secrets, model);
      if (model.provider != AssistantProvider.ollama && (key == null || key.isEmpty)) {
        throw const ResearchFailure(ResearchFailureKind.authentication);
      }
      return connectAssistant(model, key ?? '');
    },
  );
});
