import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';
import 'assistant_settings.dart';
import 'task_run_store.dart';

final quickTaskRegistryProvider = Provider<TaskRegistry>((ref) => quickTaskRegistry());

/// Each invocation resolves its own function binding. Conversation overrides
/// and the legacy default model are deliberately absent from this boundary.
final quickTaskExecutorProvider = Provider.family<QuickTaskExecutor, String>((ref, studySetId) {
  final tasks = ref.watch(quickTaskRegistryProvider);
  return (type, input, cancel) async {
    cancel.check();
    final directory = ref.read(contentRepositoryProvider).resolveFile(studySetId, '');
    if (studySetId.isEmpty || !p.isAbsolute(directory)) {
      throw const ConfigurationFailure('persistentStudySetRequired');
    }
    final assembly = ref.read(persistentTaskAssemblyProvider((directory: directory, tasks: tasks)));
    final request = TaskRequest<String>(
      spec: quickTaskSpec(type),
      input: input,
      inputFingerprint: quickInputFingerprint(input),
    );
    final context = await assembly.freeze(
      request,
      runId: List.generate(16, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join(),
      inputRange: {
        'ids': ['input'],
      },
    );
    cancel.check();
    if ((input['online'] == false || !assistantOnlineDefault(ref, studySetId)) &&
        context.config.capabilities.identity.protocol != ModelProtocol.ollamaChat) {
      throw const ResearchFailure(ResearchFailureKind.network);
    }
    final handle = assembly.runtime.start(request, context);
    var finished = false;
    Future<void>? cancellation;
    unawaited(
      cancel.whenCancelled.then((_) {
        if (!finished) {
          cancellation ??= handle.cancel();
          // The foreground finally block awaits and reports cancellation errors.
          cancellation!.ignore();
        }
      }),
    );
    try {
      final result = await cancel
          .bind(handle.result)
          .timeout(type == TaskType.titleGenerate ? const Duration(seconds: 10) : const Duration(seconds: 90));
      cancel.check();
      if (result.status != RunStatus.completed || result.value == null) {
        throw const ResearchFailure(ResearchFailureKind.protocol);
      }
      return result.value!;
    } finally {
      finished = true;
      if (handle.status != RunStatus.completed &&
              handle.status != RunStatus.failed &&
              handle.status != RunStatus.partial ||
          cancellation != null) {
        await (cancellation ??= handle.cancel());
      }
    }
  };
});

final selectionTranslatorProvider = Provider.family<Future<ParagraphTranslator> Function(), String>((ref, studySetId) {
  final execute = ref.watch(quickTaskExecutorProvider(studySetId));
  return () async => TaskParagraphTranslator(execute);
});
