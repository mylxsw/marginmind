part of '../mm_book.dart';

/// Bounds-checked big-endian reader used for every PalmDB subrecord.
class _Binary {
  _Binary(this.bytes);
  final Uint8List bytes;
  int get length => bytes.length;
  int u8(int offset) => bytes[offset];
  int u16(int offset) => ByteData.sublistView(bytes).getUint16(offset);
  int u32(int offset) => ByteData.sublistView(bytes).getUint32(offset);
  Uint8List slice(int start, int size) => Uint8List.sublistView(bytes, start, start + size);
  bool magic(String value, [int at = 0]) =>
      at >= 0 &&
      at + value.length <= length &&
      List.generate(value.length, (i) => bytes[at + i] == value.codeUnitAt(i)).every((v) => v);
}

Uint8List _palmDoc(Uint8List input, int limit) {
  final out = <int>[];
  for (var pos = 0; pos < input.length;) {
    final c = input[pos++];
    if (c >= 1 && c <= 8) {
      if (pos + c > input.length) _damaged('Truncated PalmDOC literal');
      out.addAll(input.sublist(pos, pos + c));
      pos += c;
    } else if (c < 128) {
      out.add(c);
    } else if (c >= 192) {
      out.addAll([32, c ^ 128]);
    } else {
      if (pos == input.length) _damaged('Truncated PalmDOC backreference');
      final pair = (c << 8) | input[pos++];
      final distance = (pair >> 3) & 2047;
      if (distance == 0 || distance > out.length) _damaged('Invalid PalmDOC backreference');
      final count = (pair & 7) + 3;
      for (var i = 0; i < count; i++) {
        out.add(out[out.length - distance]);
      }
    }
    if (out.length > limit) _limit();
  }
  return Uint8List.fromList(out);
}

class _Huff {
  _Huff(List<Uint8List> records, this.limit) {
    if (records.length < 2) _damaged('Missing HUFF/CDIC records');
    final h = _Binary(records.first);
    if (!h.magic('HUFF') || h.u32(4) != 24) _damaged('Invalid HUFF header');
    final fast = h.u32(8), slow = h.u32(12);
    for (var i = 0; i < 256; i++) {
      final word = h.u32(fast + i * 4);
      final bits = word & 31;
      final terminal = (word & 128) != 0;
      if (bits == 0 || (bits <= 8 && !terminal)) _damaged('Invalid HUFF code length');
      table.add((bits, terminal, ((word ~/ 256 + 1) * _power2(32 - bits)) - 1));
    }
    for (var bits = 1; bits <= 32; bits++) {
      min.add(h.u32(slow + (bits - 1) * 8) * _power2(32 - bits));
      max.add(((h.u32(slow + (bits - 1) * 8 + 4) + 1) * _power2(32 - bits)) - 1);
    }
    int? expected;
    for (final record in records.skip(1)) {
      final c = _Binary(record);
      if (!c.magic('CDIC') || c.u32(4) != 16) _damaged('Invalid CDIC header');
      final total = c.u32(8), bits = c.u32(12);
      if (bits > 16 || total > 1000000 || (expected != null && total != expected)) _damaged('Invalid CDIC size');
      expected = total;
      final count = (total - phrases.length).clamp(0, 1 << bits);
      for (var i = 0; i < count; i++) {
        final offset = 16 + c.u16(16 + i * 2);
        final size = c.u16(offset);
        phrases.add(c.slice(offset + 2, size & 0x7fff));
        literal.add((size & 0x8000) != 0);
      }
    }
    if (phrases.length != expected) _damaged('Incomplete CDIC dictionary');
  }
  final int limit;
  final table = <(int, bool, int)>[];
  final min = <int>[0], max = <int>[0];
  final phrases = <Uint8List>[];
  final literal = <bool>[];
  final active = <int>{};
  int _work = 0, _expandedBytes = 0;

  Uint8List decode(Uint8List data, [int depth = 0]) {
    if (depth > 64) _damaged('Recursive HUFF dictionary');
    final out = BytesBuilder(copy: false);
    var bit = 0;
    while (bit < data.length * 8) {
      if (++_work > limit * 8) _limit();
      var word = 0;
      // Five byte window with zero padding, valid on both VM and JS integers.
      for (var i = 0; i < 32; i++) {
        final p = bit + i;
        word = word * 2 + (p < data.length * 8 ? (data[p ~/ 8] >> (7 - p % 8)) & 1 : 0);
      }
      var (bits, terminal, ceiling) = table[word ~/ 0x1000000];
      if (!terminal) {
        while (bits <= 32 && word < min[bits]) {
          bits++;
        }
        if (bits > 32) _damaged('Invalid HUFF code');
        ceiling = max[bits];
      }
      if (bit + bits > data.length * 8) break; // terminal padding
      bit += bits;
      if (ceiling < word) _damaged('Invalid HUFF ceiling');
      final index = (ceiling - word) ~/ _power2(32 - bits);
      if (index < 0 || index >= phrases.length) _damaged('HUFF phrase outside dictionary');
      if (!literal[index]) {
        if (!active.add(index)) _damaged('Cyclic HUFF dictionary');
        phrases[index] = decode(phrases[index], depth + 1);
        _expandedBytes += phrases[index].length;
        if (_expandedBytes > limit) _limit();
        active.remove(index);
        literal[index] = true;
      }
      out.add(phrases[index]);
      if (out.length > limit) _limit();
    }
    return out.takeBytes();
  }
}

Uint8List _stripMobiTrailer(Uint8List data, int flags) {
  var end = data.length;
  for (var mask = flags >> 1; mask != 0; mask >>= 1) {
    if ((mask & 1) == 0) continue;
    var size = 0, shift = 0;
    var pos = end;
    while (true) {
      if (pos == 0 || shift >= 28) _damaged('Invalid MOBI trailer');
      final c = data[--pos];
      size += (c & 127) << shift;
      if ((c & 128) != 0) break;
      shift += 7;
    }
    if (size == 0 || size > end) _damaged('Invalid MOBI trailer length');
    end -= size;
  }
  if ((flags & 1) != 0) {
    if (end == 0) _damaged('Missing multibyte trailer');
    end -= (data[end - 1] & 3) + 1;
    if (end < 0) _damaged('Invalid multibyte trailer');
  }
  return Uint8List.sublistView(data, 0, end);
}

int _power2(int exponent) => exponent == 32 ? 0x100000000 : 1 << exponent;
