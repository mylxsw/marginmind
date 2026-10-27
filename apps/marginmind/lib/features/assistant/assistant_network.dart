import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../app/providers.dart';
import 'assistant_settings.dart';

final assistantWebCacheProvider = Provider<ResearchDocumentCache?>((ref) => null);
final assistantArticleParserProvider = Provider<HtmlArticleParser>((ref) => WebKitArticleParser());

/// Built for the conversation's selected model, freshly for each request.
Future<AssistantNetwork?> assistantNetworkFor(Ref ref, String studySetId, Conversation conversation) async {
  if (!conversation.online) return null;
  final repository = ref.read(contentRepositoryProvider);
  if (repository is! ResearchSnapshotRepository) return null;
  final settings = ref.read(assistantSettingsProvider);
  final parser = ref.read(assistantArticleParserProvider);
  final cache = ref.read(assistantWebCacheProvider);
  final key = await ref
      .read(assistantSecretsProvider)
      .read(AssistantSettingsController.account(conversation.model.provider));
  return productionAssistantNetwork(
    studySetId: studySetId,
    snapshots: repository as ResearchSnapshotRepository,
    parser: parser,
    model: conversation.model,
    key: key ?? '',
    searxngEndpoint: settings.searxngEndpoint,
    cache: cache,
  );
}
