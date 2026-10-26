import 'dart:async';
import 'dart:convert';

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
        'api-key',
        'cookie',
        'cookie2',
      }.contains(name.toLowerCase());
      var redirects = 0;
      var attempt = 0;
      while (true) {
        await guarded(policy.validate(target));
        final request = http.AbortableRequest(method, target, abortTrigger: abort.future)
          ..followRedirects = false
          ..headers.addAll(forwardedHeaders);
        if (body != null) {
          request.headers['content-type'] = 'application/json';
          request.body = jsonEncode(body);
        }
        final response = await guarded(client.send(request));
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
        if ((response.statusCode == 429 || response.statusCode >= 500) && attempt < maxRetries) {
          await response.stream.listen(null).cancel();
          final seconds = int.tryParse(response.headers['retry-after'] ?? '');
          final delay = seconds != null ? Duration(seconds: seconds.clamp(0, 30)) : retryDelay * (1 << attempt);
          attempt++;
          await guarded(Future<void>.delayed(delay));
          continue;
        }
        if (response.statusCode != 200) {
          throw ResearchFailure(switch (response.statusCode) {
            401 || 403 => ResearchFailureKind.authentication,
            429 => ResearchFailureKind.rateLimited,
            >= 500 => ResearchFailureKind.unavailable,
            _ => ResearchFailureKind.invalidRequest,
          });
        }
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
