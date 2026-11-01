part of '../mm_book.dart';

class MobiParser {
  const MobiParser({this.maxBytes = 64 * 1024 * 1024, this.maxRecords = 10000});
  final int maxBytes, maxRecords;
  Book parse(Uint8List bytes) => _guard(() => _parse(bytes));

  Book _parse(Uint8List bytes) {
    if (bytes.length > maxBytes) _limit();
    final pdb = _Binary(bytes);
    if (pdb.magic('CONT') ||
        pdb.magic('DRMION') ||
        pdb.magic('\u00eaDRMION\u00ee') ||
        pdb.magic('\u00e0\u0001\u0000\u00ea')) {
      _unsupported('KFX is not supported');
    }
    if (pdb.length < 78 || !(pdb.magic('BOOKMOBI', 60) || pdb.magic('TEXtREAd', 60))) {
      _damaged('Invalid PalmDB signature');
    }
    final count = pdb.u16(76);
    if (count > maxRecords) _limit();
    if (count == 0 || 78 + count * 8 + 2 > bytes.length) _damaged('Invalid PalmDB record table');
    final records = <Uint8List>[];
    var previous = 78 + count * 8 + 2;
    for (var i = 0; i < count; i++) {
      final start = pdb.u32(78 + i * 8), end = i + 1 == count ? bytes.length : pdb.u32(86 + i * 8);
      if (start < previous || end < start || end > bytes.length) _damaged('Overlapping PalmDB records');
      records.add(pdb.slice(start, end - start));
      previous = end;
    }
    var base = 0;
    var header = _MobiHeader(records.first);
    final legacyHeader = header;
    if (header.encryption != 0) throw const BookParseException(BookErrorKind.drm, 'MOBI uses DRM');
    final boundary = header.exth[121]?.firstOrNull;
    if (header.version < 8 && boundary != null) {
      final value = _Binary(boundary).u32(0);
      if (value != 0xffffffff) {
        if (value == 0 || value >= records.length || !_Binary(records[value - 1]).magic('BOUNDARY')) {
          _damaged('Invalid KF8 boundary');
        }
        base = value;
        header = _MobiHeader(records[base]);
        if (header.version != 8) _damaged('Invalid hybrid KF8 header');
        if (header.encryption != 0) throw const BookParseException(BookErrorKind.drm, 'KF8 uses DRM');
      }
    }
    if (header.version > 8) _unsupported('Unsupported MOBI version');
    final textCount = header.data.u16(8), textLength = header.data.u32(4);
    if (textLength > maxBytes) _limit();
    if (textCount == 0 || base + textCount >= records.length) _damaged('Missing MOBI text records');
    final compression = header.data.u16(0);
    _Huff? huff;
    if (compression == 0x4448) {
      final start = base + header.field(0x70), count = header.field(0x74);
      if (count < 2 || start < 0 || start + count > records.length) _damaged('Invalid HUFF record range');
      huff = _Huff(records.sublist(start, start + count), maxBytes);
    } else if (compression != 1 && compression != 2) {
      _unsupported('Unsupported MOBI compression');
    }
    final text = BytesBuilder(copy: false);
    for (var i = 1; i <= textCount; i++) {
      final record = _stripMobiTrailer(records[base + i], header.extraFlags);
      final data = compression == 1
          ? record
          : compression == 2
          ? _palmDoc(record, maxBytes)
          : huff!.decode(record);
      text.add(data);
      if (text.length > maxBytes) _limit();
    }
    final raw = text.takeBytes();
    // KF8 producers may count only the main markup flow in textLength.
    // Validate against the FDST below before accepting additional CSS flows.
    final hasFlows = header.version == 8 && header.field(0xc4) > 1 && header.field(0xc4) != 0xffffffff;
    if (!hasFlows && raw.length != textLength) _damaged('MOBI text length mismatch');
    if (_Binary(raw).magic('%MOP')) {
      final pdf = _printReplica(raw);
      return Book(header.title, [], {}, [], metadata: header.metadata, pdf: pdf);
    }
    if (header.type == 248) _damaged('AZW4 has no Print Replica payload');
    final resources = <String, Uint8List>{};
    var resourceBytes = 0;
    final resourceRanges = <(int, int)>[];
    if (base > 0) {
      var first = legacyHeader.field(0x6c);
      if (first == 0xffffffff) first = legacyHeader.data.u16(8) + 1;
      if (first > base - 1) _damaged('Invalid shared MOBI resource index');
      resourceRanges.add((first, base - 1));
    }
    var firstResource = header.field(0x6c);
    if (firstResource == 0xffffffff) firstResource = textCount + 1;
    if (base + firstResource > records.length) _damaged('Invalid MOBI resource index');
    resourceRanges.add((base + firstResource, records.length));
    var resourceOffset = 0;
    for (final (resourceStart, resourceEnd) in resourceRanges) {
      for (var i = resourceStart; i < resourceEnd; i++) {
        final data = records[i];
        final mime = _mime(data, '');
        if (mime.startsWith('image/')) {
          resourceBytes += data.length;
          if (resourceBytes + raw.length > maxBytes) _limit();
          resources['resource-${resourceOffset + i - resourceStart + 1}'] = data;
        }
        if (_Binary(data).magic('FONT')) {
          final font = _Binary(data);
          final flags = font.u32(8), start = font.u32(12), size = font.u32(4);
          if (size > maxBytes) _limit();
          var payload = Uint8List.fromList(font.slice(start, font.length - start));
          if ((flags & 2) != 0) {
            final keySize = font.u32(16), keyStart = font.u32(20);
            if (keySize == 0) _damaged('Empty MOBI font key');
            final key = font.slice(keyStart, keySize);
            for (var j = 0; j < payload.length && j < 1040; j++) {
              payload[j] ^= key[j % keySize];
            }
          }
          if ((flags & 1) != 0) payload = ZLibDecoder().decodeBytes(payload, maxOutputSize: size);
          if (payload.length != size) _damaged('Invalid MOBI font size');
          resourceBytes += payload.length;
          if (resourceBytes + raw.length > maxBytes) _limit();
          resources['resource-${resourceOffset + i - resourceStart + 1}'] = payload;
        }
      }
      resourceOffset += resourceEnd - resourceStart;
    }
    final diagnostics = <String>[];
    final parts = <Uint8List>[];
    final fragmentTargets = <int, (int, int)>{};
    if (header.version == 8) {
      var main = raw;
      final flowCount = header.field(0xc4);
      if (flowCount > 1 && flowCount != 0xffffffff) {
        final fdstIndex = base + header.field(0xc0);
        if (fdstIndex >= records.length) _damaged('Missing KF8 FDST');
        final fdst = _Binary(records[fdstIndex]);
        if (!fdst.magic('FDST') || fdst.u32(8) != flowCount) _damaged('Invalid KF8 FDST');
        var last = 0;
        for (var n = 0; n < flowCount; n++) {
          final start = fdst.u32(12 + n * 8), end = fdst.u32(16 + n * 8);
          if (start != last || end < start || end > raw.length) _damaged('Invalid KF8 flow bounds');
          final flow = Uint8List.sublistView(raw, start, end);
          if (n == 0) {
            main = flow;
          } else {
            resources['flow-$n'] = flow;
          }
          last = end;
        }
        if (last != raw.length) _damaged('Unaccounted KF8 flow data');
        if (textLength != raw.length && textLength != main.length) _damaged('MOBI text length mismatch');
      }
      final skel = header.field(0xfc), frag = header.field(0xf8);
      if (skel == 0xffffffff) _unsupported('KF8 without skeleton index');
      final skeletons = _mobiIndex(records, base + skel);
      final fragments = frag == 0xffffffff ? <_IndexEntry>[] : _mobiIndex(records, base + frag);
      var nextFragment = 0;
      for (final skeleton in skeletons) {
        final pos = skeleton.value(6), length = skeleton.value(6, 1);
        var assembled = _Binary(main).slice(pos, length).toList();
        var source = pos + length;
        for (var i = 0; i < skeleton.value(1); i++) {
          if (nextFragment >= fragments.length) _damaged('Missing KF8 fragment');
          final f = fragments[nextFragment];
          final insert = int.tryParse(f.label);
          if (insert == null || insert < pos || insert - pos > assembled.length || f.value(3) != parts.length) {
            _damaged('Invalid KF8 fragment position');
          }
          final size = f.value(6, 1);
          final piece = _Binary(main).slice(source, size);
          fragmentTargets[nextFragment] = (parts.length, insert - pos);
          assembled.insertAll(insert - pos, piece);
          source += size;
          nextFragment++;
          if (assembled.length > maxBytes) _limit();
        }
        parts.add(Uint8List.fromList(assembled));
      }
      if (parts.isEmpty || nextFragment != fragments.length) _damaged('Invalid KF8 skeleton/fragment counts');
    } else {
      parts.add(raw);
    }
    // filepos and KF8 links refer to bytes, before character decoding or HTML normalization.
    final targets = <int, Set<int>>{};
    for (var n = 0; n < parts.length; n++) {
      final source = latin1.decode(parts[n]);
      for (final m in RegExp(r'''filepos\s*=\s*["']?(\d+)''', caseSensitive: false).allMatches(source)) {
        targets.putIfAbsent(0, () => {}).add(int.parse(m[1]!));
      }
      for (final m in RegExp(r'kindle:pos:fid:([0-9A-V]+):off:([0-9A-V]+)', caseSensitive: false).allMatches(source)) {
        final f = int.parse(m[1]!, radix: 32), off = int.parse(m[2]!, radix: 32);
        final target = fragmentTargets[f];
        if (target == null) _damaged('Unresolved KF8 position link');
        targets.putIfAbsent(target.$1, () => {}).add(target.$2 + off);
      }
    }
    final chapters = <BookChapter>[];
    for (var n = 0; n < parts.length; n++) {
      var source = latin1.decode(parts[n]);
      for (final position in (targets[n]?.toList() ?? [])..sort((a, b) => b.compareTo(a))) {
        if (position < 0 || position > source.length) _damaged('Link outside MOBI text');
        // Anchor immediately before the element containing the byte position.
        var at = position;
        final open = source.lastIndexOf('<', (position - 1).clamp(0, source.length));
        final close = source.lastIndexOf('>', (position - 1).clamp(0, source.length));
        if (open > close) at = open;
        source = '${source.substring(0, at)}<a id="pos-$position"></a>${source.substring(at)}';
      }
      source = source.replaceAllMapped(
        RegExp(r'''filepos\s*=\s*["']?(\d+)["']?''', caseSensitive: false),
        (m) => 'href="part-0.xhtml#pos-${int.parse(m[1]!)}"',
      );
      source = source.replaceAllMapped(RegExp(r'kindle:pos:fid:([0-9A-V]+):off:([0-9A-V]+)', caseSensitive: false), (
        m,
      ) {
        final t = fragmentTargets[int.parse(m[1]!, radix: 32)]!;
        return 'part-${t.$1}.xhtml#pos-${t.$2 + int.parse(m[2]!, radix: 32)}';
      });
      source = source.replaceAllMapped(
        RegExp(r'''recindex\s*=\s*["']?(\d+)["']?''', caseSensitive: false),
        (m) => 'src="resource-${int.parse(m[1]!)}"',
      );
      source = source.replaceAllMapped(
        RegExp(r'kindle:embed:([0-9A-V]+)(?:\?[^\s"\x27<>]*)?', caseSensitive: false),
        (m) => 'resource-${int.parse(m[1]!, radix: 32)}',
      );
      source = source.replaceAllMapped(
        RegExp(r'kindle:flow:([0-9A-V]+)(?:\?[^\s"\x27<>]*)?', caseSensitive: false),
        (m) => 'flow-${int.parse(m[1]!, radix: 32)}',
      );
      final decoded = header.decode(latin1.encode(source));
      final document = html.parse(decoded);
      for (final link in document.querySelectorAll('link[rel="stylesheet"]')) {
        final resource = resources[link.attributes['href']];
        if (resource == null) {
          diagnostics.add('Missing MOBI stylesheet');
          continue;
        }
        link.replaceWith(
          dom.Element.tag('style')
            ..attributes['data-mm-source'] = link.attributes['href'] ?? ''
            ..text = header.decode(resource),
        );
      }
      chapters.add(const EpubParser().parseHtml('part-$n.xhtml', document.outerHtml, diagnostics));
    }
    return Book(header.title, chapters, resources, diagnostics, metadata: header.metadata);
  }
}

