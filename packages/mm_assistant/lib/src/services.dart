import 'providers.dart';

enum ServiceProtocol { openai, anthropic, gemini, ollama }

enum ToolCapability { unknown, supported, unsupported }

enum ConnectionStatus { ok, authFailed, unreachable }

enum WebSearchBackend { none, cloudflare, searxng, tavily, brave }

class ServiceModel {
  const ServiceModel({required this.id, this.name = '', this.enabled = true, this.tools = ToolCapability.unknown});
  final String id, name;
  final bool enabled;
  final ToolCapability tools;
  String get displayName => name.isEmpty ? id : name;
  bool get supportsTools => tools != ToolCapability.unsupported;
  ServiceModel copyWith({String? name, bool? enabled, ToolCapability? tools}) =>
      ServiceModel(id: id, name: name ?? this.name, enabled: enabled ?? this.enabled, tools: tools ?? this.tools);
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'enabled': enabled, 'tools': tools.name};
  factory ServiceModel.fromJson(Map<String, dynamic> j) => ServiceModel(
    id: j['id'],
    name: j['name'] ?? '',
    enabled: j['enabled'] ?? true,
    tools: ToolCapability.values.byName(j['tools'] ?? 'unknown'),
  );
}

class AssistantService {
  AssistantService({
    required this.id,
    required this.protocol,
    required this.name,
    required this.endpoint,
    this.enabled = true,
    this.localEnabled = false,
    this.responses = false,
    List<ServiceModel> models = const [],
  }) : models = List.unmodifiable(models);
  final String id, name, endpoint;
  final ServiceProtocol protocol;
  final bool enabled, localEnabled, responses;
  final List<ServiceModel> models;
  AssistantProvider get provider => switch (protocol) {
    ServiceProtocol.anthropic => AssistantProvider.claude,
    ServiceProtocol.gemini => AssistantProvider.gemini,
    ServiceProtocol.ollama => AssistantProvider.ollama,
    ServiceProtocol.openai => responses ? AssistantProvider.responses : AssistantProvider.compatible,
  };
  AssistantService copyWith({
    String? name,
    String? endpoint,
    bool? enabled,
    bool? localEnabled,
    List<ServiceModel>? models,
  }) => AssistantService(
    id: id,
    protocol: protocol,
    name: name ?? this.name,
    endpoint: endpoint ?? this.endpoint,
    enabled: enabled ?? this.enabled,
    localEnabled: localEnabled ?? this.localEnabled,
    responses: responses,
    models: models ?? this.models,
  );
  AssistantModel configuration(ServiceModel model) => AssistantModel(
    provider: provider,
    model: model.id,
    endpoint: endpoint,
    localEnabled: localEnabled,
    supportsTools: model.supportsTools,
    serviceId: id,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'protocol': protocol.name,
    'name': name,
    'endpoint': endpoint,
    'enabled': enabled,
    'localEnabled': localEnabled,
    'responses': responses,
    'models': models.map((m) => m.toJson()).toList(),
  };
  factory AssistantService.fromJson(Map<String, dynamic> j) => AssistantService(
    id: j['id'],
    protocol: ServiceProtocol.values.byName(j['protocol']),
    name: j['name'],
    endpoint: j['endpoint'],
    enabled: j['enabled'] ?? true,
    localEnabled: j['localEnabled'] ?? false,
    responses: j['responses'] ?? false,
    models: (j['models'] as List).map((m) => ServiceModel.fromJson(Map<String, dynamic>.from(m))).toList(),
  );
}

class ModelReference {
  const ModelReference(this.serviceId, this.modelId);
  final String serviceId, modelId;
  Map<String, dynamic> toJson() => {'serviceId': serviceId, 'modelId': modelId};
}

class AssistantServices {
  AssistantServices({List<AssistantService> services = const [], ModelReference? defaultModel})
    : services = List.unmodifiable(services) {
    final ids = <String>{};
    for (final service in services) {
      if (service.id.isEmpty || !ids.add(service.id)) throw ArgumentError('Duplicate or empty service ID');
      final models = <String>{};
      for (final model in service.models) {
        if (model.id.trim().isEmpty || !models.add(model.id)) throw ArgumentError('Duplicate or empty model ID');
      }
    }
    final available = enabledModels;
    this.defaultModel = available.any((m) => m.serviceId == defaultModel?.serviceId && m.model == defaultModel?.modelId)
        ? defaultModel
        : available.isEmpty
        ? null
        : ModelReference(available.first.serviceId!, available.first.model);
  }
  final List<AssistantService> services;
  late final ModelReference? defaultModel;
  Map<String, List<AssistantModel>> get enabledModelsByService => {
    for (final s in services)
      if (s.enabled && (s.protocol != ServiceProtocol.ollama || s.localEnabled))
        s.id: [
          for (final m in s.models)
            if (m.enabled) s.configuration(m),
        ],
  };
  List<AssistantModel> get enabledModels => enabledModelsByService.values.expand((m) => m).toList();
  AssistantModel? get configuration => enabledModels
      .where((m) => m.serviceId == defaultModel?.serviceId && m.model == defaultModel?.modelId)
      .firstOrNull;
  AssistantServices upsert(AssistantService service) => AssistantServices(
    services: services.any((s) => s.id == service.id)
        ? [for (final s in services) s.id == service.id ? service : s]
        : [...services, service],
    defaultModel: defaultModel,
  );
  AssistantServices remove(String id) =>
      AssistantServices(services: services.where((s) => s.id != id).toList(), defaultModel: defaultModel);
  AssistantServices select(ModelReference reference) {
    if (!enabledModels.any((m) => m.serviceId == reference.serviceId && m.model == reference.modelId)) {
      throw ArgumentError('Model is not enabled');
    }
    return AssistantServices(services: services, defaultModel: reference);
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'services': services.map((s) => s.toJson()).toList(),
    'default': defaultModel?.toJson(),
  };
  factory AssistantServices.fromJson(Map<String, dynamic> j) {
    if (j['version'] != 1) throw const FormatException('Unsupported services version');
    final d = j['default'];
    return AssistantServices(
      services: (j['services'] as List).map((s) => AssistantService.fromJson(Map<String, dynamic>.from(s))).toList(),
      defaultModel: d == null ? null : ModelReference(d['serviceId'], d['modelId']),
    );
  }
}

AssistantModel quickModelFor(AssistantService service, AssistantModel current) =>
    !service.enabled || current.serviceId != service.id
    ? current
    : service.models
              .where((m) => m.enabled && RegExp(r'haiku|mini|flash|small', caseSensitive: false).hasMatch(m.id))
              .map(service.configuration)
              .firstOrNull ??
          current;

class WebSearchSettings {
  const WebSearchSettings({this.backend = WebSearchBackend.none, this.endpoint = ''});
  final WebSearchBackend backend;
  final String endpoint;
  Map<String, dynamic> toJson() => {'version': 1, 'backend': backend.name, 'endpoint': endpoint};
  factory WebSearchSettings.fromJson(Map<String, dynamic> j) => WebSearchSettings(
    backend: j['backend'] == 'model' ? WebSearchBackend.none : WebSearchBackend.values.byName(j['backend']),
    endpoint: j['endpoint'] ?? '',
  );
}
