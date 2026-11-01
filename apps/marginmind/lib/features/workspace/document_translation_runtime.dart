import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';
import '../assistant/assistant_routing.dart';
import '../assistant/assistant_services.dart';
import '../assistant/task_run_store.dart';

final documentTranslationRegistryProvider = Provider<TaskRegistry>((ref) {
  final registry = TaskRegistry();
  registerDocumentTranslation(registry);
  return registry;
});

typedef DocumentTranslationScope = ({String setId, String documentId, String language, ModelReference? model});
final documentTranslationRouteProvider = FutureProvider.autoDispose.family<RoutingRowState, ModelReference?>((
  ref,
  model,
) async {
  ref.watch(assistantServicesProvider);
  final routing = await ref.watch(assistantRoutingProvider.future);
  return ref
      .watch(assistantModelResolverProvider)
      .inspect(
        TaskRequest<Map<String, dynamic>>(
          spec: documentTranslationSpec,
          input: const {},
          inputFingerprint: 'translation-setup',
          modelOverride: model,
        ),
        routing,
      );
});

final documentTranslationAssemblyProvider = Provider.family<PersistentTaskAssembly, String>((ref, directory) {
  return PersistentTaskAssembly(
    studySetDirectory: directory,
    tasks: ref.watch(documentTranslationRegistryProvider),
    services: ref.watch(assistantServicesStoreProvider),
    routing: ref.watch(assistantRoutingStoreProvider),
    profiles: ref.watch(assistantCapabilityProfilesProvider),
    knowledge: VersionedKnowledgeRegistry([documentTranslationKnowledge]),
  );
});

String documentTranslationEpochKey(String setId, String documentId, String language) =>
    'translation.runtime-epoch.${jsonEncode([setId, documentId, language])}';

/// Real catalog/secret/resolver/RunStore assembly; no direct-model fallback.
final documentTranslatorFactoryProvider =
    Provider<Future<ParagraphTranslator> Function(DocumentTranslationScope, List<TranslationParagraph>)>((ref) {
      return (scope, paragraphs) async {
        final directory = ref.read(contentRepositoryProvider).resolveFile(scope.setId, '');
        if (scope.setId.isEmpty || !p.isAbsolute(directory)) {
          throw const ConfigurationFailure('persistentStudySetRequired');
        }
        final assembly = ref.read(documentTranslationAssemblyProvider(directory));
        final epoch =
            ref
                .read(sharedPreferencesProvider)
                .getInt(documentTranslationEpochKey(scope.setId, scope.documentId, scope.language)) ??
            0;
        return RuntimeDocumentTranslator(
          runtime: assembly.runtime,
          store: assembly.runs,
          reader: assembly.runs,
          freeze: (request, id, range) =>
              assembly.freeze(request, runId: id, inputRange: range, knowledgeVersions: {'translation.document': '1'}),
          scopeId:
              'translation-scope-${sha256.convert(utf8.encode(jsonEncode([scope.documentId, scope.language, epoch, paragraphs.map((p) => p.fingerprint).toList()])))}',
          documentId: scope.documentId,
          language: scope.language,
          inputIds: paragraphs.map((p) => p.fingerprint).toList(),
          nextId: newId,
          modelOverride: scope.model,
        );
      };
    });
