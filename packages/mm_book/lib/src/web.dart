part of '../mm_book.dart';

/// Accepts the sanitized Readability HTML from the live browser, without IO.
class WebBookParser {
  const WebBookParser();

  /// Enforce the static snapshot boundary again outside the page's JavaScript
  /// world. A site may replace builtins used by the browser-side extractor.
  String sanitizeHtml(String source, Set<String> resourcePaths) {
    if (utf8.encode(source).length > 16 * 1024 * 1024) _limit();
    final document = html.parse(source);
    for (final form in document.querySelectorAll('form')) {
      final parent = form.parentNode!;
      for (final child in form.nodes.toList()) {
        parent.insertBefore(child, form);
      }
      form.remove();
    }
    for (final node in document.querySelectorAll(
      'script,style,noscript,template,iframe,object,embed,base,link,meta,input,textarea,select,button,source,video,audio,svg,math,[hidden],[aria-hidden="true"]',
    )) {
      node.remove();
    }
    for (final node in document.querySelectorAll('*')) {
      node.attributes.removeWhere(
        (key, _) => !{'src', 'href', 'alt', 'title', 'colspan', 'rowspan', 'id', 'class', 'lang', 'dir'}.contains(key),
      );
      final src = node.attributes['src'];
      if (src != null && !resourcePaths.contains(src)) node.attributes.remove('src');
      final href = node.attributes['href'];
      if (href != null) {
        final uri = Uri.tryParse(href);
        if (uri == null ||
            uri.userInfo.isNotEmpty ||
            !{'http', 'https', 'mailto'}.contains(uri.scheme) && !href.startsWith('#')) {
          node.attributes.remove('href');
        }
      }
    }
    document.head!.nodes.insert(
      0,
      dom.Element.tag('meta')
        ..attributes.addAll({
          'http-equiv': 'Content-Security-Policy',
          'content': "default-src 'none'; img-src 'self' data:; style-src 'unsafe-inline'; form-action 'none'",
        }),
    );
    return document.outerHtml;
  }

  Map<String, Uint8List> sanitizeResources(Map<String, Uint8List> resources) {
    if (resources.length > 64 || resources.values.fold<int>(0, (n, b) => n + b.length) > 32 * 1024 * 1024) _limit();
    final result = <String, Uint8List>{};
    for (final entry in resources.entries) {
      final mime = _mime(entry.value, entry.key);
      if (!RegExp(r'^resources/[a-zA-Z0-9_-]+\.(png|jpg|gif|webp|svg)$').hasMatch(entry.key) ||
          entry.value.length > 5 * 1024 * 1024 ||
          !mime.startsWith('image/')) {
        _damaged('Invalid captured image');
      }
      result[entry.key] = mime == 'image/svg+xml' ? _staticSvg(entry.value) : entry.value;
    }
    return result;
  }

  Uint8List _staticSvg(Uint8List bytes) {
    final document = XmlDocument.parse(utf8.decode(bytes));
    for (final node in document.descendants.whereType<XmlElement>().toList()) {
      if ({
        'script',
        'foreignobject',
        'iframe',
        'object',
        'embed',
        'style',
        'animate',
        'animatemotion',
        'animatetransform',
        'set',
      }.contains(node.name.local.toLowerCase())) {
        node.parent?.children.remove(node);
        continue;
      }
      node.attributes.removeWhere(
        (a) =>
            a.name.local.toLowerCase().startsWith('on') ||
            a.name.local == 'style' ||
            RegExp(r'url\s*\(', caseSensitive: false).hasMatch(a.value) ||
            a.name.local == 'href' && !a.value.startsWith('#'),
      );
    }
    return utf8.encode(document.rootElement.toXmlString());
  }

  Book parse(String title, String source, Map<String, Uint8List> resources) {
    if (utf8.encode(source).length > 16 * 1024 * 1024 || resources.length > 64) _limit();
    if (resources.values.fold<int>(0, (sum, bytes) => sum + bytes.length) > 32 * 1024 * 1024) _limit();
    for (final entry in resources.entries) {
      if (!RegExp(r'^resources/[a-zA-Z0-9_-]+\.(png|jpg|gif|webp|svg)$').hasMatch(entry.key) ||
          entry.value.length > 5 * 1024 * 1024 ||
          !_mime(entry.value, entry.key).startsWith('image/')) {
        _damaged('Invalid captured image');
      }
    }
    final diagnostics = <String>[];
    final chapter = const EpubParser().parseHtml('main', source, diagnostics);
    if (chapter.canonicalText.trim().isEmpty) _damaged('No readable content');
    return Book(
      title,
      [chapter],
      resources,
      diagnostics,
      toc: [
        for (final block in chapter.blocks)
          if (block.kind == BlockKind.heading) BookTocEntry(block.id, block.text, 'main', block.start),
      ],
    );
  }

