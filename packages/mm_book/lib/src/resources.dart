part of '../mm_book.dart';

/// Content-derived resource metadata. Image dimensions are pixels (CSS px for
/// SVG), independent of the image's authored display size in a chapter.
class BookResource {
  const BookResource._(this.path, this.sha256, this.length, this.mime, this.width, this.height);
  final String path, sha256, mime;
  final int length;
  final double? width, height;
  Map<String, Object> toJson() => {
    'path': path,
    'sha256': sha256,
    'length': length,
    'mime': mime,
    'width': ?width,
    'height': ?height,
  };
}

class _BookResources {
  _BookResources(Map<String, Uint8List> resources, List<String> issues)
    : bytes = Map.unmodifiable(resources.map((k, v) => MapEntry(k, Uint8List.fromList(v).asUnmodifiableView()))) {
    final descriptions = <String, BookResource>{};
    final messages = [...issues];
    for (final entry in bytes.entries) {
      final mime = _mime(entry.value, entry.key);
      final (width, height) = _imageSize(entry.value, mime);
      descriptions[entry.key] = BookResource._(
        entry.key,
        sha256.convert(entry.value).toString(),
        entry.value.length,
        mime,
        width,
        height,
      );
      if ((mime.startsWith('image/') ||
              RegExp(r'\.(png|jpe?g|gif|webp|svg)$', caseSensitive: false).hasMatch(entry.key)) &&
          (width == null || height == null)) {
        messages.add('Could not read image dimensions: ${entry.key}');
      }
    }
    manifest = Map.unmodifiable(descriptions);
    diagnostics = List.unmodifiable(messages);
  }
  final Map<String, Uint8List> bytes;
  late final Map<String, BookResource> manifest;
  late final List<String> diagnostics;
}

/// Header inspection only: no pixel allocation, decompression or platform API.
(double?, double?) _imageSize(Uint8List bytes, String mime) {
  final data = ByteData.sublistView(bytes);
  bool at(int offset, List<int> signature) =>
      offset + signature.length <= bytes.length &&
      List.generate(signature.length, (i) => bytes[offset + i] == signature[i]).every((v) => v);
  (double?, double?) size(int width, int height) =>
      (width > 0 ? width.toDouble() : null, height > 0 ? height.toDouble() : null);
  switch (mime) {
    case 'image/png':
      if (bytes.length >= 33 &&
          at(0, [137, 80, 78, 71, 13, 10, 26, 10]) &&
          data.getUint32(8) == 13 &&
          at(12, ascii.encode('IHDR'))) {
        return size(data.getUint32(16), data.getUint32(20));
      }
    case 'image/gif':
      if (bytes.length >= 13 && (at(0, ascii.encode('GIF87a')) || at(0, ascii.encode('GIF89a')))) {
        return size(data.getUint16(6, Endian.little), data.getUint16(8, Endian.little));
      }
    case 'image/jpeg':
      var offset = 2;
      while (offset < bytes.length) {
        if (bytes[offset++] != 0xff) break;
        while (offset < bytes.length && bytes[offset] == 0xff) {
          offset++;
        }
        if (offset >= bytes.length) break;
        final marker = bytes[offset++];
        if (marker == 0xd9 || marker == 0xda) break; // EOI / scan data.
        if (marker == 0x01 || marker >= 0xd0 && marker <= 0xd8) continue;
        if (offset + 2 > bytes.length) break;
        final length = data.getUint16(offset);
        if (length < 2 || offset + length > bytes.length) break;
        // SOF markers excluding DHT, JPG and DAC; baseline and progressive.
        if (marker >= 0xc0 && marker <= 0xcf && !const {0xc4, 0xc8, 0xcc}.contains(marker)) {
          if (length < 8 || length != 8 + 3 * bytes[offset + 7]) break;
          return size(data.getUint16(offset + 5), data.getUint16(offset + 3));
        }
        offset += length;
      }
    case 'image/webp':
      if (bytes.length < 12) break;
      final end = data.getUint32(4, Endian.little) + 8;
      if (end > bytes.length || end < 12) break;
      var offset = 12;
      int u24(int p) => bytes[p] | bytes[p + 1] << 8 | bytes[p + 2] << 16;
      while (offset + 8 <= end) {
        final length = data.getUint32(offset + 4, Endian.little);
        final start = offset + 8;
        if (start + length + (length & 1) > end) break;
        if (at(offset, ascii.encode('VP8X')) && length == 10) {
          return size(1 + u24(start + 4), 1 + u24(start + 7));
        }
        if (at(offset, ascii.encode('VP8L')) && length >= 5 && bytes[start] == 0x2f) {
          final bits = data.getUint32(start + 1, Endian.little);
          if (bits >> 29 != 0) break; // Unsupported lossless version.
          return size(1 + (bits & 0x3fff), 1 + ((bits >> 14) & 0x3fff));
        }
        if (at(offset, ascii.encode('VP8 ')) &&
            length >= 10 &&
            bytes[start] & 1 == 0 &&
            at(start + 3, [0x9d, 0x01, 0x2a])) {
          return size(
            data.getUint16(start + 6, Endian.little) & 0x3fff,
            data.getUint16(start + 8, Endian.little) & 0x3fff,
          );
        }
        offset = start + length + (length & 1);
      }
    case 'image/svg+xml':
      return _svgSize(bytes);
  }
  return (null, null);
}

(double?, double?) _svgSize(Uint8List bytes) {
  // MIME validation already checked XML. The XML library never fetches entities.
  final root = XmlDocument.parse(utf8.decode(bytes)).rootElement;
  double? positive(double? n) => n != null && n.isFinite && n > 0 ? n : null;
  double? length(String? value) {
    final match = RegExp(r'^\s*([+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)\s*(px|in|cm|mm|q|pt|pc)?\s*$')
        .firstMatch(value ?? '');
    if (match == null) return null;
    final scale = switch (match[2]) {
      'in' => 96.0,
      'cm' => 96 / 2.54,
      'mm' => 96 / 25.4,
      'q' => 96 / 101.6,
      'pt' => 96 / 72,
      'pc' => 16.0,
      _ => 1.0,
    };
    return positive(double.tryParse(match[1]!)! * scale);
  }

  var width = length(root.getAttribute('width')), height = length(root.getAttribute('height'));
  final viewBox = (root.getAttribute('viewBox') ?? '').trim().split(RegExp(r'[\s,]+'));
  if (viewBox.length == 4) {
    final values = viewBox.map(double.tryParse).toList();
    final w = positive(values[2]), h = positive(values[3]);
    if (values.every((v) => v != null && v.isFinite) && w != null && h != null) {
      if (width == null && height == null) {
        width = w;
        height = h;
      } else if (width == null) {
        width = positive(height! * w / h);
      } else {
        height ??= positive(width * h / w);
      }
    }
  }
  return (width, height);
}
