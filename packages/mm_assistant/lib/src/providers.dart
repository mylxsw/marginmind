import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_research/mm_research.dart';

import 'runtime.dart';
import 'compatible_stream.dart';

enum AssistantProvider { claude, responses, compatible, ollama, gemini }

class AssistantModel {
  const AssistantModel({
    required this.provider,
    required this.model,
    required this.endpoint,
    this.localEnabled = false,
    this.supportsTools = true,
    this.serviceId,
  });
  final AssistantProvider provider;
  final String model, endpoint;
  final bool localEnabled;
  final bool supportsTools;
  final String? serviceId;
  Map<String, dynamic> toJson() => {
    'provider': provider.name,
    'model': model,
    'endpoint': endpoint,
    'localEnabled': localEnabled,
    'supportsTools': supportsTools,
    if (serviceId != null) 'serviceId': serviceId,
  };
  factory AssistantModel.fromJson(Map<String, dynamic> j) => AssistantModel(
    provider: AssistantProvider.values.byName(j['provider']),
    model: j['model'],
    endpoint: j['endpoint'],
    localEnabled: j['localEnabled'] ?? false,
    supportsTools: j['supportsTools'] ?? true,
    serviceId: j['serviceId'],
  );
}

class AssistantConnection {
  AssistantConnection(this.client, this.dio);
  final LLMClient client;
  final Dio dio;
  void close() => dio.close(force: true);
}

/// Compatible/Ollama accept a base URL or a complete chat endpoint.
/// The safe adapter pins the resolved endpoint; SDKs receive its base.
/// Retries only received 429/5xx, never network exceptions or partial streams.
/// A null budget disables session duration/byte quotas for multi-section notes;
/// requestTimeout still applies to each individual request. Long-lived translation
/// schedulers use perRequestBudget and own retries to keep calls and usage aligned.
AssistantConnection connectAssistant(
  AssistantModel config,
  String key, {
  ResearchBudget? budget = const ResearchBudget(),
  Duration? requestTimeout,
  HttpClientAdapter? adapter,
  bool retryRequests = true,
  bool perRequestBudget = false,
}) {
  suppressAssistantDiagnostics();
  final timeout = requestTimeout ?? budget?.duration ?? const Duration(minutes: 2);
  if (timeout <= Duration.zero) throw const ResearchFailure(ResearchFailureKind.invalidRequest);
  final Uri configured;
  try {
    configured = Uri.parse(config.endpoint.trim());
  } on FormatException {
    throw const ResearchFailure(ResearchFailureKind.invalidRequest);
  }
  final suffix = switch (config.provider) {
    AssistantProvider.claude => '/v1/messages',
    AssistantProvider.responses => '/responses',
    AssistantProvider.gemini => '/v1beta',
    _ => '/chat/completions',
  };
  if (config.model.trim().isEmpty ||
      (config.provider == AssistantProvider.gemini && !RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(config.model)) ||
      configured.host.isEmpty ||
      configured.userInfo.isNotEmpty ||
      configured.hasQuery ||
      configured.hasFragment ||
      (config.provider == AssistantProvider.ollama
          ? !config.localEnabled || !{'http', 'https'}.contains(configured.scheme)
          : configured.scheme != 'https')) {
    throw const ResearchFailure(ResearchFailureKind.invalidRequest);
  }
  var path = configured.path.replaceFirst(RegExp(r'/+$'), '');
  if (config.provider == AssistantProvider.compatible || config.provider == AssistantProvider.ollama) {
    if (path.isEmpty) path = '/v1';
    if (!path.endsWith(suffix)) path += suffix;
  }
  if (config.provider == AssistantProvider.claude && !path.endsWith('/messages')) {
    path = path.endsWith('/v1') ? '$path/messages' : '$path/v1/messages';
  }
  if (config.provider == AssistantProvider.responses && !path.endsWith('/responses')) {
    path = path.isEmpty ? '/v1/responses' : '$path/responses';
  }
  if (config.provider == AssistantProvider.gemini && path.isEmpty) path = '/v1beta';
  if (!path.endsWith(suffix)) throw const ResearchFailure(ResearchFailureKind.invalidRequest);
  final endpoint = configured.replace(path: path);
  if (config.provider == AssistantProvider.ollama &&
      !{'localhost', '127.0.0.1', '::1', '[::1]'}.contains(endpoint.host)) {
    throw const ResearchFailure(ResearchFailureKind.unsafeUrl);
  }
  final geminiEndpoints = {
    for (final action in ['generateContent', 'streamGenerateContent'])
      endpoint.replace(path: '${endpoint.path}/models/${config.model}:$action'),
  };
  final policy = config.provider == AssistantProvider.gemini
      ? _ExactProviderPolicy(geminiEndpoints)
      : UrlPolicy(
          localEndpoint: config.provider == AssistantProvider.ollama ? endpoint : null,
          providerEndpoint: endpoint,
        );
  final dio = Dio(BaseOptions(followRedirects: false, maxRedirects: 0));
  final address = endpoint.toString();
  final base = address.substring(0, address.length - suffix.length);
  final client = switch (config.provider) {
    AssistantProvider.gemini => GeminiClient(apiKey: key, client: dio, maxRetries: 0, timeout: timeout),
    AssistantProvider.claude => ClaudeClient(apiKey: key, baseUrl: base, client: dio, maxRetries: 0, timeout: timeout),
    AssistantProvider.responses => ResponsesClient(
      apiKey: key,
      baseUrl: base,
      client: dio,
      maxRetries: 0,
      timeout: timeout,
      autoPreviousResponseId: false,
    ),
    _ => OpenAIClient(apiKey: key, baseUrl: base, client: dio, maxRetries: 0, timeout: timeout),
  };
  // Set AFTER SDK initialization: configureProxy may otherwise replace adapter.
  dio.httpClientAdapter = _BoundedAdapter(
    adapter ?? IOHttpClientAdapter(createHttpClient: () => policy.createClient()),
    budget?.responseBytes,
    perRequestBudget: perRequestBudget,
    normalizeNames: config.provider == AssistantProvider.compatible || config.provider == AssistantProvider.ollama,
  );
  final deadline = budget == null || perRequestBudget ? null : DateTime.now().add(budget.duration);
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        var allowed = options.uri == endpoint;
        if (config.provider == AssistantProvider.gemini) {
          final native = Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/${config.model}:generateContent',
          );
          final stream = Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/${config.model}:streamGenerateContent',
          );
          allowed = options.uri == native || options.uri == stream || geminiEndpoints.contains(options.uri);
          if (allowed) {
            final action = options.uri.path.endsWith(':generateContent') ? 'generateContent' : 'streamGenerateContent';
            options.path = endpoint.replace(path: '${endpoint.path}/models/${config.model}:$action').toString();
          }
        }
        if (!allowed || (deadline != null && DateTime.now().isAfter(deadline))) {
          handler.reject(
            DioException(requestOptions: options, error: const ResearchFailure(ResearchFailureKind.invalidRequest)),
          );
          return;
        }
        options.followRedirects = false;
        options.validateStatus = (code) => code == 200;
        handler.next(options);
      },
      onError: (error, handler) async {
        final status = error.response?.statusCode;
        final attempt = error.requestOptions.extra['assistant.retry'] as int? ?? 0;
        if (retryRequests && status != null && (status == 429 || status >= 500) && attempt < 2) {
          final seconds = int.tryParse(error.response?.headers.value('retry-after') ?? '');
          final delay = seconds == null
              ? Duration(milliseconds: 500 * (1 << attempt))
              : Duration(seconds: seconds.clamp(0, 30));
          if (deadline == null || DateTime.now().add(delay).isBefore(deadline)) {
            final token = error.requestOptions.cancelToken;
            await Future.any([Future<void>.delayed(delay), if (token != null) token.whenCancel.then<void>((_) {})]);
            if (token?.isCancelled != true) {
              try {
                error.requestOptions.extra['assistant.retry'] = attempt + 1;
                handler.resolve(await dio.fetch(error.requestOptions));
                return;
              } on DioException catch (e) {
                handler.next(e);
                return;
              }
            }
          }
        }
        handler.next(error);
      },
    ),
  );
  return AssistantConnection(client, dio);
}

