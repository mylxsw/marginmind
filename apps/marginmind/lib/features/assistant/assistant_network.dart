import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../app/providers.dart';
import 'assistant_settings.dart';
import 'assistant_services.dart';

final assistantWebCacheProvider = Provider<ResearchDocumentCache?>((ref) => null);
final assistantArticleParserProvider = Provider<HtmlArticleParser>((ref) => WebKitArticleParser());

/// Built for the conversation's selected model, freshly for each request.
Future<AssistantNetwork?> assistantNetworkFor(Ref ref, String studySetId, Conversation conversation) async {
  if (!conversation.online) return null;
  final repository = ref.read(contentRepositoryProvider);
  if (repository is! ResearchSnapshotRepository) return null;
  final model = await ref.read(assistantServicesStoreProvider).resolve(conversation.model);
  final settings = ref.read(webSearchSettingsProvider);
  final secrets = ref.read(assistantSecretsProvider);
  final needsSearchService = !hasNativeWebSearch(model);
  final searchKey =
      needsSearchService && settings.backend != WebSearchBackend.none && settings.backend != WebSearchBackend.searxng
      ? await secrets.read(WebSearchSettingsController.account(settings.backend))
      : null;
  final account = needsSearchService && settings.backend == WebSearchBackend.cloudflare
      ? await secrets.read(WebSearchSettingsController.cloudflareAccount)
      : null;
  final parser = ref.read(assistantArticleParserProvider);
  final cache = ref.read(assistantWebCacheProvider);
  final key = await ref.read(assistantSecretsProvider).read(AssistantServicesStore.account(model.serviceId!));
  return productionAssistantNetwork(
    studySetId: studySetId,
    snapshots: repository as ResearchSnapshotRepository,
    parser: parser,
    model: model,
    key: key ?? '',
    searchSettings: settings,
    searchKey: searchKey ?? '',
    searchAccountId: account ?? '',
    cache: cache,
  );
}
