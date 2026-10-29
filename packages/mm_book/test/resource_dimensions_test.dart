import 'dart:convert';
import 'dart:typed_data';

import 'package:mm_book/mm_book.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

Uint8List gif(String version) {
  final b = Uint8List(13);
  magic(b, 0, version);
  ByteData.sublistView(b).setUint16(6, 300, Endian.little);
  ByteData.sublistView(b).setUint16(8, 200, Endian.little);
  return b;
}

Uint8List jpeg(int marker) => Uint8List.fromList([
  0xff, 0xd8, 0xff, 0xe0, 0, 4, 0, 0, // Skip APP metadata.
  0xff, 0xff, 0x01, // Fill byte and standalone marker.
  0xff, marker, 0, 11, 8, 0, 200, 1, 44, 1, 1, 0x11, 0,
]);

Uint8List webp(String chunk, List<int> payload, {bool unknownChunk = false}) {
  final b = Uint8List(20 + payload.length + (payload.length & 1) + (unknownChunk ? 10 : 0));
  magic(b, 0, 'RIFF');
  ByteData.sublistView(b).setUint32(4, b.length - 8, Endian.little);
  magic(b, 8, 'WEBP');
  var offset = 12;
  if (unknownChunk) {
    magic(b, offset, 'JUNK');
    ByteData.sublistView(b).setUint32(offset + 4, 1, Endian.little);
    offset += 10;
  }
  magic(b, offset, chunk);
  ByteData.sublistView(b).setUint32(offset + 4, payload.length, Endian.little);
  b.setRange(offset + 8, offset + 8 + payload.length, payload);
  return b;
}

Book resourceBook(Uint8List bytes, [String path = 'image.bin']) => Book('', [], {path: bytes}, []);

