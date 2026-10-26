/// Joins hard wraps; blank lines remain paragraph boundaries. Only discretionary
/// soft hyphens, PDFium’s U+0002 hyphen marker and Latin trailing-hyphen wraps
/// are dehyphenated. A wrap carries no space between CJK characters, but one the
/// PDF text already has next to a Latin word or number stays.
String joinExcerptLines(String text) {
  final paragraphs = text
      .replaceAll('\u0002', '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .trim()
      .split(RegExp(r'\n\s*\n'));
  return paragraphs
      .map((paragraph) {
        var result = '';
        var spaceAfter = false;
        for (final raw in paragraph.split('\n')) {
          final line = raw.trim();
          if (line.isEmpty) continue;
          final spaceBefore = raw.startsWith(RegExp(r'\s'));
          final hadSpace = spaceAfter || spaceBefore;
          spaceAfter = RegExp(r'\s$').hasMatch(raw);
          if (result.isEmpty) {
            result = line;
          } else if (result.endsWith('\u00ad')) {
            result = result.substring(0, result.length - 1) + line;
          } else if (RegExp(r'[A-Za-z]{2,}-$').hasMatch(result) && RegExp(r'^[a-z]').hasMatch(line)) {
            result = result.substring(0, result.length - 1) + line;
          } else {
            final noSpace =
                RegExp(r'[\u2e80-\u9fff\uf900-\ufaff，。！？；：、（]$').hasMatch(result) ||
                RegExp(r'^[\u2e80-\u9fff\uf900-\ufaff，。！？；：、）]').hasMatch(line);
            final keepSpace =
                hadSpace && (RegExp(r'[A-Za-z0-9]$').hasMatch(result) || RegExp(r'^[A-Za-z0-9]').hasMatch(line));
            result += '${noSpace && !keepSpace ? '' : ' '}$line';
          }
        }
        return result;
      })
      .where((s) => s.isNotEmpty)
      .join('\n\n');
}
