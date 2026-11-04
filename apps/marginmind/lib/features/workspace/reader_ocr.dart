import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:mm_core/mm_core.dart';

import '../../app/providers.dart';
import 'document_resources.dart';

typedef ReaderOcrSource = (String, DocumentResourceKey?);
ReaderOcrSource documentOcrSource(String set, Document doc, String path) => (path, documentResourceKey(set, doc));

final pdfOcrServiceProvider = Provider<PdfOcrService>((ref) => VisionPdfOcr());

final readerOcrInspectionProvider = FutureProvider.autoDispose.family<void, ReaderOcrSource>((ref, source) {
  ref.watch(readerOcrProvider(source).select((s) => s.unavailable));
  return ref.read(readerOcrProvider(source).notifier).inspect();
});

class ReaderOcrState {
  const ReaderOcrState({
    this.document,
    this.unavailable,
    this.running = false,
    this.cancelling = false,
    this.cancelled = false,
    this.failed = false,
    this.done = 0,
    this.total = 0,
    this.revision = 0,
  });
  final PdfOcrDocument? document;
  final DocumentResourceAvailability? unavailable;
  final bool running;
  final bool cancelling;
  final bool cancelled;
  final bool failed;
  final int done;
  final int total;
  final int revision;
}

/// A document version owns its results; a reused path must not reuse old OCR.
final readerOcrProvider = NotifierProvider.autoDispose.family<ReaderOcr, ReaderOcrState, ReaderOcrSource>(
  ReaderOcr.new,
);

class ReaderOcr extends Notifier<ReaderOcrState> {
  ReaderOcr(this.source);
  final ReaderOcrSource source;
  int _generation = 0;
  bool _guarding = false;
  var _resourceReady = Completer<void>();
  DocumentResourceAvailability _availability = DocumentResourceAvailability.ready;
  String? _job;
  Future<void>? _inspection;
  static int _serial = 0;

  @override
  ReaderOcrState build() {
    _resourceReady = Completer<void>();
    _inspection = null;
    _job = null;
    _guarding = false;
    _availability = DocumentResourceAvailability.ready;
    final service = ref.read(pdfOcrServiceProvider);
    ref.onDispose(() {
      _generation++;
      if (!_resourceReady.isCompleted) _resourceReady.complete();
      if (_job case final id?) unawaited(service.cancel(id).catchError((Object _) {}));
    });
    return const ReaderOcrState();
  }

  void _startGuards() {
    if (_guarding) return;
    _guarding = true;
    if (source.$2 case final key?) {
      final repository = ref.read(contentRepositoryProvider);
      // These guards must remain live while an operation has no visible widget.
      // Riverpod can pause dependencies of an unobserved family instance.
      final contents = repository.watch(key.$1).listen((content) {
        final doc = content.document(key.$2);
        if (doc == null || documentResourceKey(key.$1, doc) != key) {
          _invalidate(DocumentResourceAvailability.changed);
        }
      }, onError: (Object _) => _invalidate(DocumentResourceAvailability.changed));
      ref.onDispose(() => unawaited(contents.cancel()));
      if (repository is DocumentResourceRepository) {
        final resources = (repository as DocumentResourceRepository)
            .watchDocumentResources(key.$1, key.$2)
            .listen(
              (value) {
                _availability = value;
                if (!_resourceReady.isCompleted) _resourceReady.complete();
                if (value != DocumentResourceAvailability.ready) {
                  _invalidate(value);
                } else if (state.unavailable != null) {
                  _inspection = null;
                  state = const ReaderOcrState();
                }
              },
              onError: (Object _) {
                _availability = DocumentResourceAvailability.changed;
                if (!_resourceReady.isCompleted) _resourceReady.complete();
                _invalidate(_availability);
              },
            );
        ref.onDispose(() => unawaited(resources.cancel()));
      } else {
        _resourceReady.complete();
      }
    } else {
      _resourceReady.complete();
    }
  }

  void _invalidate(DocumentResourceAvailability reason) {
    if (!ref.mounted) return;
    _generation++;
    _inspection = null;
    final id = _job;
    _job = null;
    if (id != null) unawaited(ref.read(pdfOcrServiceProvider).cancel(id).catchError((Object _) {}));
    state = ReaderOcrState(unavailable: reason);
  }

  Future<bool> _available(int generation) async {
    _startGuards();
    final key = source.$2;
    if (key == null) return ref.mounted && generation == _generation;
    try {
      await _resourceReady.future;
      final availability = _availability;
      if (!ref.mounted || generation != _generation) return false;
      final content = await ref.read(contentRepositoryProvider).load(key.$1);
      if (!ref.mounted || generation != _generation) return false;
      final doc = content.document(key.$2);
      if (availability != DocumentResourceAvailability.ready ||
          doc == null ||
          documentResourceKey(key.$1, doc) != key) {
        _invalidate(
          availability == DocumentResourceAvailability.ready ? DocumentResourceAvailability.changed : availability,
        );
        return false;
      }
      return true;
    } catch (_) {
      if (ref.mounted && generation == _generation) _invalidate(DocumentResourceAvailability.changed);
      return false;
    }
  }

  Future<void> requireAvailable() async {
    final hold = ref.keepAlive();
    try {
      if (!await _available(_generation)) {
        throw const DocumentResourcesUnavailable(DocumentResourceAvailability.changed);
      }
    } finally {
      hold.close();
    }
  }

  Future<void> inspect() {
    if (_inspection case final task?) return task;
    final hold = ref.keepAlive();
    return _inspection = _inspect(_generation).whenComplete(hold.close);
  }

  Future<void> _inspect(int generation) async {
    final service = ref.read(pdfOcrServiceProvider);
    if (!service.supported || !await _available(generation)) return;
    try {
      final document = await service.inspect(source.$1);
      if (!await _available(generation)) return;
      if (ref.mounted && generation == _generation && !state.running) {
        state = ReaderOcrState(document: document, revision: state.revision);
      }
    } catch (_) {
      if (ref.mounted && generation == _generation) {
        if (!state.running) state = ReaderOcrState(document: state.document, failed: true);
        _inspection = null;
      }
    }
  }

  Future<void> recognize(int first, int last, PdfOcrLanguage language) async {
    if (state.running) return;
    final service = ref.read(pdfOcrServiceProvider);
    if (!service.supported || first < 1 || last < first || last > (state.document?.pageCount ?? 0)) return;
    final hold = ref.keepAlive();
    final generation = _generation;
    final id = _job = 'ocr-${++_serial}';
    final before = state;
    state = ReaderOcrState(
      document: before.document,
      running: true,
      total: last - first + 1,
      revision: before.revision,
    );
    try {
      if (!await _available(generation) || _job != id) return;
      final result = await service.recognize(
        source.$1,
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
      if (!ref.mounted || generation != _generation || _job != id) return;
      if (!await _available(generation) || _job != id) return;
      state = ReaderOcrState(document: result.document, cancelled: result.cancelled, revision: before.revision + 1);
    } catch (_) {
      if (ref.mounted && generation == _generation && _job == id) {
        state = ReaderOcrState(document: before.document, failed: true, revision: before.revision);
      }
    } finally {
      if (_job == id) _job = null;
      hold.close();
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