class _MobiHeader {
  _MobiHeader(Uint8List bytes) : data = _Binary(bytes) {
    if (data.length < 16) _damaged('Truncated PalmDOC header');
    encryption = data.u16(12);
    if (encryption != 0) return;
    if (!data.magic('MOBI', 16)) _unsupported('PalmDOC without MOBI header');
    final length = data.u32(20);
    if (length < 0x74 || length + 16 > data.length) _damaged('Invalid MOBI header length');
    headerEnd = length + 16;
    type = data.u32(24);
    encoding = data.u32(28);
    version = data.u32(36);
    if (encoding != 65001 && encoding != 1252) _unsupported('Unsupported MOBI encoding');
    title = decode(data.slice(data.u32(0x54), data.u32(0x58)));
    if ((field(0x80, fallback: 0) & 64) != 0) {
      final start = headerEnd;
      if (!data.magic('EXTH', start)) _damaged('Missing EXTH header');
      final end = start + data.u32(start + 4), count = data.u32(start + 8);
      if (end > data.length || end < start + 12 || count > (end - start - 12) ~/ 8) _damaged('Invalid EXTH length');
      var p = start + 12;
      for (var i = 0; i < count; i++) {
        final tag = data.u32(p), length = data.u32(p + 4);
        if (length < 8 || p + length > end) _damaged('Invalid EXTH record');
        exth.putIfAbsent(tag, () => []).add(data.slice(p + 8, length - 8));
        p += length;
      }
      final updatedTitle = exth[503]?.firstOrNull;
      if (updatedTitle != null) title = decode(updatedTitle);
    }
    extraFlags = headerEnd >= 0xf4 ? data.u16(0xf2) : 0;
  }
  final _Binary data;
  int encryption = 0, version = 0, encoding = 65001, type = 0, headerEnd = 0, extraFlags = 0;
  String title = '';
  final exth = <int, List<Uint8List>>{};
  int field(int offset, {int fallback = 0xffffffff}) => offset + 4 <= headerEnd ? data.u32(offset) : fallback;
  Map<String, List<String>> get metadata => {
    'title': [title],
    for (final e in {100: 'creator', 101: 'publisher', 103: 'description', 104: 'identifier', 524: 'language'}.entries)
      if (exth[e.key] case final List<Uint8List> values) e.value: values.map(decode).toList(),
  };
  String decode(List<int> bytes) {
    if (encoding == 65001) return utf8.decode(bytes);
    const high = '€\u0081‚ƒ„…†‡ˆ‰Š‹Œ\u008dŽ\u008f\u0090‘’“”•–—˜™š›œ\u009džŸ';
    return String.fromCharCodes(bytes.map((b) => b >= 128 && b < 160 ? high.codeUnitAt(b - 128) : b));
  }
}

Uint8List _printReplica(Uint8List bytes) {
  final b = _Binary(bytes);
  final types = b.u32(4);
  if (types == 0 || types > 1000) _damaged('Invalid Print Replica type count');
  final counts = [for (var i = 0; i < types; i++) b.u32(8 + i * 4)];
  final total = counts.fold(0, (a, c) => a + c);
  if (total > 10000) _damaged('Invalid Print Replica section count');
  Uint8List? pdf;
  var p = 8 + types * 4;
  for (var i = 0; i < total; i++, p += 8) {
    final payload = b.slice(b.u32(p), b.u32(p + 4));
    if (_Binary(payload).magic('%PDF-')) {
      if (pdf != null) _unsupported('Print Replica with multiple PDFs');
      pdf = Uint8List.fromList(payload);
    }
  }
  return pdf ?? _damaged('Print Replica PDF missing');
}
