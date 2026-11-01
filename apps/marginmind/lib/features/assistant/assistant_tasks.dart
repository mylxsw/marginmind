import 'dart:async';
import 'dart:math';

import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:path/path.dart' as p;

import 'assistant_routing.dart';
import 'assistant_services.dart';
import 'task_run_store.dart';
import 'quick_tasks.dart';
import '../../settings/app_settings.dart';
import 'assistant_reader.dart' show assistantRootId;

String _runId() => List.generate(16, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join();

/// Production domain factory. Each run owns a registry/bindings; no legacy
/// client or conversation model is used as a fallback when routing rejects it.
AssistantTaskOwner createPersistentAssistantRun({
  required Ref ref,
  required String directory,
  required sdk.AgentState state,
  required Conversation conversation,
  required Message question,
  required StudySetReader reader,
  required List<Document> documents,
  required String mapId,
  required int revision,
  required Map<String, String?> parents,
  AssistantNetwork? network,
  Future<List<sdk.ImagePart>> Function(List<ContextItem>)? images,
  Future<AssistantNetwork?> Function(AssistantModel)? networkFactory,
}) {
  if (!p.isAbsolute(directory)) throw const ConfigurationFailure('persistentStudySetRequired');
  final spec = assistantSpecFor(question.skill, question.contexts);
  final registry = TaskRegistry();
  final assembly = PersistentTaskAssembly(
    studySetDirectory: directory,
    tasks: registry,
    services: ref.read(assistantServicesStoreProvider),
    routing: ref.read(assistantRoutingStoreProvider),
    profiles: ref.read(assistantCapabilityProfilesProvider),
    knowledge: assistantTaskKnowledgeRegistry(),
  );
  late AssistantTaskOwner owner;
  owner = AssistantTaskOwner(
    conversationState: state,
    reader: reader,
    scope: scopeFromContexts(conversation.studySetId, question.contexts, documentIds: documents.map((d) => d.id)),
    requestId: question.requestId,
    mapId: mapId,
    baseRevision: revision,
    parents: parents,
    online: conversation.online,
    network: network,
    primaryDocumentId: question.contexts.map((c) => c.documentId).whereType<String>().firstOrNull,
    execute: (text) async {
      if ((await images?.call(question.contexts))?.isNotEmpty == true) {
        throw const ConfigurationFailure('multimodalRuntimeInputRequired');
      }
      if (question.skill == 'translate') {
        final explicit = question.contexts.where((c) => !c.auto).toList();
        final selected = explicit.isEmpty ? question.contexts : explicit;
        if (selected.isEmpty ||
            selected.any(
              (c) => c.kind == ContextKind.document || c.kind == ContextKind.map || c.kind == ContextKind.branch,
            )) {
          throw const ConfigurationFailure('translationSelectionRequired');
        }
        final units = await _summaryUnits(
          owner,
          TaskType.documentSummarize,
          conversation,
          Message(
            id: question.id,
            requestId: question.requestId,
            role: MessageRole.user,
            text: text,
            contexts: selected,
          ),
          documents,
        );
        final source = units
            .map((unit) => unit.text.replaceFirst(RegExp(r'^\[(?:page|source):[^\]]+\] '), ''))
            .join('\n\n');
        if (source.length > 24000) throw const ConfigurationFailure('translationSelectionTooLarge');
        final direction = ref.read(settingsProvider).selectionTranslationDirection;
        final value = await ref.read(quickTaskExecutorProvider(conversation.studySetId))(TaskType.selectionTranslate, {
          'text': source,
          'targetLanguage': direction.targetLanguage(source),
          'sourceLanguage': switch (direction) {
            SelectionTranslationDirection.automatic => null,
            SelectionTranslationDirection.englishToChinese => 'en',
            SelectionTranslationDirection.chineseToEnglish => 'zh',
          },
          'maxOutputTokens': 16384,
          'online': conversation.online,
        }, owner.cancel);
        return RunResult<String>(
          runId: question.requestId,
          status: RunStatus.completed,
          value: value,
          validation: ValidationReport(),
        );
      }

      final input = <String, dynamic>{
        'question': text,
        if (question.summaryMessageIds != null) 'summaryMessageIds': question.summaryMessageIds,
        'contexts': [for (final c in question.contexts) c.toJson()],
        'documents': [
          for (final d in documents) {'id': d.id, 'title': d.title, 'pages': d.pageCount},
        ],
        'parents': parents,
        'online': conversation.online,
        'toolsEnabled': conversation.model.supportsTools,
        'reviewOnly': spec.type == TaskType.reviewCards,
      };
      final request = TaskRequest<String>(
        spec: spec,
        input: input,
        inputFingerprint: quickInputFingerprint(input),
        modelOverride:
            question.taskModel ??
            (spec.type == TaskType.assistantChat
                ? conversationRoutingOverride(conversation.toJson(), TaskType.assistantChat)
                : null),
      );
      final context = await assembly.freeze(
        request,
        runId: _runId(),
        inputRange: {
          'studySetId': conversation.studySetId,
          'conversationId': conversation.id,
          'requestId': question.requestId,
          if (question.summaryMessageIds != null) 'messageIds': question.summaryMessageIds,
          'contexts': [for (final c in question.contexts) c.toJson()],
        },
      );
      owner.cancel.check();
      if (spec.type == TaskType.research && conversation.online) {
        owner.network = network ?? await networkFactory?.call((await assembly.loadModel(context)).model);
      }
      state.metadata['assistant.taskRun.v1'] = encodeRunContext(context);
      final activity = ref.read(assistantTaskActivityProvider(conversation.studySetId).notifier);
      Future<RunResult<String>> dispatch(TaskRequest<String> request, RunContext stageContext) => _dispatch(
        assembly,
        owner,
        request,
        stageContext,
        onStatus: (status) => activity.update(stageContext, spec.type, status),
      );

      if (spec.type == TaskType.conversationSummarize || spec.type == TaskType.documentSummarize) {
        final units = await _summaryUnits(owner, spec.type, conversation, question, documents);
        final capacity = context.config.capabilities.contextTokens;
        final requestCharacters = ((capacity ?? 60000) - (context.config.policy.maxOutputTokens ?? 8192) - 12000).clamp(
          4096,
          24000,
        );
        final summary = await summarizeAssistantUnits(
          units: units,
          requestCharacters: requestCharacters,
          cancel: owner.cancel,
          execute: (group, stage) => dispatch(
            TaskRequest<String>(
              spec: spec,
              input: {
                'question': text,
                'units': [for (final u in group) u.toJson()],
              },
              inputFingerprint: quickInputFingerprint({
                'units': [for (final u in group) u.toJson()],
              }),
            ),
            stage == 0 ? context : context.child('${context.runId}-$stage'),
          ),
        );
        state.metadata['assistant.summaryCoverage.v1'] = summary.coveredIds;
        return RunResult<String>(
          runId: context.runId,
          status: RunStatus.completed,
          validation: ValidationReport(),
          value: summary.text,
        );
      }
      final result = await dispatch(request, context);
      if (spec.type == TaskType.research && result.value != null) {
        String rendered;
        try {
          rendered = AssistantResearch.parse(result.value!).render(chinese: RegExp(r'[\u4e00-\u9fff]').hasMatch(text));
        } catch (_) {
          return result;
        }
        return RunResult<String>(
          runId: result.runId,
          status: result.status,
          value: rendered,
          validation: result.validation,
          failureCode: result.failureCode,
          usage: result.usage,
        );
      }
      return result;
    },
  );
  registerAssistantTasks(registry, owner);
  return owner;
}

Future<RunResult<String>> _dispatch(
  PersistentTaskAssembly assembly,
  AssistantTaskOwner owner,
  TaskRequest<String> request,
  RunContext context, {
  void Function(RunStatus)? onStatus,
}) async {
  owner.cancel.check();
  final handle = assembly.runtime.start(request, context);
  final subscription = handle.events.listen((event) => onStatus?.call(event.status));
  owner.permissions.onWaitingChanged = (waiting) => onStatus?.call(waiting ? RunStatus.awaitingUser : handle.status);
  var finished = false;
  Future<void>? cancelling;
  unawaited(
    owner.cancel.whenCancelled.then((_) {
      if (!finished) {
        cancelling ??= handle.cancel();
        cancelling!.ignore();
      }
    }),
  );
  try {
    return await owner.cancel.bind(handle.result);
  } finally {
    finished = true;
    owner.permissions.onWaitingChanged = null;
    await subscription.cancel();
    if (cancelling != null) await cancelling;
    owner.synchronize();
  }
}

Future<List<SummaryUnit>> _summaryUnits(
  AssistantTaskOwner owner,
  TaskType type,
  Conversation conversation,
  Message question,
  List<Document> documents,
) async {
  if (type == TaskType.conversationSummarize) {
    // Freeze only the active branch before this question. Replaced branches are
    // archived separately and are never included in this range.
    final eligible = conversation.messages
        .takeWhile((m) => m.id != question.id)
        .where((m) => m.status == MessageStatus.done && m.text.trim().isNotEmpty)
        .toList();
    final ids = question.summaryMessageIds?.toSet();
    if (ids == null || ids.isEmpty || !eligible.map((m) => m.id).toSet().containsAll(ids)) {
      throw const ConfigurationFailure('summaryRangeRequired');
    }
    return [
      for (final message in eligible.where((m) => ids.contains(m.id)))
        if (message.status == MessageStatus.done && message.text.trim().isNotEmpty)
          SummaryUnit(message.id, '${message.role.name}: ${message.text}'),
    ];
  }
  final units = <SummaryUnit>[];
  final pages = <String>{};
  for (final context in question.contexts) {
    owner.cancel.check();
    if (context.kind == ContextKind.document && context.documentId != null) {
      final doc = documents.where((d) => d.id == context.documentId).firstOrNull;
      if (doc == null) throw const ConfigurationFailure('summaryDocumentMissing');
      for (var page = 1; page <= doc.pageCount; page++) {
        final read = await owner.reader.readPages(doc.id, page, page, owner.scope, owner.cancel);
        if (read.length != 1 ||
            read.single.documentId != doc.id ||
            read.single.page != page ||
            read.single.text.trim().isEmpty) {
          throw const ConfigurationFailure('unreadSummaryRange');
        }
        if (pages.add('${doc.id}:$page')) {
          final marker = owner.citations.page(read.single);
          units.add(SummaryUnit('${doc.id}:$page', '$marker ${read.single.text}'));
        }
      }
    } else if (context.kind == ContextKind.page && context.documentId != null && context.page != null) {
      final read = await owner.reader.readPages(
        context.documentId!,
        context.page!,
        context.page!,
        owner.scope,
        owner.cancel,
      );
      if (read.length != 1 ||
          read.single.documentId != context.documentId ||
          read.single.page != context.page ||
          read.single.text.trim().isEmpty) {
        throw const ConfigurationFailure('unreadSummaryRange');
      }
      if (pages.add('${context.documentId}:${context.page}')) {
        units.add(SummaryUnit(context.id, '${owner.citations.page(read.single)} ${read.single.text}'));
      }
    } else if (context.kind == ContextKind.selection) {
      final read = await owner.reader.readSelection(context.id, owner.scope, owner.cancel);
      if (read.isEmpty || read.any((page) => page.documentId != context.documentId || page.text.trim().isEmpty)) {
        throw const ConfigurationFailure('unreadSummaryRange');
      }
      for (final page in read) {
        units.add(SummaryUnit('${context.id}:${page.page}', '${owner.citations.page(page)} ${page.text}'));
      }
    } else if (context.mapId != null && (context.kind == ContextKind.map || context.nodeId != null)) {
      final nodes = await owner.reader.readBranch(
        context.mapId!,
        context.nodeId ?? assistantRootId,
        owner.scope,
        owner.cancel,
      );
      if (nodes.isEmpty) throw const ConfigurationFailure('unreadSummaryRange');
      for (final node in nodes) {
        if (pages.add('node:${context.mapId}:${node.id}')) {
          units.add(SummaryUnit('node:${context.mapId}:${node.id}', '${node.title}\n${node.body}'));
        }
      }
    } else {
      throw const ConfigurationFailure('unreadSummaryRange');
    }
  }
  return units;
}

class AssistantTaskActivity {
  const AssistantTaskActivity(this.context, this.type, this.status);
  final RunContext context;
  final TaskType type;
  final RunStatus status;
}

final assistantTaskActivityProvider =
    NotifierProvider.family<AssistantTaskActivityController, AssistantTaskActivity?, String>(
      AssistantTaskActivityController.new,
    );

class AssistantTaskActivityController extends Notifier<AssistantTaskActivity?> {
  AssistantTaskActivityController(this.studySetId);
  final String studySetId;
  @override
  AssistantTaskActivity? build() => null;
  void update(RunContext context, TaskType type, RunStatus status) =>
      state = AssistantTaskActivity(context, type, status);
}
