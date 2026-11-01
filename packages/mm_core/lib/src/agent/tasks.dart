import 'models.dart';

enum TaskCategory { quick, heavy }

enum TaskType {
  selectionTranslate('selection_translate', TaskCategory.quick, ['translation.basic']),
  wordLookup('word_lookup', TaskCategory.quick, ['vocabulary.basic']),
  titleGenerate('title_generate', TaskCategory.quick, ['title.basic']),
  assistantChat('assistant_chat', TaskCategory.heavy, ['assistant.core', 'explain']),
  conversationSummarize('conversation_summarize', TaskCategory.heavy, ['summary.conversation']),
  documentSummarize('document_summarize', TaskCategory.heavy, ['summary.document']),
  documentTranslate('document_translate', TaskCategory.heavy, ['translation.document']),
  mapExpand('map_expand', TaskCategory.heavy, ['mindmap.expand']),
  mapGenerate('map_generate', TaskCategory.heavy, ['mindmap.document']),
  research('research', TaskCategory.heavy, ['research.evidence']),
  studyNotes('study_notes', TaskCategory.heavy, ['notes.organize']),
  reviewCards('review_cards', TaskCategory.heavy, ['review.grounded']);

  const TaskType(this.key, this.category, this.knowledgePacks);
  final String key;
  final TaskCategory category;
  final List<String> knowledgePacks;
  static TaskType? fromKey(String key) {
    for (final type in values) {
      if (type.key == key) return type;
    }
    return null;
  }
}

enum RunPurpose { task, contextCompact, nativeSearch, schemaRepair, capabilityProbe }

/// Domain migrations register concrete schemas/validators; this is not an executable prompt registry.
class TaskSpec {
  TaskSpec({
    required this.type,
    required this.inputSchema,
    required this.resultSchema,
    required this.promptVersion,
    required this.schemaVersion,
    required this.completionRule,
    Set<String> allowedTools = const {},
    Set<ModelCapability> requiredCapabilities = const {},
    this.maxRepairs = 1,
    this.maxOutputTokens,
  }) : allowedTools = Set.unmodifiable(allowedTools),
       requiredCapabilities = Set.unmodifiable(requiredCapabilities) {
    if (maxRepairs < 0 || (type.category == TaskCategory.quick && (allowedTools.isNotEmpty || maxRepairs > 1))) {
      throw ArgumentError('Quick tasks allow no tools and at most one repair');
    }
  }
  final TaskType type;
  final String inputSchema, resultSchema, promptVersion, schemaVersion, completionRule;
  final Set<String> allowedTools;
  final Set<ModelCapability> requiredCapabilities;
  final int maxRepairs;
  final int? maxOutputTokens;
  TaskCategory get category => type.category;
  List<String> get knowledgePacks => type.knowledgePacks;
}

class TaskRequest<T> {
  TaskRequest({
    required this.spec,
    required Map<String, dynamic> input,
    required this.inputFingerprint,
    this.modelOverride,
    this.reasoning,
    this.maxOutputTokens,
    this.purpose = RunPurpose.task,
  }) : input = freezeAgentJson(input);
  final TaskSpec spec;
  final Map<String, dynamic> input;
  final String inputFingerprint;
  final ModelReference? modelOverride;
  final ReasoningPolicy? reasoning;
  final int? maxOutputTokens;
  final RunPurpose purpose;
}

/// Raw versioned bindings preserve unknown task keys for forward-compatible storage.
/// Interpretation/precedence and revision-controlled writes belong to S1.
class RoutingConfig {
  RoutingConfig({required Map<String, dynamic> document}) : document = freezeAgentJson(document) {
    if (document['version'] != 1) throw const ConfigurationFailure('unsupportedRoutingVersion');
    if (document['revision'] is! int || (document['revision'] as int) < 0) {
      throw const ConfigurationFailure('invalidRoutingRevision');
    }
  }
  final Map<String, dynamic> document;
  int get revision => document['revision'] as int;
  Map<String, dynamic> toJson() => document;
  ModelReference? defaultModel(TaskCategory category) {
    final value = (document['defaults'] as Map?)?[category.name];
    return value == null ? null : ModelReference.fromJson(Map<String, dynamic>.from(value as Map));
  }

  TaskModelBinding binding(TaskType type) {
    final value = (document['bindings'] as Map?)?[type.key];
    return value == null
        ? const TaskModelBinding.inherit()
        : TaskModelBinding.fromJson(Map<String, dynamic>.from(value as Map));
  }

  ReasoningPolicy get heavyReasoning => ReasoningPolicy.values.byName(document['heavyReasoning'] as String? ?? 'auto');
}

abstract interface class ModelResolver {
  Future<ResolvedTaskConfig> resolve<T>(TaskRequest<T> request, RoutingConfig routing);
}

class KnowledgeBundle {
  KnowledgeBundle({required this.id, required this.version, required this.instructions, Set<String> tools = const {}})
    : tools = Set.unmodifiable(tools);
  final String id, version, instructions;
  final Set<String> tools;
}

abstract interface class KnowledgeRegistry {
  List<KnowledgeBundle> resolve(TaskSpec spec, Map<String, String> versions);
}

enum TaskBindingMode { inherit, explicit }

class TaskModelBinding {
  const TaskModelBinding.inherit() : mode = TaskBindingMode.inherit, model = null, reasoning = null;
  const TaskModelBinding.explicit(ModelReference this.model, {this.reasoning}) : mode = TaskBindingMode.explicit;
  final TaskBindingMode mode;
  final ModelReference? model;
  final ReasoningPolicy? reasoning;
  factory TaskModelBinding.fromJson(Map<String, dynamic> json) {
    if (json['mode'] == 'inherit') return const TaskModelBinding.inherit();
    if (json['mode'] != 'explicit' || json['model'] is! Map) {
      throw const ConfigurationFailure('invalidBinding');
    }
    return TaskModelBinding.explicit(
      ModelReference.fromJson(Map<String, dynamic>.from(json['model'] as Map)),
      reasoning: json['reasoning'] == null ? null : ReasoningPolicy.values.byName(json['reasoning'] as String),
    );
  }
  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    if (model != null) 'model': model!.toJson(),
    if (reasoning != null) 'reasoning': reasoning!.name,
  };
}
