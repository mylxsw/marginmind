import 'dart:async';
import 'dart:typed_data';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_research/mm_research.dart';

import 'runtime.dart';

enum AssistantProvider { claude, responses, compatible, ollama }

class AssistantModel {
  const AssistantModel({
    required this.provider,
    required this.model,
    required this.endpoint,
    this.localEnabled = false,
    this.supportsTools = true,
  });
  final AssistantProvider provider;
  final String model, endpoint;
  final bool localEnabled;
  final bool supportsTools;
  Map<String, dynamic> toJson() => {
    'provider': provider.name,
    'model': model,
    'endpoint': endpoint,
    'localEnabled': localEnabled,
    'supportsTools': supportsTools,
  };
  factory AssistantModel.fromJson(Map<String, dynamic> j) => AssistantModel(
    provider: AssistantProvider.values.byName(j['provider']),
    model: j['model'],
    endpoint: j['endpoint'],
    localEnabled: j['localEnabled'] ?? false,
    supportsTools: j['supportsTools'] ?? true,
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
AssistantConnection connectAssistant(
  AssistantModel config,
  String key, {
  ResearchBudget budget = const ResearchBudget(),
  HttpClientAdapter? adapter,
}) {
  suppressAssistantDiagnostics();
  final Uri configured;
  try {
    configured = Uri.parse(config.endpoint.trim());
  } on FormatException {
    throw const ResearchFailure(ResearchFailureKind.invalidRequest);
  }
  final suffix = switch (config.provider) {
    AssistantProvider.claude => '/v1/messages',
    AssistantProvider.responses => '/responses',
    _ => '/chat/completions',
  };
  if (config.model.trim().isEmpty ||
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
  if (!path.endsWith(suffix)) throw const ResearchFailure(ResearchFailureKind.invalidRequest);
  final endpoint = configured.replace(path: path);
  if (config.provider == AssistantProvider.ollama &&
      !{'localhost', '127.0.0.1', '::1', '[::1]'}.contains(endpoint.host)) {
    throw const ResearchFailure(ResearchFailureKind.unsafeUrl);
  }
  final policy = UrlPolicy(
    localEndpoint: config.provider == AssistantProvider.ollama ? endpoint : null,
    providerEndpoint: endpoint,
  );
  final dio = Dio(BaseOptions(followRedirects: false, maxRedirects: 0));
  final address = endpoint.toString();
  final base = address.substring(0, address.length - suffix.length);
  final client = switch (config.provider) {
    AssistantProvider.claude => ClaudeClient(
      apiKey: key,
      baseUrl: base,
      client: dio,
      maxRetries: 0,
      timeout: budget.duration,
    ),
    AssistantProvider.responses => ResponsesClient(
      apiKey: key,
      baseUrl: base,
      client: dio,
      maxRetries: 0,
      timeout: budget.duration,
      autoPreviousResponseId: false,
    ),
    _ => OpenAIClient(apiKey: key, baseUrl: base, client: dio, maxRetries: 0, timeout: budget.duration),
  };
  // Set AFTER SDK initialization: configureProxy may otherwise replace adapter.
  dio.httpClientAdapter = _BoundedAdapter(
    adapter ?? IOHttpClientAdapter(createHttpClient: () => policy.createClient()),
    budget.responseBytes,
  );
  final deadline = DateTime.now().add(budget.duration);
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.uri != endpoint || DateTime.now().isAfter(deadline)) {
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
        if (status != null && (status == 429 || status >= 500) && attempt < 2) {
          final seconds = int.tryParse(error.response?.headers.value('retry-after') ?? '');
          final delay = seconds == null
              ? Duration(milliseconds: 500 * (1 << attempt))
              : Duration(seconds: seconds.clamp(0, 30));
          if (DateTime.now().add(delay).isBefore(deadline)) {
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
  _BoundedAdapter(this.inner, this.maximum);
  final HttpClientAdapter inner;
  final int maximum;
  int bytes = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final response = await inner.fetch(options, requestStream, cancelFuture);
    response.stream = response.stream.map((chunk) {
      bytes += chunk.length;
      if (bytes > maximum) throw const ResearchFailure(ResearchFailureKind.budget);
      return chunk;
    });
    return response;
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
}
