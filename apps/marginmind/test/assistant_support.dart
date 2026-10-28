import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/app_commands.dart';
import 'package:marginmind/features/assistant/assistant_controller.dart';
import 'package:marginmind/features/assistant/assistant_reader.dart';
import 'package:marginmind/features/assistant/widgets/assistant_panel.dart';
import 'package:marginmind/features/assistant/assistant_scope.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/assistant/assistant_writes.dart';
import 'package:marginmind/features/assistant/widgets/assistant_overlays.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../../packages/mm_assistant/test/support.dart';
import 'helpers.dart';

export '../../../packages/mm_assistant/test/support.dart' show ScriptClient, StreamClient, answer, call;

class FakeSecrets implements SecretStore {
  final values = <String, String>{};
  final reads = <String>[];
  @override
  Future<String?> read(String name) async {
    reads.add(name);
    return values[name];
  }

  @override
  Future<void> write(String name, String value) async => values[name] = value;
  @override
  Future<void> delete(String name) async => values.remove(name);
}

class UnreadableAfterWriteSecrets extends FakeSecrets {
  @override
  Future<String?> read(String account) async {
    if (account != 'anthropic' && values.containsKey(account)) {
      throw const ResearchFailure(ResearchFailureKind.authentication, 'secret_store');
    }
    return super.read(account);
  }
}

/// A model catalog without network: every service answers with [status]
/// and lists [models]; probing marks tools as supported.
class FakeCatalog extends ServiceCatalog {
  FakeCatalog({this.status = ConnectionStatus.ok, List<ServiceModel>? models, this.listFailure})
    : models =
          models ??
          const [ServiceModel(id: 'claude-sonnet-5-5', name: 'Claude Sonnet'), ServiceModel(id: 'claude-haiku-5-5')];
  ConnectionStatus status;
  List<ServiceModel> models;
  ResearchFailure? listFailure;
  final checked = <(String, String)>[];
  final listed = <(String, String)>[];
  int probes = 0;
  @override
  Future<ConnectionStatus> check(AssistantService service, String key, {CancellationToken? cancellation}) async {
    checked.add((service.endpoint, key));
    return status;
  }

  @override
  Future<List<ServiceModel>> list(AssistantService service, String key, {CancellationToken? cancellation}) async {
    listed.add((service.endpoint, key));
    if (listFailure != null) throw listFailure!;
    return models;
  }

  @override
  Future<ServiceModel> probe(
    AssistantService service,
    ServiceModel model,
    String key, {
    CancellationToken? cancellation,
  }) async {
    probes++;
    return model.copyWith(tools: ToolCapability.supported);
  }
}

class FakeLinks extends ExternalLinks {
  final opened = <Uri>[];
  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    return true;
  }
}

/// An executor that records what it applied and throws when told to.
class RecordingExecutor extends MemoryMapEditExecutor {
  RecordingExecutor() : super(studySetId: 'demo-1', mapId: MindMap.defaultId);
  bool fail = false;
  StudySetContent Function()? content;
  @override
  Future<MapEditReceipt> apply(MapEditProposal p, Set<String> selectedIds) async {
    if (fail) throw const ResearchFailure(ResearchFailureKind.unavailable);
    if (content != null) parents = mapParents(content!(), mapId);
    return super.apply(p, selectedIds);
  }
}

typedef AssistantApp = ({
  ProviderContainer container,
  WorkspaceController workspace,
  MemoryConversationArchive archive,
  FakeSecrets secrets,
  FakeLinks links,
  RecordingExecutor executor,
  MemoryNoteSaver notes,
  InMemoryStudySetContentRepository repository,
});

