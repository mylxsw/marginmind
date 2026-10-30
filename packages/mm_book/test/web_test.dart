import 'dart:convert';
import 'dart:typed_data';

import 'package:mm_book/mm_book.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  const parser = WebBookParser();
  BookChapter chapter(String text, [String id = 'main']) => const EpubParser().parseHtml(id, '<p>$text</p>');
  test('body attribution follows a single title in HTML and Markdown, with only the domain linked', () async {
    final url = Uri.parse('https://example.com/article?a=1&b=2');
    for (final source in ['<h1>Article</h1><p>Body</p>', '<p>Body</p>']) {
      final html = parser.withAttribution(source, 'Article', url, DateTime(2026, 10, 29));
      for (final book in [
        parser.parse('Article', html, {}),
        await const MarkdownBookParser().parse(utf8.encode(parser.markdown(html))),
      ]) {
        final blocks = book.chapters.single.blocks;
        expect(blocks.map((b) => b.text), ['Article', 'example.com · 2026-10-29', 'Body']);
        final source = blocks[1];
        expect(source.style['font-size'], '0.75em');
        expect(source.style['font-family'], 'system-ui');
        expect(source.style['opacity'], '0.6');
        expect(source.runs.where((r) => r.link != null).single.text, 'example.com');
        expect(source.runs.where((r) => r.link != null).single.link, url.toString());
      }
    }
    final escaped = parser.withAttribution('<p>Body</p>', '<script>title</script>', url, DateTime(2026));
    expect(escaped, contains('&lt;script&gt;title&lt;/script&gt;'));
    expect(parser.withAttribution('<p>Body</p>', '', url, DateTime(2026)), contains('<h1>example.com</h1>'));
    expect(() => parser.withAttribution('', 'Title', url, DateTime(2026)), throwsFormatException);
  });
  test('snapshot sanitization is independent of page JavaScript and retains article text inside forms', () {
    final clean = parser.sanitizeHtml(
      '<form><article><p>visible</p><img src="resources/a.png" onload="secret()">'
      '<a href="javascript:secret()">bad</a><a href="#heading">inside</a><a href="https://example.com">web</a>'
      '<a href="https://user:pass@example.com">credential</a><img src="https://tracker.example.com">'
      '<input value="FORM_SECRET"><textarea>FORM_SECRET</textarea></article></form>'
      '<script>SCRIPT_SECRET</script><div hidden>HIDDEN_SECRET</div>',
      {'resources/a.png'},
    );
    for (final secret in [
      'FORM_SECRET',
      'SCRIPT_SECRET',
      'HIDDEN_SECRET',
      'onload',
      'javascript:',
      'https://tracker.example.com',
      'user:pass',
    ]) {
      expect(clean, isNot(contains(secret)));
    }
    expect(clean, contains('visible'));
    expect(clean, contains('Content-Security-Policy'));
    expect(clean, contains('src="resources/a.png"'));
    expect(clean, contains('href="#heading"'));
    expect(clean, contains('href="https://example.com"'));
    final resources = parser.sanitizeResources({
      'resources/a.svg': utf8.encode(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10" onload="secret()"><script>secret()</script><foreignObject>active</foreignObject><rect width="10" height="10"/><use href="http://tracker.example.com"/></svg>',
      ),
    });
    final svg = utf8.decode(resources.values.single);
    expect(svg, contains('<rect'));
    expect(svg, isNot(contains('secret')));
    expect(svg, isNot(contains('foreignObject')));
    expect(svg, isNot(contains('tracker.example.com')));
    expect(
      parser.parse('Image', '<img src="resources/a.svg">', resources).resourceManifest.values.single.mime,
      'image/svg+xml',
    );
    expect(() => parser.sanitizeResources({'../secret.png': pngImage()}), throwsFormatException);
  });
  test('HTML normalization, local images, headings and Unicode share the IR', () {
    final result = parser.parse('Title', '<h1>标题</h1><p>你好 &amp; <strong>🌍</strong></p><img src="resources/a.png">', {
      'resources/a.png': pngImage(),
    });
    expect(result.title, 'Title');
    expect(result.chapters.single.id, 'main');
    expect(result.chapters.single.canonicalText, '标题\n你好 & 🌍\n\uFFFC');
    expect(result.toc.single.offset, 0);
    expect(result.resourceManifest['resources/a.png']!.mime, 'image/png');
    expect(() => parser.parse('', '<script>secret</script>', {}), throwsFormatException);
    for (final path in ['../secret.png', 'resources/a.exe', '/resources/a.png']) {
      expect(() => parser.parse('', '<p>text</p>', {path: pngImage()}), throwsFormatException);
    }
    expect(
      () => parser.parse('', '<p>a</p>', {
        'resources/a.png': Uint8List.fromList([1, 2]),
      }),
      throwsFormatException,
    );
  });
  test('Markdown roundtrip keeps inline styles, code, links, lists, tables and images', () async {
    const source =
        '<h2>A</h2><p><b>bold</b> <em>italic</em> <a href="https://example.com/">link</a><br>next</p>'
        '<pre>  code`\nline</pre><blockquote>quote</blockquote><hr>'
        '<ul><li>first<ul><li>nested</li></ul></li></ul>'
        '<table><tr><th>X</th></tr><tr><td>Y</td></tr></table><p><code>a`b</code> <code>a``b</code> <code>`edge`</code> *literal*</p>'
        '<img alt="image" src="resources/a.png"><a>plain</a><img><ruby>文<rt>wen</rt></ruby>';
    final markdown = parser.markdown(source);
    expect(markdown, contains('## A'));
    expect(markdown, contains('**bold**'));
    expect(markdown, contains('<table>'));
    final parsed = await const MarkdownBookParser().parse(utf8.encode(markdown), resolver: (_) async => pngImage());
    for (final text in [
      'bold',
      'italic',
      'link',
      'code`',
      'nested',
      'X',
      'Y',
      'a`b',
      'a``b',
      '`edge`',
      '*literal*',
      '文',
    ]) {
      expect(parsed.chapters.single.canonicalText, contains(text));
    }
    expect(parsed.resources.length, 1);
    expect(parser.markdown('<script>secret</script><form>password</form><p>ok</p>'), 'ok\n');
  });
  test('alignment validates same version then uses unique quotes and context', () {
    final old = chapter('before 🌍 after');
    final anchor = old.anchor(7, 9, revision: 'old');
    expect(alignTextAnchor(anchor, [old], 'old'), same(anchor));
    final shifted = chapter('inserted before 🌍 after');
    final aligned = alignTextAnchor(anchor, [shifted], 'new')!;
    expect(aligned.start, 16);
    expect(aligned.quote, '🌍');
    expect(aligned.revision, 'new');
    expect(alignTextAnchor(anchor, [chapter('gone')], 'new'), isNull);
    expect(alignTextAnchor(const TextAnchor('main', 0, 1, 'x', revision: 'a'), [chapter('x x')], 'b'), isNull);
    final repeated = chapter('other x before x after');
    final contextual = const TextAnchor('main', 0, 1, 'x', prefix: 'before ', suffix: ' after', revision: 'a');
    expect(alignTextAnchor(contextual, [repeated], 'b')!.start, 15);
    expect(alignTextAnchor(contextual, [chapter('before x after', 'renamed')], 'b')!.chapterId, 'renamed');
    expect(alignTextAnchor(const TextAnchor('old', 0, 1, 'x', revision: 'a'), [chapter('x', 'renamed')], 'b'), isNull);
    expect(alignTextAnchor(const TextAnchor('main', 0, 0, '', revision: 'a'), [old], 'b'), isNull);
    expect(
      alignTextAnchor(const TextAnchor('main', 0, 1, 'x', revision: 'a', normalizationVersion: 2), [old], 'b'),
      isNull,
    );
    expect(alignTextAnchor(anchor, [], 'b'), isNull);
    expect(alignTextAnchor(const TextAnchor('main', 0, 1, 'x', revision: 'a'), [chapter('x' * 10002)], 'b'), isNull);
  });
}