void main() {
  final lossless = Uint8List(5)..[0] = 0x2f;
  ByteData.sublistView(lossless).setUint32(1, 299 | (199 << 14), Endian.little);
  final samples = <String, Uint8List>{
    'png': pngImage(),
    'gif87': gif('GIF87a'),
    'gif89': gif('GIF89a'),
    'jpeg baseline': jpeg(0xc0),
    'jpeg progressive': jpeg(0xc2),
    'webp lossy': webp('VP8 ', [0, 0, 0, 0x9d, 1, 0x2a, 44, 1, 200, 0]),
    'webp lossless': webp('VP8L', lossless),
    'webp extended animation': webp('VP8X', [2, 0, 0, 0, 43, 1, 0, 199, 0, 0]),
    'webp unknown padded chunk': webp('VP8L', lossless, unknownChunk: true),
  };
  for (final entry in samples.entries) {
    test('${entry.key} dimensions come from bytes, independent of filename', () {
      final book = resourceBook(entry.value);
      final resource = book.resourceManifest.values.single;
      expect(resource.width, entry.key == 'png' ? 1 : 300);
      expect(resource.height, entry.key == 'png' ? 1 : 200);
      expect(resource.mime, startsWith('image/'));
      expect(book.diagnostics, isEmpty);
      expect((book.toJson()['resources'] as List).single, resource.toJson());
      expect(resource.sha256, hasLength(64));
      expect(resource.length, entry.value.length);
      final revision = book.revision;
      entry.value[0] = 0;
      expect(book.revision, revision);
      expect(() => book.resourceManifest.clear(), throwsUnsupportedError);
    });
  }

  final svgCases = <String, (double?, double?)>{
    '<svg width="300" height="200px"/>': (300, 200),
    '<svg viewBox="-1, -2, 300, 200"/>': (300, 200),
    '<svg width="150" viewBox="0 0 300 200"/>': (150, 100),
    '<svg height="100" viewBox="0 0 300 200"/>': (150, 100),
    '<svg width="100%" height="auto" viewBox="0 0 300 200"/>': (300, 200),
    '<svg width="2in" height="72pt" viewBox="0 0 1 1"/>': (192, 96),
    '<svg width="2.54cm" height="25.4mm"/>': (96, 96),
    '<svg width="6pc" height="101.6q"/>': (96, 96),
    '<svg width="+1.5e2px" height=".5e2"/>': (150, 50),
    '<svg width="300"/>': (300, null),
    '<svg height="200"/>': (null, 200),
    '<svg/>': (null, null),
    '<svg viewBox="0 0 0 200"/>': (null, null),
    '<svg viewBox="0 0 -1 200"/>': (null, null),
    '<svg viewBox="x y 300 200"/>': (null, null),
    '<svg width="1e999" height="-2"/>': (null, null),
    '<svg width="0" height="NaN"/>': (null, null),
    '<svg viewBox="0 0 300"/>': (null, null),
  };
  for (final entry in svgCases.entries) {
    test('SVG dimensions: ${entry.key}', () {
      final book = resourceBook(Uint8List.fromList(utf8.encode(entry.key)), 'image.svg');
      final resource = book.resourceManifest.values.single;
      expect(resource.width, entry.value.$1);
      expect(resource.height, entry.value.$2);
      expect(book.diagnostics.length, entry.value.$1 == null || entry.value.$2 == null ? 1 : 0);
      expect(resource.toJson().containsKey('width'), entry.value.$1 != null);
      expect(resource.toJson().containsKey('height'), entry.value.$2 != null);
    });
  }

  test('SVG XML declarations, namespaces and leading whitespace are recognized', () {
    final book = resourceBook(
      utf8.encode('\uFEFF <?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg" width="300" height="200"/>'),
    );
    expect(book.resourceManifest.values.single.width, 300);
    expect(book.diagnostics, isEmpty);
  });

  test('unreadable images produce one diagnostic each, without rejecting the book', () {
    final invalid = <String, Uint8List>{
      'empty.png': Uint8List(0),
      'truncated.jpg': Uint8List.fromList([255, 216, 255]),
      'invalid.gif': gif('GIF80a'),
      'broken.svg': utf8.encode('<svg width="3"'),
      'not-svg.svg': utf8.encode('<html/>'),
      'bad-utf8.svg': Uint8List.fromList([60, 115, 118, 103, 255]),
      'invalid.webp': webp('VP8L', [0, 0, 0, 0, 0]),
      'version.webp': webp('VP8L', [0x2f, 0, 0, 0, 0xe0]),
      'zero.gif': Uint8List.fromList([...ascii.encode('GIF89a'), ...List.filled(7, 0)]),
    };
    final book = Book('', [], invalid, ['Existing diagnostic']);
    expect(book.diagnostics.length, invalid.length + 1);
    expect(book.diagnostics.first, 'Existing diagnostic');
    for (final resource in book.resourceManifest.values) {
      expect(resource.width, isNull);
      expect(resource.height, isNull);
      expect(book.diagnostics, contains('Could not read image dimensions: ${resource.path}'));
    }
    book.toJson();
    book.toJson();
    expect(book.diagnostics.length, invalid.length + 1);
  });

  test('every truncated header is safe and JPEG/WebP segment lengths are bounded', () {
    // Make fresh samples: the metadata immutability tests mutate their inputs.
    final images = [pngImage(), gif('GIF89a'), jpeg(0xc2), webp('VP8L', lossless)];
    for (final image in images) {
      for (var length = 0; length < image.length; length++) {
        expect(() => resourceBook(Uint8List.sublistView(image, 0, length)).toJson(), returnsNormally);
      }
    }
    for (final bytes in [
      [255, 216, 255, 224, 0, 0],
      [255, 216, 255, 224, 255, 255],
      [255, 216, 255, 192, 0, 2],
      [255, 216, 255, 218, 0, 2],
      [255, 216, 255, 217],
      [255, 216, 255, 255],
      [255, 216, 255, 224, 0, 2, 0],
    ]) {
      final book = resourceBook(Uint8List.fromList(bytes), 'bad.jpg');
      expect(book.resourceManifest.values.single.width, isNull);
      expect(book.diagnostics, hasLength(1));
    }
    final oversized = webp('VP8L', lossless);
    ByteData.sublistView(oversized).setUint32(16, 0xffffffff, Endian.little);
    expect(resourceBook(oversized).diagnostics, hasLength(1));
  });

  test('non-images omit dimensions without diagnostic and resources stay sorted', () {
    final book = Book('', [], {'z.css': utf8.encode('p{}'), 'a.bin': Uint8List(0)}, []);
    expect(book.diagnostics, isEmpty);
    expect((book.toJson()['resources'] as List).map((r) => r['path']), ['a.bin', 'z.css']);
    expect(book.resourceManifest['z.css']!.toJson().keys, isNot(contains('width')));
  });

  test('EPUB, MOBI and Markdown expose dimensions before any JSON serialization', () async {
    final epub = const EpubParser().parse(richEpub(extra: {'OPS/image.png': pngImage()}));
    final mobiBook = const MobiParser().parse(mobi('<img recindex="1">', tail: [pngImage()]));
    final markdown = await const MarkdownBookParser().parse(
      utf8.encode('![alt](image.png)'),
      resolver: (_) async => pngImage(),
    );
    for (final book in [epub, mobiBook, markdown]) {
      final resource = book.resourceManifest.values.singleWhere((r) => r.mime == 'image/png');
      expect(resource.width, 1);
      expect(resource.height, 1);
      expect(book.diagnostics.where((d) => d.startsWith('Could not read image dimensions:')), isEmpty);
    }
  });
}
