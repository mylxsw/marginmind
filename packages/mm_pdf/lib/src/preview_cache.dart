import 'dart:typed_data';

/// Produces PNG bytes for a 1-based page and a physical-pixel width.
typedef MMPdfPreviewRenderer = Future<Uint8List?> Function(int page, int pixelWidth);

/// Document-scoped, bounded LRU for thumbnails. Requests share in-flight work
/// and run serially so a sidebar cannot flood PDFium with concurrent renders.
///
/// Returned bytes are read-only and remain valid after eviction. Call [clear]
/// when the document changes; old queued work is skipped and old results are
/// discarded. The owner must also clear before disposing the document.
class MMPdfPreviewCache {
  MMPdfPreviewCache({required this.render, this.maxBytes = 16 * 1024 * 1024}) {
    if (maxBytes <= 0) throw ArgumentError.value(maxBytes, 'maxBytes');
  }

  final MMPdfPreviewRenderer render;
  final int maxBytes;
  final _images = <(int, int), Uint8List>{};
  final _pending = <(int, int), Future<Uint8List?>>{};
  Future<void> _tail = Future.value();
  int _epoch = 0;
  int _bytes = 0;

  int get cachedBytes => _bytes;
  int get entryCount => _images.length;

  /// Width is rounded up to a 64px bucket (64–1024px). Caller supplies DPR.
  Future<Uint8List?> get(int page, {int pixelWidth = 160}) {
    if (page < 1) throw RangeError.range(page, 1, null, 'page');
    if (pixelWidth < 1 || pixelWidth > 1024) throw RangeError.range(pixelWidth, 1, 1024, 'pixelWidth');
    final width = ((pixelWidth + 63) ~/ 64) * 64;
    final key = (page, width);
    final cached = _images.remove(key);
    if (cached != null) {
      _images[key] = cached;
      return Future.value(cached);
    }
    final pending = _pending[key];
    if (pending != null) return pending;
    final epoch = _epoch;
    final result = _tail.then((_) async {
      if (epoch != _epoch) return null;
      final bytes = await render(page, width);
      if (epoch != _epoch || bytes == null) return null;
      final image = Uint8List.fromList(bytes).asUnmodifiableView();
      if (image.lengthInBytes <= maxBytes) {
        while (_bytes + image.lengthInBytes > maxBytes) {
          _bytes -= _images.remove(_images.keys.first)!.lengthInBytes;
        }
        _images[key] = image;
        _bytes += image.lengthInBytes;
      }
      return image;
    });
    _pending[key] = result;
    // Catch only on the queue tail: callers still receive rendering errors,
    // and a failed page cannot poison later requests.
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace stack) {}).whenComplete(() {
      if (epoch == _epoch) _pending.remove(key);
    });
    return result;
  }

  void clear() {
    _epoch++;
    _images.clear();
    _pending.clear();
    _bytes = 0;
  }
}
