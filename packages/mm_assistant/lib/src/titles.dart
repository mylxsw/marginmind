import 'package:mm_core/mm_core.dart';

import 'quick_tasks.dart';

import 'models.dart';
import 'providers.dart';

String? assistantSelectionTitle(String question, List<ContextItem> contexts) {
  final selection = contexts
      .where(
        (c) =>
            c.kind == ContextKind.selection &&
            c.displayText.trim().isNotEmpty &&
            c.displayText.trim().runes.length <= 12,
      )
      .firstOrNull;
  final pronouns = RegExp('这个|这段|这里|他|她|它');
  if (selection == null || !pronouns.hasMatch(question)) return null;
  return question.replaceAll(pronouns, selection.displayText.trim());
}

String assistantTitlePlaceholder(String question, List<ContextItem> contexts) => String.fromCharCodes(
  (assistantSelectionTitle(question, contexts) ?? question).trim().replaceAll(RegExp(r'\s+'), ' ').runes.take(24),
);

/// Compatibility identity; title generation resolves its own quick task route.
@Deprecated('Resolve TaskType.titleGenerate through TaskModelResolver')
AssistantModel assistantTitleModel(AssistantModel current, List<AssistantModel> available) => current;

Future<String> generateAssistantTitle(QuickTaskExecutor execute, String question) async {
  final cancel = CancellationToken();
  try {
    return await execute(TaskType.titleGenerate, {'question': question}, cancel);
  } finally {
    cancel.cancel();
  }
}
