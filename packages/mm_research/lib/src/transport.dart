import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:mm_core/mm_core.dart';

import 'url_policy.dart';

class BudgetCounter {
  BudgetCounter(this.limits) {
    limits.validate();
  }
  final ResearchBudget limits;
  int searches = 0, pages = 0, bytes = 0;
  void search() {
    if (++searches > limits.searches) _exceeded();
  }

  void page() {
    if (++pages > limits.pages) _exceeded();
  }

  void addBytes(int count) {
    bytes += count;
    if (bytes > limits.responseBytes) _exceeded();
  }

  Never _exceeded() => throw const ResearchFailure(ResearchFailureKind.budget);
}

class ResearchHttp {
  ResearchHttp({
    UrlPolicy? policy,
    this._clientFactory,
    this.retryDelay = const Duration(milliseconds: 500),
    this.maxRetries = 2,
  }) : policy = policy ?? UrlPolicy();
  final UrlPolicy policy;
  final http.Client Function()? _clientFactory;
  final Duration retryDelay;
  final int maxRetries;

  Stream<List<int>> send(
    Uri url, {
    required CancellationToken cancellation,
    ResearchBudget budget = const ResearchBudget(),
    String method = 'GET',
    Map<String, String> headers = const {},
    Object? body,
    void Function(Uri url, Map<String, String> headers)? onResponse,
  }) async* {
    budget.validate();
    cancellation.check();
    final abort = Completer<void>();
    var timedOut = false;
    void stop() {
      if (!abort.isCompleted) abort.complete();
    }

    final timer = Timer(budget.duration, () {
      timedOut = true;
      stop();
    });
    // Detached listener contains no work; transport always closes in finally.
    cancellation.whenCancelled.then((_) => stop());
    final client = _clientFactory?.call() ?? IOClient(policy.createClient());
    final counter = BudgetCounter(budget);
    Future<T> guarded<T>(Future<T> work) => Future.any([
      work,
      abort.future.then<T>(
        (_) => throw ResearchFailure(timedOut ? ResearchFailureKind.timeout : ResearchFailureKind.cancelled),
      ),
    ]);
    try {
      var target = url;
      final forwardedHeaders = Map<String, String>.of(headers);
      bool sensitive(String name) => const {
        'authorization',
        'proxy-authorization',
        'x-api-key',
        'x-goog-api-key',
        'x-subscription-token',
        'api-key',
        'cookie',
        'cookie2',
      }.contains(name.toLowerCase());
      var redirects = 0;
      var attempt = 0;
      while (true) {
        http.StreamedResponse response;
        try {
          await guarded(policy.validate(target));
          final request = http.AbortableRequest(method, target, abortTrigger: abort.future)
            ..followRedirects = false
            ..headers.addAll(forwardedHeaders);
          if (body != null) {
            request.headers['content-type'] = 'application/json';
            request.body = jsonEncode(body);
          }
          response = await guarded(client.send(request));
        } on ResearchFailure {
          rethrow;
        } catch (error) {
          cancellation.check();
          if (timedOut) throw const ResearchFailure(ResearchFailureKind.timeout);
          if (error is HandshakeException) {
            throw const ResearchFailure(ResearchFailureKind.unavailable, 'tls');
          }
          if (attempt >= maxRetries) {
            throw const ResearchFailure(ResearchFailureKind.unavailable, 'connection');
          }
          await guarded(Future<void>.delayed(retryDelay * (1 << attempt++)));
          continue;
        }
        if (response.statusCode >= 300 && response.statusCode < 400) {
          // Never forward API keys, authorization, or POST payloads on redirects.
          if (method != 'GET' ||
              forwardedHeaders.keys.any(sensitive) ||
              ++redirects > 5 ||
              response.headers['location'] == null) {
            throw const ResearchFailure(ResearchFailureKind.unsafeUrl);
          }
          await response.stream.listen(null).cancel();
          forwardedHeaders.removeWhere((name, _) => sensitive(name));
          target = target.resolve(response.headers['location']!);
          continue;
        }
        if ((response.statusCode == 408 || response.statusCode == 429 || response.statusCode >= 500) &&
            attempt < maxRetries) {
          await response.stream.listen(null).cancel();
          final seconds = int.tryParse(response.headers['retry-after'] ?? '');
          final delay = seconds != null ? Duration(seconds: seconds.clamp(0, 30)) : retryDelay * (1 << attempt);
          attempt++;
          await guarded(Future<void>.delayed(delay));
          continue;
        }
        if (response.statusCode != 200) {
          // Read only a small diagnostic body, under the same cancellation/deadline.
          final bytes = <int>[];
          final iterator = StreamIterator(response.stream);
          try {
            while (bytes.length < 8192 && await guarded(iterator.moveNext())) {
              bytes.addAll(iterator.current.take(8192 - bytes.length));
            }
          } finally {
            await iterator.cancel();
          }
          final message = providerErrorMessage(utf8.decode(bytes, allowMalformed: true), secrets: headers.values);
          throw ResearchFailure(
            switch (response.statusCode) {
              401 || 403 => ResearchFailureKind.authentication,
              408 => ResearchFailureKind.timeout,
              429 => ResearchFailureKind.rateLimited,
              >= 500 => ResearchFailureKind.unavailable,
              _ => ResearchFailureKind.invalidRequest,
            },
            null,
            message,
            response.statusCode,
          );
        }
        onResponse?.call(target, response.headers);
        final length = response.contentLength;
        if (length != null && length > budget.responseBytes) {
          throw const ResearchFailure(ResearchFailureKind.budget);
        }
        final iterator = StreamIterator(response.stream);
        try {
          while (await guarded(iterator.moveNext())) {
            cancellation.check();
            counter.addBytes(iterator.current.length);
            yield iterator.current;
          }
        } finally {
          await iterator.cancel();
        }
        break;
      }
    } on ResearchFailure {
      rethrow;
    } catch (_) {
      if (timedOut) throw const ResearchFailure(ResearchFailureKind.timeout);
      cancellation.check();
      throw const ResearchFailure(ResearchFailureKind.unavailable);
    } finally {
      timer.cancel();
      stop();
      client.close();
    }
  }
}

