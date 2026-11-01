import 'dart:async';
import 'dart:math';

import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:path/path.dart' as p;

import 'assistant_routing.dart';
import 'assistant_task_session.dart';
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
  Future<AssistantNetwork?> Function(AssistantModel, SearchProvider)? networkFactory,
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
  final archivedRecord = (state.metadata['assistant.taskRecords.v1'] as Map?)?[question.requestId] as Map?;
  final pinnedDocuments = archivedRecord == null
      ? documents.map((d) => d.id)
      : ((archivedRecord['input'] as Map)['documents'] as List).map((d) => d['id'] as String);
  late AssistantTaskOwner owner;
  owner = AssistantTaskOwner(
    conversationState: state,
    reader: reader,
    scope: scopeFromContexts(conversation.studySetId, question.contexts, documentIds: pinnedDocuments),
    requestId: question.requestId,
    mapId: archivedRecord == null
        ? mapId
        : (decodeRunContext(Map<String, dynamic>.from(archivedRecord['context'])).inputRange['mapId'] as String),
    baseRevision: archivedRecord == null
        ? revision
        : (decodeRunContext(Map<String, dynamic>.from(archivedRecord['context'])).inputRange['baseRevision'] as int),
    parents: archivedRecord == null ? parents : Map<String, String?>.from((archivedRecord['input'] as Map)['parents']),
    online: conversation.online && (archivedRecord == null || (archivedRecord['input'] as Map)['online'] == true),
    network: network,
    primaryDocumentId: question.contexts.map((c) => c.documentId).whereType<String>().firstOrNull,
    execute: (text) async {
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

      final taskImages = archivedRecord != null
          ? [
              for (final i in archivedRecord['images'] as List? ?? [])
                TaskImage(base64Data: i['base64Data'], mimeType: i['mimeType']),
            ]
          : [
              for (final i in await images?.call(question.contexts) ?? <sdk.ImagePart>[])
                TaskImage(base64Data: i.base64Data, mimeType: i.mimeType),
            ];
      final input = <String, dynamic>{
        'question': text,
        if (question.summaryMessageIds != null) 'summaryMessageIds': question.summaryMessageIds,
        'contexts': [for (final c in question.contexts) c.toJson()],
        'documents': [
          for (final d in documents) {'id': d.id, 'title': d.title, 'pages': d.pageCount},
        ],
        'parents': parents,
        'online': conversation.online,
        'toolsEnabled': question.toolsEnabled,
        'reviewOnly': spec.type == TaskType.reviewCards,
      };
      var request = TaskRequest<String>(
        spec: spec,
        images: taskImages,
        streamDrafts: spec.type == TaskType.assistantChat || spec.type == TaskType.reviewCards,
        input: input,
        inputFingerprint: quickInputFingerprint(input),
        modelOverride:
            question.taskModel ??
            (spec.type == TaskType.assistantChat
                ? conversationRoutingOverride(conversation.toJson(), TaskType.assistantChat)
                : null),
      );
      var context = archivedRecord == null
          ? await assembly.freeze(
              request,
              runId: _runId(),
              inputRange: {
                'studySetId': conversation.studySetId,
                'conversationId': conversation.id,
                'requestId': question.requestId,
                'mapId': mapId,
                'baseRevision': revision,
                if (question.summaryMessageIds != null) 'messageIds': question.summaryMessageIds,
                'contexts': [for (final c in question.contexts) c.toJson()],
              },
            )
          : decodeRunContext(Map<String, dynamic>.from(archivedRecord['context']));
      owner.cancel.check();
      final record = (state.metadata['assistant.taskRecords.v1'] as Map?)?[question.requestId] as Map?;
      if (record != null) {
        if (record['version'] != 1 || record['type'] != spec.type.key || (record['input'] as Map)['question'] != text) {
          throw const ConfigurationFailure('assistantTaskRecordMismatch');
        }
        request = TaskRequest<String>(
          spec: spec,
          input: Map<String, dynamic>.from(record['input']),
          images: taskImages,
          streamDrafts: spec.type == TaskType.assistantChat || spec.type == TaskType.reviewCards,
          inputFingerprint: record['fingerprint'],
          maxOutputTokens: record['maxOutputTokens'],
        );
        if (quickInputFingerprint(request.input) != request.inputFingerprint) {
          throw const ConfigurationFailure('assistantTaskInputMismatch');
        }
        context = decodeRunContext(Map<String, dynamic>.from(record['context']));
        if (context.inputRange['studySetId'] != conversation.studySetId ||
            context.inputRange['conversationId'] != conversation.id ||
            context.inputRange['requestId'] != question.requestId) {
          throw const ConfigurationFailure('assistantTaskScopeMismatch');
        }
      }
      final activity = ref.read(assistantTaskActivityProvider(conversation.studySetId).notifier);
      final session = AssistantTaskSession(
        assembly: assembly,
        owner: owner,
        request: request,
        initialContext: context,
        queuedPhase: record?['configurationIntent'] == null
            ? null
            : decodeRunContext(Map<String, dynamic>.from(record!['configurationIntent'])),
        changed: (session) => activity.update(session.context, spec.type, session.status, owner: owner),
        prepareNetwork: (context) async {
          if (spec.type == TaskType.research && owner.online) {
            owner.network =
                network ?? await networkFactory?.call((await assembly.loadModel(context)).model, owner.nativeSearch);
          }
        },
      );
      owner.controls = session;
      if (spec.type == TaskType.conversationSummarize || spec.type == TaskType.documentSummarize) {
        final existing = await assembly.runs.load(context.runId);
        final units = existing == null
            ? await _summaryUnits(owner, spec.type, conversation, question, documents)
            : null;
        final capacity = context.config.capabilities.contextTokens;
        final requestCharacters = ((capacity ?? 60000) - (context.config.policy.maxOutputTokens ?? 8192) - 12000).clamp(
          4096,
          24000,
        );
        return session.runSummary(units: units, capacity: requestCharacters);
      }
      final result = await session.runTask();
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
  const AssistantTaskActivity(this.context, this.type, this.status, this.owner);
  final RunContext context;
  final TaskType type;
  final RunStatus status;
  final AssistantTaskOwner? owner;
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
  void update(RunContext context, TaskType type, RunStatus status, {AssistantTaskOwner? owner}) =>
      state = AssistantTaskActivity(context, type, status, owner);
}