class _BoundedAdapter implements HttpClientAdapter {
  _BoundedAdapter(this.inner, this.maximum, {this.normalizeNames = false, this.perRequestBudget = false});
  final HttpClientAdapter inner;
  final int? maximum;
  final bool normalizeNames, perRequestBudget;
  int bytes = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    var requestBytes = 0;
    final response = await inner.fetch(options, requestStream, cancelFuture);
    response.stream = response.stream.map((chunk) {
      if (maximum case final limit?) {
        requestBytes += chunk.length;
        bytes += perRequestBudget ? 0 : chunk.length;
        if ((perRequestBudget ? requestBytes : bytes) > limit) throw const ResearchFailure(ResearchFailureKind.budget);
      }
      return chunk;
    });
    if (normalizeNames && response.statusCode == 200 && options.responseType == ResponseType.stream) {
      response.stream = normalizeCompatibleToolNames(response.stream);
    }
    return response;
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
}

/// Each native Gemini operation gets its own provider-only fake-IP exception.
class _ExactProviderPolicy extends UrlPolicy {
  _ExactProviderPolicy(this.endpoints);
  final Set<Uri> endpoints;
  @override
  Future<List<InternetAddress>> validate(Uri url) {
    if (!endpoints.contains(url)) throw const ResearchFailure(ResearchFailureKind.unsafeUrl);
    return UrlPolicy(providerEndpoint: url).validate(url);
  }
}