/// SSE decoding is independent of network packet and UTF-8 character boundaries.
Stream<Map<String, dynamic>> decodeEvents(Stream<List<int>> bytes) async* {
  var data = <String>[];
  await for (final line in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) {
      if (data.isEmpty) continue;
      final value = data.join('\n');
      data = [];
      if (value == '[DONE]') {
        yield {'type': 'done'};
        continue;
      }
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, dynamic>) throw const FormatException('Invalid SSE data');
      yield decoded;
    } else if (line.startsWith('data:')) {
      data.add(line.substring(5).replaceFirst(RegExp(r'^ '), ''));
    }
  }
  if (data.isNotEmpty) throw const FormatException('Truncated SSE frame');
}

/// Extract only the provider's error message, never arbitrary HTML or payloads.
String? providerErrorMessage(String body, {Iterable<String> secrets = const []}) {
  try {
    final value = jsonDecode(body);
    if (value is! Map) return null;
    final error = value['error'];
    final raw = error is Map
        ? error['message']
        : error is String
        ? error
        : value['message'];
    if (raw is! String) return null;
    var message = raw;
    for (final secret in secrets) {
      for (final token in [secret, secret.replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '')]) {
        if (token.isNotEmpty) message = message.replaceAll(token, '[redacted]');
      }
    }
    message = message
        .replaceAll(RegExp(r'(?:sk-|sk_)[a-zA-Z0-9_-]+'), '[redacted]')
        .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')
        .trim();
    return message.isEmpty ? null : message.substring(0, message.length.clamp(0, 600));
  } catch (_) {
    return null;
  }
}
