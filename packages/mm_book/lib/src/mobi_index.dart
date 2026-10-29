part of '../mm_book.dart';

class _IndexEntry {
  _IndexEntry(this.label, this.tags);
  final String label;
  final Map<int, List<int>> tags;
  int value(int tag, [int n = 0]) {
    final values = tags[tag];
    if (values == null || n >= values.length) _damaged('Missing KF8 index tag');
    return values[n];
  }
}

List<_IndexEntry> _mobiIndex(List<Uint8List> records, int index) {
  if (index < 0 || index >= records.length) _damaged('Invalid KF8 index record');
  final root = _Binary(records[index]);
  if (!root.magic('INDX')) _damaged('Missing KF8 INDX');
  final tagStart = root.u32(4), count = root.u32(24);
  if (!root.magic('TAGX', tagStart)) _damaged('Missing KF8 TAGX');
  final tagLength = root.u32(tagStart + 4), controls = root.u32(tagStart + 8);
  if (controls == 0 || controls > 32 || tagLength < 12 || (tagLength - 12) % 4 != 0) _damaged('Invalid TAGX');
  final tags = <(int, int, int, int)>[];
  for (var p = tagStart + 12; p < tagStart + tagLength; p += 4) {
    tags.add((root.u8(p), root.u8(p + 1), root.u8(p + 2), root.u8(p + 3)));
  }
  final result = <_IndexEntry>[];
  if (count > records.length - index - 1) _damaged('Truncated INDX records');
  for (var n = 1; n <= count; n++) {
    final record = _Binary(records[index + n]);
    if (!record.magic('INDX')) _damaged('Missing INDX data');
    final end = record.u32(20), entries = record.u32(24);
    if (!record.magic('IDXT', end)) _damaged('Missing IDXT');
    for (var i = 0; i < entries; i++) {
      final start = record.u16(end + 4 + i * 2);
      final stop = i + 1 < entries ? record.u16(end + 6 + i * 2) : end;
      if (start >= stop || stop > end) _damaged('Invalid INDX entry bounds');
      final textLength = record.u8(start);
      final control = start + 1 + textLength;
      var p = control + controls;
      if (p > stop) _damaged('Truncated INDX control');
      int variable() {
        var v = 0;
        for (var j = 0; j < 5 && p < stop; j++) {
          final b = record.u8(p++);
          v = v * 128 + (b & 127);
          if ((b & 128) != 0) return v;
        }
        return _damaged('Unterminated INDX integer');
      }

      final specs = <(int, int, int?)>[];
      var controlIndex = 0;
      for (final (tag, per, mask, finish) in tags) {
        if (finish == 1) {
          controlIndex++;
          continue;
        }
        if (controlIndex >= controls || mask == 0 || per == 0) _damaged('Invalid TAGX mask');
        var v = record.u8(control + controlIndex) & mask;
        if (v == 0) continue;
        if (v == mask && (mask & (mask - 1)) != 0) {
          specs.add((tag, per, variable()));
        } else {
          var m = mask;
          while ((m & 1) == 0) {
            m >>= 1;
            v >>= 1;
          }
          specs.add((tag, per * v, null));
        }
      }
      final values = <int, List<int>>{};
      for (final (tag, count, byteCount) in specs) {
        final list = <int>[];
        if (byteCount != null) {
          final target = p + byteCount;
          if (target > stop) _damaged('Invalid TAGX byte count');
          while (p < target) {
            list.add(variable());
          }
          if (p != target) _damaged('Invalid TAGX values');
        } else {
          if (count > stop - p) _damaged('Invalid TAGX count');
          for (var k = 0; k < count; k++) {
            list.add(variable());
          }
        }
        values[tag] = list;
      }
      result.add(_IndexEntry(utf8.decode(record.slice(start + 1, textLength)), values));
    }
  }
  return result;
}
