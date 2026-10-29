part of '../mm_book.dart';

const _cssProperties = {
  'font-family',
  'font-size',
  'font-weight',
  'font-style',
  'line-height',
  'color',
  'text-decoration',
  'text-align',
  'text-indent',
  'white-space',
  'margin',
  'margin-top',
  'margin-right',
  'margin-bottom',
  'margin-left',
  'padding',
  'padding-top',
  'padding-right',
  'padding-bottom',
  'padding-left',
  'width',
  'max-width',
  'height',
  'break-before',
  'break-after',
  'break-inside',
  'display',
  'position',
  'top',
  'left',
  'right',
  'bottom',
};
const _cssInherited = {
  'font-family',
  'font-size',
  'font-weight',
  'font-style',
  'line-height',
  'color',
  'text-decoration',
  'text-align',
  'text-indent',
  'white-space',
};

class _Css {
  _Css(dom.Document document, String chapterId, List<String> diagnostics) {
    for (final style in document.querySelectorAll('style')) {
      var text = style.text.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '').replaceAll(RegExp(r'@charset[^;]*;'), '');
      text = text.replaceAllMapped(RegExp(r'@font-face\s*\{([^{}]*)\}', caseSensitive: false), (match) {
        final fields = <String, String>{};
        for (final declaration in match[1]!.split(';')) {
          final colon = declaration.indexOf(':');
          if (colon >= 0) fields[declaration.substring(0, colon).trim()] = declaration.substring(colon + 1).trim();
        }
        final family = fields['font-family'];
        final url = RegExp(r"""url\(\s*["']?([^\s"'()]+)["']?\s*\)""").firstMatch(fields['src'] ?? '')?.group(1);
        if (family != null && url != null) {
          try {
            fonts.add(
              BookFontFace(
                family.replaceAll(RegExp(r"""^["']|["']$"""), ''),
                _resolve(style.attributes['data-mm-source'] ?? chapterId, url),
                fields['font-weight'] ?? 'normal',
                fields['font-style'] ?? 'normal',
              ),
            );
          } on FormatException {
            diagnostics.add('Blocked font URL: $url');
          }
        } else {
          diagnostics.add('Unsupported font-face declaration');
        }
        return '';
      });
      for (final match in RegExp(r'([^{}]+)\{([^{}]*)\}').allMatches(text)) {
        for (final selector in match[1]!.split(',')) {
          final parts = selector.trim().split(RegExp(r'\s+'));
          if (parts.any((s) => !RegExp(r'^(?:[a-zA-Z][\w-]*|\*)?(?:[.#][\w-]+)*$').hasMatch(s) || s.isEmpty)) {
            diagnostics.add('Unsupported CSS selector: ${selector.trim()}');
            continue;
          }
          var score = 0;
          for (final p in parts) {
            score += RegExp('#').allMatches(p).length * 100 + RegExp(r'\.').allMatches(p).length * 10;
            if (RegExp(r'^[a-zA-Z]').hasMatch(p)) score++;
          }
          rules.add((parts, score, _declarations(match[2]!, diagnostics)));
        }
      }
    }
  }
  final fonts = <BookFontFace>[];
  final rules = <(List<String>, int, Map<String, (String, bool)>)>[];
  Map<String, String> compute(dom.Element node, Map<String, String> parent, List<String> diagnostics) {
    final result = <String, String>{
      for (final k in _cssInherited)
        if (parent[k] != null) k: parent[k]!,
    };
    final weights = <String, (int, int)>{};
    void apply(Map<String, (String, bool)> declarations, int specificity) {
      for (final e in declarations.entries) {
        final rank = (e.value.$2 ? 1 : 0, specificity);
        final old = weights[e.key];
        if (old != null && (old.$1 > rank.$1 || old.$1 == rank.$1 && old.$2 > rank.$2)) continue;
        weights[e.key] = rank;
        final value = e.value.$1;
        if (value == 'inherit') {
          if (parent[e.key] != null) result[e.key] = parent[e.key]!;
        } else {
          result[e.key] = value;
        }
      }
    }

    bool simple(dom.Element e, String selector) {
      final tag = RegExp(r'^[a-zA-Z][\w-]*').firstMatch(selector)?.group(0);
      if (tag != null && e.localName != tag.toLowerCase()) return false;
      for (final m in RegExp(r'([.#])([\w-]+)').allMatches(selector)) {
        if (m[1] == '#' ? e.id != m[2] : !e.classes.contains(m[2])) return false;
      }
      return true;
    }

    if (rules.length > 10000) _limit();
    for (final (parts, score, declarations) in rules) {
      if (!simple(node, parts.last)) continue;
      dom.Element? ancestor = node.parent;
      var i = parts.length - 2;
      while (i >= 0 && ancestor != null) {
        if (simple(ancestor, parts[i])) i--;
        ancestor = ancestor.parent;
      }
      if (i < 0) apply(declarations, score);
    }
    apply(_declarations(node.attributes['style'] ?? '', diagnostics), 1000);
    return Map.unmodifiable(result);
  }
}

Map<String, (String, bool)> _declarations(String source, List<String> diagnostics) {
  final result = <String, (String, bool)>{};
  for (final declaration in source.split(';')) {
    final colon = declaration.indexOf(':');
    if (colon < 0) continue;
    final key = declaration.substring(0, colon).trim().toLowerCase();
    var value = declaration.substring(colon + 1).trim();
    final important = RegExp(r'\s*!important\s*$', caseSensitive: false).hasMatch(value);
    value = value.replaceFirst(RegExp(r'\s*!important\s*$', caseSensitive: false), '');
    if (!_cssProperties.contains(key) ||
        value.contains('url(') ||
        value.contains('expression(') ||
        key == 'display' && !const {'none', 'block', 'inline', 'inline-block'}.contains(value)) {
      diagnostics.add('Unsupported CSS declaration: $key');
      continue;
    }
    if (result[key]?.$2 == true && !important) continue;
    result[key] = (value, important);
  }
  return result;
}
