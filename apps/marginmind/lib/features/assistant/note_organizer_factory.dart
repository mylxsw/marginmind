import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';

import 'assistant_services.dart';
import 'assistant_settings.dart';

/// Uses the same selected service and Keychain account as the assistant.
/// Create after the sending disclosure is accepted; close when the session ends.
Future<ModelNoteOrganizer> createModelNoteOrganizer({
  required AssistantServicesStore services,
  required SecretStore secrets,
  ResearchBudget budget = const ResearchBudget(),
  void Function(NoteProgress)? onProgress,
  void Function(NoteSchemaFailure)? onFallback,
}) async {
  budget.validate();
  final model = (await services.load()).configuration;
  if (model == null) throw const ResearchFailure(ResearchFailureKind.invalidRequest);
  final key = await assistantModelKey(secrets, model);
  if (model.provider != AssistantProvider.ollama && (key == null || key.isEmpty)) {
    throw const ResearchFailure(ResearchFailureKind.authentication);
  }
  final connection = connectAssistant(model, key ?? '', budget: budget);
  return ModelNoteOrganizer(
    client: connection.client,
    model: model.model,
    budget: budget,
    onProgress: onProgress,
    onFallback: onFallback,
    closeConnection: connection.close,
  );
}