/// The app with demo-1 open and an assistant whose model answers from
/// [client]. Without [key] the assistant is not configured. With
/// [realWrites] proposals go through the workspace, so undo reaches them.
Future<AssistantApp> openAssistantApp(
  WidgetTester tester, {
  sdk.LLMClient? client,
  bool key = true,
  bool realFactory = false,
  Size size = const Size(1400, 900),
  Map<String, Object> prefs = const {},
  List<Override> overrides = const [],
  FakeCatalog? catalog,
  FakeSecrets? secretStore,
  MemoryConversationArchive? archive,
  bool realWrites = false,
}) async {
  final repo = InMemoryStudySetContentRepository({'demo-1': demoContent()});
  final store = archive ?? MemoryConversationArchive();
  final secrets = secretStore ?? FakeSecrets();
  if (key) secrets.values['anthropic'] = 'test-key';
  final links = FakeLinks();
  final executor = RecordingExecutor();
  final notes = MemoryNoteSaver();
  final llm = client ?? ScriptClient([answer('好的')]);
  final container = await pumpApp(
    tester,
    size: size,
    prefs: {'settings.language': 'zh', ...prefs},
    content: repo,
    overrides: [
      assistantSecretsProvider.overrideWithValue(secrets),
      assistantArchiveProvider.overrideWith((ref, id) => store.archive),
      if (!realWrites) assistantMapEditExecutorProvider.overrideWith((ref, id) => executor),
      if (!realWrites) assistantNoteSaverProvider.overrideWith((ref, id) => notes),
      assistantPageTextProvider.overrideWithValue((path, page) async => '第 $page 页的正文'),
      serviceCatalogProvider.overrideWithValue(catalog ?? FakeCatalog()),
      assistantLinksProvider.overrideWithValue(links),
      if (!realFactory)
        assistantDependenciesForProvider.overrideWith((ref, id) {
          return AssistantDependencies(
            studySetId: id,
            model: unconfiguredAssistantModel,
            defaultModel: () => ref.read(assistantDefaultModelProvider),
            storage: store,
            executor: realWrites ? ref.watch(assistantMapEditExecutorProvider(id)) : executor,
            notes: realWrites ? ref.watch(assistantNoteSaverProvider(id)) : notes,
            online: assistantOnlineDefault(ref, id),
            runFactory: (state, conversation, question) async {
              final workspace = ref.read(workspaceProvider(id).notifier);
              final mapId = ref.read(workspaceProvider(id)).activeMapId;
              if (await secrets.read('anthropic') == null) {
                throw const ResearchFailure(ResearchFailureKind.authentication);
              }
              return createAssistantRun(
                client: llm,
                model: conversation.model.model,
                state: state,
                requestId: question.requestId,
                reader: WorkspaceReader(
                  content: () => workspace.content,
                  contexts: question.contexts,
                  filePath: workspace.filePath,
                  pageText: (path, page) async => '第 $page 页的正文',
                ),
                scope: scopeFromContexts(
                  id,
                  question.contexts,
                  documentIds: workspace.content.documents.map((document) => document.id),
                ),
                mapId: mapId,
                baseRevision: realWrites ? assistantMapRevision(workspace.content, mapId) : executor.revision,
                parents: mapParents(workspace.content, mapId),
                primaryDocumentId: question.contexts.map((c) => c.documentId).whereType<String>().firstOrNull,
                online: conversation.online,
                skill: question.skill,
              );
            },
          );
        }),
      ...overrides,
    ],
  );
  container.read(navigationProvider.notifier).openStudySet('demo-1');
  await tester.pumpAndSettle();
  final workspace = container.read(workspaceProvider('demo-1').notifier);
  executor.content = () => workspace.content;
  return (
    container: container,
    workspace: workspace,
    archive: store,
    secrets: secrets,
    links: links,
    executor: executor,
    notes: notes,
    repository: repo,
  );
}

/// Lets an answer stream in and its writes finish, without waiting on
/// endless animations (cursor, spinners).
Future<void> pumpFor(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    // The agent SDK awaits real asynchronous work between events.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 30));
  }
}

/// Opens history using the visible assistant controls.
Future<void> showAssistantHistory(WidgetTester tester) async {
  if (find.byType(AssistantPanel).evaluate().isEmpty) {
    await tester.tap(find.byKey(const ValueKey('toolbar-assistant')));
    await pumpFor(tester, 20);
  }
  if (find.byKey(const ValueKey('assistant-history')).evaluate().isEmpty) {
    await tester.tap(find.byKey(const ValueKey('assistant-history-button')));
    await pumpFor(tester, 20);
  }
}

Future<void> openAssistantConversation(WidgetTester tester, String id) async {
  await showAssistantHistory(tester);
  final row = find.byKey(ValueKey('history-$id'));
  await tester.ensureVisible(row);
  await tester.tap(row);
  await pumpFor(tester, 20);
}

/// Reaches model settings through the app's shared Settings command.
Future<void> openAssistantModelSettings(WidgetTester tester) async {
  final shortcut = AppShortcuts.settings;
  if (shortcut.meta) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  if (shortcut.control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(shortcut.trigger);
  if (shortcut.control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  if (shortcut.meta) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('settings-tab-models')));
  await tester.pumpAndSettle();
}

/// The scoped assistant controller of the open window.
AssistantController assistantOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(AssistantPanel))).read(assistantControllerProvider.notifier);

Conversation conversationOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(AssistantPanel))).read(assistantControllerProvider);
