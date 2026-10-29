import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

// Original 1x1 PNG, also usable by tests that assert successful image metadata.
Uint8List pngImage() =>
    base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=');

Uint8List contractEpub() => richEpub(
  chapter:
      '<style>section {margin:1em;padding:8px;background-color:#eee;text-align:center}</style>'
      '<section><h1 id="title">中文 😀</h1><p id="body">Hello <strong>world</strong>'
      '<ruby>漢<rt>kan</rt></ruby><img src="a.png"></p>'
      '<table><thead><tr><th>Head</th><td>Title</td></tr></thead>'
      '<tbody><tr><th>Row</th><td>cell</td></tr></tbody></table></section>',
  extra: {'OPS/a.png': pngImage()},
);

void u16(Uint8List b, int p, int v) => ByteData.sublistView(b).setUint16(p, v);
void u32(Uint8List b, int p, int v) => ByteData.sublistView(b).setUint32(p, v);
void magic(Uint8List b, int p, String s) => b.setRange(p, p + s.length, latin1.encode(s));
Uint8List zip(Map<String, List<int>> files) {
  final a = Archive();
  for (final e in files.entries) {
    a.addFile(ArchiveFile.bytes(e.key, e.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(a));
}

Uint8List richEpub({
  bool nav = true,
  String? encryption,
  String layout = '',
  String chapter = '<h1 id="title">Title</h1><p id="body">你好 😀</p>',
  String? manifest,
  Map<String, List<int>> extra = const {},
}) => zip({
  'META-INF/container.xml': utf8.encode(
    '<container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>',
  ),
  'OPS/book.opf': utf8.encode(
    '''<package unique-identifier="uid"><metadata><title>Sample</title><creator>Author</creator><identifier id="uid">urn:uuid:00112233-4455-6677-8899-aabbccddeeff</identifier><meta property="rendition:layout">$layout</meta></metadata><manifest>
  ${manifest ?? '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/><item id="font" href="font.otf" media-type="font/otf"/>'}
  <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="${nav ? 'nav' : ''}"/>
  <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/></manifest><spine toc="ncx"><itemref idref="c"/></spine></package>''',
  ),
  'OPS/c.xhtml': utf8.encode(chapter),
  'OPS/nav.xhtml': utf8.encode(
    '<nav epub:type="toc"><ol><li><a href="c.xhtml#title">Start</a><ol><li><a href="c.xhtml#body">Body</a></li></ol></li></ol></nav>',
  ),
  'OPS/toc.ncx': utf8.encode(
    '<ncx><navMap><navPoint id="start"><navLabel><text>Start NCX</text></navLabel><content src="c.xhtml#title"/><navPoint id="body"><navLabel><text>Body NCX</text></navLabel><content src="c.xhtml#body"/></navPoint></navPoint></navMap></ncx>',
  ),
  if (encryption != null) 'META-INF/encryption.xml': utf8.encode(encryption),
  ...extra,
});
Uint8List palm(List<Uint8List> records) {
  var offset = 80 + records.length * 8;
  final bytes = Uint8List(offset + records.fold(0, (n, r) => n + r.length));
  magic(bytes, 60, 'BOOKMOBI');
  u16(bytes, 76, records.length);
  for (var i = 0; i < records.length; i++) {
    u32(bytes, 78 + i * 8, offset);
    bytes.setRange(offset, offset + records[i].length, records[i]);
    offset += records[i].length;
  }
  return bytes;
}

Uint8List mobiHeader(
  int textSize, {
  int version = 6,
  int compression = 1,
  int encoding = 65001,
  int encryption = 0,
  int textCount = 1,
  int? boundary,
  int firstResource = 2,
  int? skel,
  int? frag,
  int? fdst,
  int flowCount = 1,
  int huffCount = 0,
  int flags = 0,
  int type = 2,
}) {
  final b = Uint8List(400);
  u16(b, 0, compression);
  u32(b, 4, textSize);
  u16(b, 8, textCount);
  u16(b, 10, 4096);
  u16(b, 12, encryption);
  magic(b, 16, 'MOBI');
  u32(b, 20, 264);
  u32(b, 24, type);
  u32(b, 28, encoding);
  u32(b, 36, version);
  u32(b, 0x54, 380);
  u32(b, 0x58, 4);
  magic(b, 380, 'Book');
  u32(b, 0x6c, firstResource);
  u32(b, 0x70, 2);
  u32(b, 0x74, huffCount);
  u32(b, 0xc0, fdst ?? 0xffffffff);
  u32(b, 0xc4, flowCount);
  u32(b, 0xf8, frag ?? 0xffffffff);
  u32(b, 0xfc, skel ?? 0xffffffff);
  u16(b, 0xf2, flags);
  u32(b, 0x80, 64);
  magic(b, 280, 'EXTH');
  final exth = <(int, List<int>)>[
    (100, utf8.encode('Author')),
    (503, utf8.encode('Title')),
    if (boundary != null) (121, (ByteData(4)..setUint32(0, boundary)).buffer.asUint8List()),
  ];
  var p = 292;
  for (final (tag, data) in exth) {
    u32(b, p, tag);
    u32(b, p + 4, 8 + data.length);
    b.setRange(p + 8, p + 8 + data.length, data);
    p += 8 + data.length;
  }
  u32(b, 284, p - 280);
  u32(b, 288, exth.length);
  return b;
}

Uint8List mobi(
  String source, {
  int compression = 1,
  int encoding = 65001,
  int encryption = 0,
  int version = 6,
  List<int>? compressed,
  List<Uint8List> tail = const [],
}) {
  final text = encoding == 65001 ? utf8.encode(source) : latin1.encode(source);
  return palm([
    mobiHeader(text.length, compression: compression, encoding: encoding, encryption: encryption, version: version),
    Uint8List.fromList(compressed ?? text),
    ...tail,
  ]);
}

List<int> vwi(int value) {
  final b = <int>[value & 127 | 128];
  while ((value >>= 7) > 0) {
    b.insert(0, value & 127);
  }
  return b;
}

List<Uint8List> indexRecords(List<(int, int, int, int)> tags, List<(String, List<int>)> entries) {
  final root = Uint8List(192 + 12 + tags.length * 4);
  magic(root, 0, 'INDX');
  u32(root, 4, 192);
  u32(root, 24, 1);
  magic(root, 192, 'TAGX');
  u32(root, 196, 12 + tags.length * 4);
  u32(root, 200, 1);
  for (var i = 0; i < tags.length; i++) {
    final t = tags[i];
    root.setRange(204 + i * 4, 208 + i * 4, [t.$1, t.$2, t.$3, t.$4]);
  }
  final body = <int>[];
  final offsets = <int>[];
  for (final e in entries) {
    offsets.add(192 + body.length);
    body.addAll([e.$1.length, ...utf8.encode(e.$1), ...e.$2]);
  }
  final end = 192 + body.length;
  final rec = Uint8List(end + 4 + entries.length * 2);
  magic(rec, 0, 'INDX');
  u32(rec, 4, 192);
  u32(rec, 20, end);
  u32(rec, 24, entries.length);
  rec.setRange(192, end, body);
  magic(rec, end, 'IDXT');
  for (var i = 0; i < offsets.length; i++) {
    u16(rec, end + 4 + i * 2, offsets[i]);
  }
  return [root, rec];
}

List<Uint8List> kf8Records({bool flows = true, bool badFragment = false, bool links = false}) {
  const skeleton = '<html><body><p></p></body></html>';
  final fragment =
      'Hello 😀<img src="kindle:embed:0001?mime=image/png"/>${links ? '<a href="kindle:pos:fid:0000:off:0000">Jump</a>' : ''}';
  final raw = utf8.encode(skeleton + fragment + (flows ? 'p {color: red}' : ''));
  final sk = indexRecords(
    [(1, 1, 1, 0), (6, 2, 2, 0)],
    [
      ('skel', [3, ...vwi(1), ...vwi(0), ...vwi(skeleton.length)]),
    ],
  );
  final fr = indexRecords(
    [(3, 1, 1, 0), (6, 2, 2, 0)],
    [
      (badFragment ? '999' : '15', [3, ...vwi(0), ...vwi(0), ...vwi(utf8.encode(fragment).length)]),
    ],
  );
  final fdst = Uint8List(28);
  magic(fdst, 0, 'FDST');
  u32(fdst, 4, 12);
  u32(fdst, 8, 2);
  u32(fdst, 12, 0);
  u32(fdst, 16, raw.length - 14);
  u32(fdst, 20, raw.length - 14);
  u32(fdst, 24, raw.length);
  // "p {color: red}" is 14 bytes.
  return [
    mobiHeader(raw.length, version: 8, skel: 2, frag: 4, fdst: 6, flowCount: flows ? 2 : 1, firstResource: 7),
    Uint8List.fromList(raw),
    ...sk,
    ...fr,
    fdst,
    Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
  ];
}

List<Uint8List> huffRecords(String phrase) {
  final h = Uint8List(1304);
  magic(h, 0, 'HUFF');
  u32(h, 4, 24);
  u32(h, 8, 24);
  u32(h, 12, 1048);
  // Every byte maps to literal phrase zero with an 8-bit code.
  for (var i = 0; i < 256; i++) {
    u32(h, 24 + i * 4, (i << 8) | 0x88);
  }
  final value = utf8.encode(phrase);
  final c = Uint8List(20 + value.length);
  magic(c, 0, 'CDIC');
  u32(c, 4, 16);
  u32(c, 8, 1);
  u32(c, 12, 1);
  u16(c, 16, 2);
  u16(c, 18, 0x8000 | value.length);
  c.setRange(20, c.length, value);
  return [h, c];
}