  /// App-authored provenance belongs to the article flow, below its title.
  /// Call after sanitizing the site's markup; only the domain is linked.
  String withAttribution(String source, String title, Uri url, DateTime capturedAt) {
    final document = html.parse(source);
    if (document.body!.text.trim().isEmpty &&
        !document.body!.querySelectorAll('img').any((n) => n.attributes.containsKey('src'))) {
      _damaged('No readable content');
    }
    var heading = document.body!.querySelector('h1');
    if (heading == null) {
      heading = dom.Element.tag('h1')..text = title.trim().isEmpty ? url.host : title;
      document.body!.nodes.insert(0, heading);
    }
    final date = capturedAt.toLocal().toIso8601String().substring(0, 10);
    final attribution = dom.Element.tag('p')
      ..classes.add('mm-web-source')
      ..attributes['style'] = 'font-size:0.75em;font-family:system-ui;opacity:0.6'
      ..nodes.addAll([
        dom.Element.tag('a')
          ..attributes['href'] = url.toString()
          ..text = url.host,
        dom.Text(' · $date'),
      ]);
    final siblings = heading.parentNode!.nodes;
    siblings.insert(siblings.indexOf(heading) + 1, attribution);
    return document.outerHtml;
  }

  /// Preserve inline HTML for structures Markdown cannot represent losslessly
  /// (tables, ruby, nested lists); the shared Markdown parser accepts these.
  String markdown(String source) {
    final document = html.parse(source);
    String escape(String text) => text.replaceAllMapped(RegExp(r'[\\`*_\[\]<>#]'), (m) => '\\${m[0]}');
    String inlineCode(String text) {
      final longest = RegExp(r'`+').allMatches(text).fold<int>(0, (n, m) => m[0]!.length > n ? m[0]!.length : n);
      final fence = '`' * (longest + 1);
      final pad =
          text.startsWith('`') ||
              text.endsWith('`') ||
              text.startsWith(' ') && text.endsWith(' ') && text.trim().isNotEmpty
          ? ' '
          : '';
      return '$fence$pad$text$pad$fence';
    }

    String render(dom.Node node) {
      if (node is dom.Text) return escape(node.text);
      if (node is! dom.Element) return '';
      final tag = node.localName!;
      if (const {'script', 'style', 'form', 'input', 'textarea', 'button', 'iframe', 'object', 'embed'}.contains(tag)) {
        return '';
      }
      final body = node.nodes.map(render).join();
      if (tag == 'p' && node.classes.contains('mm-web-source')) return '\n${node.outerHtml}\n\n';
      if (RegExp(r'^h[1-6]$').hasMatch(tag)) return '\n${'#' * int.parse(tag[1])} $body\n\n';
      return switch (tag) {
        'p' || 'div' || 'section' || 'article' => '$body\n\n',
        'strong' || 'b' => '**$body**',
        'em' || 'i' => '*$body*',
        'br' => '  \n',
        'hr' => '\n---\n\n',
        'a' => node.attributes['href'] == null ? body : '[$body](<${node.attributes['href']}>)',
        'img' =>
          node.attributes['src'] == null
              ? ''
              : '![${escape(node.attributes['alt'] ?? '')}](<${node.attributes['src']}>)',
        'code' => inlineCode(node.text),
        'pre' =>
          '\n${'`' * (node.text.split('`').length + 3)}\n${node.text}\n${'`' * (node.text.split('`').length + 3)}\n\n',
        'blockquote' => '\n${body.trim().split('\n').map((line) => '> $line').join('\n')}\n\n',
        'ul' || 'ol' || 'table' || 'ruby' => '\n${node.outerHtml}\n\n',
        _ => body,
      };
    }

    return '${document.body!.nodes.map(render).join().trim()}\n';
  }
}

/// Unique quote + context matching. Never guess by distance across revisions.
TextAnchor? alignTextAnchor(TextAnchor anchor, List<BookChapter> chapters, String revision) {
  if (anchor.normalizationVersion != 1 || anchor.quote.isEmpty) return null;
  final original = chapters.where((c) => c.id == anchor.chapterId).firstOrNull;
  if (anchor.revision == revision && original != null && original.resolves(anchor)) return anchor;
  var overflow = false;
  List<(BookChapter, int, int)> matches(Iterable<BookChapter> source) {
    final result = <(BookChapter, int, int)>[];
    for (final chapter in source) {
      final text = chapter.canonicalText;
      for (var at = text.indexOf(anchor.quote); at >= 0; at = text.indexOf(anchor.quote, at + 1)) {
        if (result.length >= 10000) {
          overflow = true;
          return result;
        }
        result.add((
          chapter,
          at,
          (anchor.prefix.isNotEmpty &&
                      at >= anchor.prefix.length &&
                      text.startsWith(anchor.prefix, at - anchor.prefix.length)
                  ? 1
                  : 0) +
              (anchor.suffix.isNotEmpty && text.startsWith(anchor.suffix, at + anchor.quote.length) ? 1 : 0),
        ));
      }
    }
    return result;
  }

  var candidates = matches(original == null ? chapters : [original]);
  if (candidates.isEmpty && original != null) candidates = matches(chapters);
  if (overflow || candidates.isEmpty) return null;
  candidates.sort((a, b) => b.$3.compareTo(a.$3));
  final best = candidates.first;
  if (candidates.length > 1 && candidates[1].$3 == best.$3) return null;
  if (best.$1.id != anchor.chapterId && best.$3 == 0) return null;
  return best.$1.anchor(best.$2, best.$2 + anchor.quote.length, revision: revision);
}
