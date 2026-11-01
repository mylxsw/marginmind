import 'dart:convert';

import 'package:mm_core/mm_core.dart';
import 'package:mm_research/mm_research.dart';

import 'network.dart';
import 'services.dart';

/// Factory is injectable for fake HTTP; production pins each exact operation.
typedef ServiceHttpFactory = ResearchHttp Function(Uri endpoint, bool local);
ResearchHttp serviceHttp(Uri endpoint, bool local) => AssistantNetworkHttp(
  policy: UrlPolicy(providerEndpoint: endpoint, localEndpoint: local ? endpoint : null),
);

Uri serviceEndpoint(AssistantService service, String operation) {
  final uri = Uri.parse(service.endpoint.trim());
  UrlPolicy.syntax(uri);
  if (uri.hasQuery || (service.protocol != ServiceProtocol.ollama && uri.scheme != 'https')) {
    throw const ResearchFailure(ResearchFailureKind.unsafeUrl);
  }
  if (service.protocol == ServiceProtocol.ollama &&
      (!service.localEnabled || !{'localhost', '127.0.0.1', '::1', '[::1]'}.contains(uri.host))) {
    throw const ResearchFailure(ResearchFailureKind.unsafeUrl);
  }
  var path = uri.path.replaceFirst(RegExp(r'/+$'), '');
  path = path.replaceFirst(RegExp(r'/(chat/completions|responses|messages)$'), '');
  switch (service.protocol) {
    case ServiceProtocol.openai:
      if (path.isEmpty) path = '/v1';
    case ServiceProtocol.anthropic:
      if (!path.endsWith('/v1')) path += '/v1';
    case ServiceProtocol.gemini:
      if (!path.endsWith('/v1beta')) path += '/v1beta';
    case ServiceProtocol.ollama:
      path = path.replaceFirst(RegExp(r'/(v1|api)$'), '');
      path += '/api';
  }
  return uri.replace(path: '$path/$operation');
}

Map<String, String> serviceHeaders(AssistantService service, String key) => switch (service.protocol) {
  ServiceProtocol.anthropic => {'x-api-key': key, 'anthropic-version': '2023-06-01'},
  ServiceProtocol.gemini => {'x-goog-api-key': key},
  _ => {'authorization': 'Bearer $key'},
};

Future<Map<String, dynamic>> serviceJson(
  ResearchHttp http,
  Uri url,
  CancellationToken cancel, {
  String method = 'GET',
  Map<String, String> headers = const {},
  Object? body,
}) async {
  final bytes = await http
      .send(url, cancellation: cancel, method: method, headers: headers, body: body)
      .expand((b) => b)
      .toList();
  cancel.check();
  try {
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  } catch (_) {
    throw const ResearchFailure(ResearchFailureKind.protocol);
  }
}

class ServiceCatalog {
  ServiceCatalog({this.httpFactory = serviceHttp});
  final ServiceHttpFactory httpFactory;
  Future<Map<String, dynamic>> _request(
    AssistantService service,
    String key,
    String operation,
    CancellationToken cancel, {
    Object? body,
    Map<String, String>? query,
    ServiceHttpFactory? transport,
  }) {
    var endpoint = serviceEndpoint(service, operation);
    if (query != null) endpoint = endpoint.replace(queryParameters: query);
    return serviceJson(
      (transport ?? httpFactory)(endpoint, service.protocol == ServiceProtocol.ollama),
      endpoint,
      cancel,
      method: body == null ? 'GET' : 'POST',
      headers: serviceHeaders(service, key),
      body: body,
    );
  }

  Future<ConnectionStatus> check(AssistantService service, String key, {CancellationToken? cancellation}) async {
    try {
      await list(service, key, cancellation: cancellation);
      return ConnectionStatus.ok;
    } on ResearchFailure catch (e) {
      if (e.kind == ResearchFailureKind.cancelled) rethrow;
      return e.kind == ResearchFailureKind.authentication ? ConnectionStatus.authFailed : ConnectionStatus.unreachable;
    } catch (_) {
      return ConnectionStatus.unreachable;
    }
  }

