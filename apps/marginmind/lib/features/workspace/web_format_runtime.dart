import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';
import '../assistant/assistant_routing.dart';
import '../assistant/assistant_services.dart';
import '../assistant/assistant_settings.dart';
import '../assistant/task_run_store.dart';
import 'web_format_session.dart';

final webFormatRegistryProvider = Provider<TaskRegistry>((ref) {
  final registry = TaskRegistry();
  registerWebFormatting(registry);
  return registry;
});

/// Whether formatting can run, and on which model. Dispatch resolves again.
final webFormatRouteProvider = FutureProvider.autoDispose.family<RoutingRowState, ModelReference?>((ref, model) async {
  ref.watch(assistantServicesProvider);
  ref.watch(assistantKeysProvider);
  ref.watch(assistantCapabilityProfilesProvider);
  final resolver = ref.watch(assistantModelResolverProvider);
  return resolver.inspect(
    TaskRequest<String>(
      spec: webFormatSpec,
      input: const {},
      inputFingerprint: 'web-format-setup',
      modelOverride: model,
    ),
    await ref.watch(assistantRoutingProvider.future),
  );
});

final webFormatExecutorProvider = Provider.family<WebFormatExecutor, String>((ref, studySetId) {
  final tasks = ref.watch(webFormatRegistryProvider);
  return (input, model, onDraft, cancel) async {
    cancel.check();
    final directory = ref.read(contentRepositoryProvider).resolveFile(studySetId, '');
    if (studySetId.isEmpty || !p.isAbsolute(directory)) {
      throw const ConfigurationFailure('persistentStudySetRequired');
    }
    final assembly = ref.read(persistentTaskAssemblyProvider((directory: directory, tasks: tasks)));
    final request = TaskRequest<String>(
      spec: webFormatSpec,
      input: input,
      inputFingerprint: quickInputFingerprint(input),
      modelOverride: model,
      maxOutputTokens: webFormatOutputLimit(input['text'] as String),
      streamDrafts: true,
    );
    final context = await assembly.freeze(
      request,
      runId: newId(),
      inputRange: {
        'ids': [input['id']],
      },
    );
    cancel.check();
    final handle = assembly.runtime.start(request, context);
    return runWebFormatHandle(handle, onDraft, cancel);
  };
});
