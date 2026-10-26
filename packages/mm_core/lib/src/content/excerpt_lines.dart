/// Joins hard wraps; blank lines remain paragraph boundaries. Only discretionary
/// soft hyphens, PDFium’s U+0002 hyphen marker and Latin trailing-hyphen wraps
/// are dehyphenated.
String joinExcerptLines(String text) {
  final paragraphs = text
      .replaceAll('\u0002', '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .trim()
      .split(RegExp(r'\n\s*\n'));
  return paragraphs
      .map((paragraph) {
        final lines = paragraph.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty);
        var result = '';
        for (final line in lines) {
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
            result += '${noSpace ? '' : ' '}$line';
          }
        }
        return result;
      })
      .where((s) => s.isNotEmpty)
      .join('\n\n');
}
