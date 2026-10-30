part of 'browser.dart';

enum BrowserDocumentMode { readable, original, markdown }

/// An immutable capture of the live tab. Images were read by that tab's
/// session; neither cookies nor an HTTP downloader are exposed to the app.
class BrowserDocumentCapture {
  BrowserDocumentCapture({
    required this.url,
    required this.title,
    required this.capturedAt,
    required this.html,
    required this.snapshot,
    required Map<String, Uint8List> resources,
    Uint8List? pdf,
    List<String> diagnostics = const [],
  }) : resources = Map.unmodifiable(
         resources.map((key, value) => MapEntry(key, Uint8List.fromList(value).asUnmodifiableView())),
       ),
       pdf = pdf == null ? null : Uint8List.fromList(pdf).asUnmodifiableView(),
       diagnostics = List.unmodifiable(diagnostics);
  final Uri url;
  final String title, html, snapshot;
  final DateTime capturedAt;
  final Map<String, Uint8List> resources;
  final Uint8List? pdf;
  final List<String> diagnostics;
}

extension BrowserDocumentConversion on BrowserSession {
  /// Every await checks the navigation generation. Failure/cancellation never
  /// returns a partial PDF or changes the displayed document.
  Future<BrowserDocumentCapture> captureDocument({
    required int navigationId,
    BrowserDocumentMode mode = BrowserDocumentMode.readable,
    bool Function()? cancelled,
    void Function(String stage)? onStage,
  }) async {
    final token = 'mmCapture_${DateTime.now().microsecondsSinceEpoch}';
    void check() {
      if (_disposed || this.navigationId != navigationId || (cancelled?.call() ?? false)) {
        throw StateError('stale_capture');
      }
    }

    Future<Map<String, dynamic>> evaluate(String script) async {
      check();
      final raw = await _channel
          .invokeMethod<String>('evaluate', {'script': script})
          .timeout(const Duration(seconds: 15));
      check();
      if (raw == null || raw.length > 64 * 1024 * 1024) throw StateError('invalid_capture');
      return BrowserSession._decode(raw);
    }

    check();
    if (!_hasDocument || phase == BrowserPhase.failed) throw StateError('page_not_ready');
    if (_capturingDocument) throw StateError('capture_busy');
    _capturingDocument = true;
    try {
      onStage?.call('loading-reader');
      final script = await rootBundle.loadString('packages/mm_platform/assets/readability/Readability.js');
      check();
      onStage?.call('extracting');
      await evaluate(browserDocumentScript(script, token, original: mode == BrowserDocumentMode.original));
      final deadline = DateTime.now().add(const Duration(seconds: 45));
      String? stage;
      Map<String, dynamic> data;
      while (true) {
        data = await evaluate(
          'JSON.stringify(globalThis[${jsonEncode(token)}]?.result || {pending:true,stage:globalThis[${jsonEncode(token)}]?.stage})',
        );
        if (data['stage'] is String && data['stage'] != stage) {
          stage = data['stage'] as String;
          onStage?.call(stage);
        }
        if (data['pending'] != true) break;
        if (DateTime.now().isAfter(deadline)) throw TimeoutException('capture_timeout');
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (data['error'] != null) throw StateError('capture_failed');
      if (data['url'] != url.toString()) throw StateError('stale_capture');
      if ((data['resources'] as Map).length > 64 ||
          (data['html'] as String).length > 16 * 1024 * 1024 ||
          (data['snapshot'] as String).length > 16 * 1024 * 1024) {
        throw StateError('capture_too_large');
      }
      final resources = <String, Uint8List>{};
      var total = 0;
      for (final entry in (data['resources'] as Map).entries) {
        if (!RegExp(r'^resources/[a-zA-Z0-9_-]+\.(png|jpg|gif|webp|svg)$').hasMatch(entry.key as String)) {
          throw StateError('invalid_resource');
        }
        final bytes = base64Decode(entry.value as String);
        total += bytes.length;
        if (bytes.length > 5 * 1024 * 1024 || total > 32 * 1024 * 1024) throw StateError('capture_too_large');
        resources[entry.key as String] = bytes;
      }
      Uint8List? pdf;
      if (mode == BrowserDocumentMode.original) {
        check();
        onStage?.call('printing');
        pdf = await _channel.invokeMethod<Uint8List>('printPdf').timeout(const Duration(seconds: 45));
        check();
        if (pdf == null ||
            pdf.length < 5 ||
            pdf.length > 128 * 1024 * 1024 ||
            ascii.decode(pdf.take(5).toList()) != '%PDF-') {
          throw StateError('invalid_pdf');
        }
        // pushState can precede the next readiness poll.
        final current = await evaluate('JSON.stringify({url:location.href})');
        if (current['url'] != data['url']) throw StateError('stale_capture');
      }
      onStage?.call('complete');
      return BrowserDocumentCapture(
        url: url,
        title: data['title'] as String,
        capturedAt: DateTime.now().toUtc(),
        html: data['html'] as String,
        snapshot: data['snapshot'] as String,
        resources: resources,
        diagnostics: List<String>.from(data['diagnostics'] as List),
        pdf: pdf,
      );
    } finally {
      _capturingDocument = false;
      if (!_disposed) {
        try {
          await _channel
              .invokeMethod<String>('evaluate', {
                'script': 'globalThis[${jsonEncode(token)}]?.cancel(); delete globalThis[${jsonEncode(token)}]; "{}"',
              })
              .timeout(const Duration(seconds: 2));
        } catch (_) {
          /* The page may have disappeared. */
        }
      }
    }
  }
}
