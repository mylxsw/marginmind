import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_platform/mm_platform.dart';

final pdfOcrServiceProvider = Provider<PdfOcrService>((ref) => VisionPdfOcr());

class ReaderOcrState {
  const ReaderOcrState({
    this.document,
    this.running = false,
    this.cancelling = false,
    this.cancelled = false,
    this.failed = false,
    this.done = 0,
    this.total = 0,
    this.revision = 0,
  });
  final PdfOcrDocument? document;
  final bool running;
  final bool cancelling;
  final bool cancelled;
  final bool failed;
  final int done;
  final int total;
  final int revision;
}

/// Keyed by the immutable source path: aliases of one imported PDF share a job.
final readerOcrProvider = NotifierProvider.family<ReaderOcr, ReaderOcrState, String>(ReaderOcr.new);

class ReaderOcr extends Notifier<ReaderOcrState> {
  ReaderOcr(this.source);
  final String source;
  String? _job;
  Future<void>? _inspection;
  static int _serial = 0;

  @override
  ReaderOcrState build() {
    final service = ref.read(pdfOcrServiceProvider);
    ref.onDispose(() {
      if (_job case final id?) unawaited(service.cancel(id).catchError((Object _) {}));
    });
    return const ReaderOcrState();
  }

  Future<void> inspect() => _inspection ??= _inspect();
  Future<void> _inspect() async {
    final service = ref.read(pdfOcrServiceProvider);
    if (!service.supported) return;
    try {
      final document = await service.inspect(source);
      if (ref.mounted && !state.running) state = ReaderOcrState(document: document, revision: state.revision);
    } catch (_) {
      if (ref.mounted && !state.running) state = ReaderOcrState(document: state.document, failed: true);
      _inspection = null;
    }
  }

  Future<void> recognize(int first, int last, PdfOcrLanguage language) async {
    if (state.running) return;
    final service = ref.read(pdfOcrServiceProvider);
    if (!service.supported || first < 1 || last < first || last > (state.document?.pageCount ?? 0)) return;
    final id = _job = 'ocr-${++_serial}';
    final before = state;
    state = ReaderOcrState(
      document: before.document,
      running: true,
      total: last - first + 1,
      revision: before.revision,
    );
    try {
      final result = await service.recognize(
        source,
        id: id,
        first: first,
        last: last,
        language: language,
        onProgress: (done, total) {
          if (!ref.mounted || _job != id) return;
          state = ReaderOcrState(
            document: state.document,
            running: true,
            cancelling: state.cancelling,
            done: done,
            total: total,
            revision: state.revision,
          );
        },
      );
      if (!ref.mounted) return;
      state = ReaderOcrState(document: result.document, cancelled: result.cancelled, revision: before.revision + 1);
    } catch (_) {
      if (ref.mounted) state = ReaderOcrState(document: before.document, failed: true, revision: before.revision);
    } finally {
      _job = null;
    }
  }

  Future<void> cancel() async {
    final id = _job;
    if (id == null || state.cancelling) return;
    final before = state;
    state = ReaderOcrState(
      document: before.document,
      running: true,
      cancelling: true,
      done: before.done,
      total: before.total,
      revision: before.revision,
    );
    try {
      await ref.read(pdfOcrServiceProvider).cancel(id);
    } catch (_) {
      // A failed cancel leaves the current job running, so the reader remains
      // usable and cancellation can be retried.
      if (ref.mounted && _job == id && state.running) {
        state = ReaderOcrState(
          document: state.document,
          running: true,
          done: state.done,
          total: state.total,
          revision: state.revision,
        );
      }
    }
  }
}