  Future<List<ServiceModel>> list(AssistantService service, String key, {CancellationToken? cancellation}) async {
    final cancel = cancellation ?? CancellationToken();
    final counter = BudgetCounter(const ResearchBudget());
    final deadline = DateTime.now().add(const ResearchBudget().duration);
    final ServiceHttpFactory transport = httpFactory == serviceHttp
        ? (url, local) => AssistantNetworkHttp(
            policy: UrlPolicy(providerEndpoint: url, localEndpoint: local ? url : null),
            sharedCounter: counter,
            sharedDeadline: deadline,
          )
        : httpFactory;
    final models = <String, ServiceModel>{};
    String? cursor;
    final cursors = <String>{};
    for (var page = 0; page < 20; page++) {
      final data = await _request(
        service,
        key,
        service.protocol == ServiceProtocol.ollama ? 'tags' : 'models',
        cancel,
        transport: transport,
        query: cursor == null ? null : {service.protocol == ServiceProtocol.gemini ? 'pageToken' : 'after_id': cursor},
      );
      final rows =
          data[service.protocol == ServiceProtocol.gemini || service.protocol == ServiceProtocol.ollama
              ? 'models'
              : 'data'];
      if (rows is! List) throw const ResearchFailure(ResearchFailureKind.protocol);
      if (models.length + rows.length > 1000) throw const ResearchFailure(ResearchFailureKind.budget);
      for (final raw in rows) {
        if (raw is! Map) continue;
        final id = (raw['id'] ?? raw['model'] ?? raw['name']) as String?;
        if (id == null || id.isEmpty || !_chat(raw, id)) continue;
        Map details = raw;
        if (service.protocol == ServiceProtocol.ollama && raw['capabilities'] == null) {
          final metadata = await _request(service, key, 'show', cancel, body: {'model': id}, transport: transport);
          details = {...raw, ...metadata};
          if (!_chat(details, id)) continue;
        }
        final normalized = id.replaceFirst(RegExp(r'^models/'), '');
        final caps = details['capabilities'];
        final supported = details['supports_tools'] ?? (caps is Map ? caps['tools'] ?? caps['function_calling'] : null);
        models[normalized] = ServiceModel(
          id: normalized,
          name: (raw['display_name'] ?? raw['displayName'] ?? raw['name'] ?? normalized) as String,
          tools: supported is bool
              ? (supported ? ToolCapability.supported : ToolCapability.unsupported)
              : caps is List
              ? (caps.contains('tools') ? ToolCapability.supported : ToolCapability.unsupported)
              : ToolCapability.unknown,
        );
      }
      cursor = service.protocol == ServiceProtocol.gemini
          ? data['nextPageToken'] as String?
          : data['has_more'] == true
          ? data['last_id'] as String?
          : null;
      if (cursor == null || cursor.isEmpty) return models.values.toList();
      if (!cursors.add(cursor)) throw const ResearchFailure(ResearchFailureKind.protocol);
    }
    throw const ResearchFailure(ResearchFailureKind.budget);
  }

  bool _chat(Map raw, String id) {
    final methods = raw['supportedGenerationMethods'];
    if (methods is List && !methods.contains('generateContent')) return false;
    final caps = raw['capabilities'];
    if (caps is List && !caps.contains('completion')) return false;
    return !RegExp(
      r'embed|whisper|tts|dall-e|imagen|veo|moderation|transcri|image-generation|gpt-image|audio|speech|rerank',
      caseSensitive: false,
    ).hasMatch(id);
  }

  /// A successful minimal tool request proves acceptance, never executes a tool.
  /// Transport failures remain unknown and can be retried by the caller.
  Future<ServiceModel> probe(
    AssistantService service,
    ServiceModel model,
    String key, {
    CancellationToken? cancellation,
  }) async {
    if (model.tools != ToolCapability.unknown) return model;
    if (service.protocol == ServiceProtocol.gemini && !RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(model.id)) {
      throw const ResearchFailure(ResearchFailureKind.invalidRequest);
    }
    final cancel = cancellation ?? CancellationToken();
    const schema = {'type': 'object', 'properties': <String, dynamic>{}};
    const function = {'name': 'connection_probe', 'description': 'Connection check', 'parameters': schema};
    final (operation, body) = switch (service.protocol) {
      ServiceProtocol.anthropic => (
        'messages',
        <String, dynamic>{
          'model': model.id,
          'max_tokens': 1,
          'messages': [
            {'role': 'user', 'content': 'ping'},
          ],
          'tools': [
            {'name': 'connection_probe', 'description': 'Connection check', 'input_schema': schema},
          ],
        },
      ),
      ServiceProtocol.gemini => (
        'models/${model.id}:generateContent',
        <String, dynamic>{
          'contents': [
            {
              'parts': [
                {'text': 'ping'},
              ],
            },
          ],
          'generationConfig': {'maxOutputTokens': 1},
          'tools': [
            {
              'functionDeclarations': [function],
            },
          ],
        },
      ),
      ServiceProtocol.ollama => (
        'chat',
        <String, dynamic>{
          'model': model.id,
          'stream': false,
          'messages': [
            {'role': 'user', 'content': 'ping'},
          ],
          'options': {'num_predict': 1},
          'tools': [
            {'type': 'function', 'function': function},
          ],
        },
      ),
      ServiceProtocol.openai => (
        service.responses ? 'responses' : 'chat/completions',
        <String, dynamic>{
          'model': model.id,
          'store': false,
          if (service.responses) ...{
            'input': 'ping',
            'max_output_tokens': 16,
            'tools': [
              {'type': 'function', ...function},
            ],
          } else ...{
            'messages': [
              {'role': 'user', 'content': 'ping'},
            ],
            'max_tokens': 1,
            'tools': [
              {'type': 'function', 'function': function},
            ],
          },
        },
      ),
    };
    try {
      await _request(service, key, operation, cancel, body: body);
      return model; // Acceptance alone is not evidence that tool calling works.
    } on ResearchFailure catch (e) {
      if (e.kind == ResearchFailureKind.cancelled) rethrow;
      // Only an explicit tool rejection is a negative capability result.
      if (e.statusCode == 400 &&
          RegExp(
            r'(tool|function).*(not supported|unsupported)|does not support.*(tool|function)',
            caseSensitive: false,
          ).hasMatch(e.message ?? '')) {
        return model.copyWith(tools: ToolCapability.unsupported);
      }
      return model;
    }
  }
}
