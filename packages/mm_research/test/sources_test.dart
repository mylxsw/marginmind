import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_research/mm_research.dart';
import 'package:test/test.dart';

class Parser implements HtmlArticleParser {
  Parser(this.read);
  final ReadableHtml Function(Uri, String) read;
  @override
  Future<ReadableHtml> parse(Uri url, String html, CancellationToken cancellation) async => read(url, html);
}

void main() {
  ResearchHttp transport(Future<http.Response> Function(http.Request) send) => ResearchHttp(
    clientFactory: () => MockClient(send),
    policy: UrlPolicy(lookup: (_) async => [InternetAddress('8.8.8.8')]),
  );
  final url = Uri.parse('https://example.com/article');
  test('video identity rejects fake hosts and search pages and preserves Bilibili parts', () {
    final now = DateTime(2026);
    for (final link in [
      'https://youtu.be/dQw4w9WgXcQ',
      'https://youtube.com/watch?v=dQw4w9WgXcQ',
      'https://m.youtube.com/shorts/dQw4w9WgXcQ',
    ]) {
      expect(videoSource(Uri.parse(link), now).canonicalUrl, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    }
    expect(videoSource(Uri.parse('https://www.bilibili.com/video/BV1xx411c7mD?p=2'), now).url, contains('p=2'));
    expect(videoSource(Uri.parse('https://bilibili.com/video/av123'), now).videoId, 'av123');
    for (final link in [
      'https://youtube.com.evil.com/watch?v=dQw4w9WgXcQ',
      'https://youtube.com/results?search_query=x',
      'https://youtu.be/',
      'file:///video',
      'https://bilibili.com/video/invalid',
      'https://youtube.com/watch?v=bad',
    ]) {
      expect(() => videoSource(Uri.parse(link), now), throwsA(isA<ResearchFailure>()));
    }
    final hit = sourceFromHit(SearchHit(url: Uri.parse('https://youtu.be/dQw4w9WgXcQ'), title: 'Video'), now);
    expect(hit.kind, 'video');
    expect(hit.title, 'Video');
    expect(hit.readState, 'noTranscript');
    expect(
      sourceFromHit(SearchHit(url: Uri.parse('https://youtu.be/dQw4w9WgXcQ'), title: ''), now).title,
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    );
  });

  test('video titles from YouTube oEmbed and Bilibili; any failure keeps the link', () async {
    final now = DateTime(2026);
    final youtube = videoSource(Uri.parse('https://youtu.be/dQw4w9WgXcQ'), now);
    final bv = videoSource(Uri.parse('https://www.bilibili.com/video/BV1xx411c7mD?p=2'), now);
    final av = videoSource(Uri.parse('https://bilibili.com/video/av170001'), now);
    expect(youtube.title, youtube.url);
    final seen = <Uri>[];
    VideoTitles titles(int status, Object body) => VideoTitles(
      http: transport((r) async {
        seen.add(r.url);
        return http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );
    expect(
      await titles(200, {'title': ' Never Gonna Give You Up '}).lookup(youtube, CancellationToken()),
      'Never Gonna Give You Up',
    );
    expect(seen.last.host, 'www.youtube.com');
    expect(seen.last.path, '/oembed');
    expect(seen.last.queryParameters['url'], youtube.canonicalUrl);
    final bilibili = titles(200, {
      'code': 0,
      'data': {'title': '字幕君交流场所'},
    });
    expect(await bilibili.lookup(bv, CancellationToken()), '字幕君交流场所');
    expect(seen.last.queryParameters, {'bvid': 'BV1xx411c7mD'});
    expect(await bilibili.lookup(av, CancellationToken()), '字幕君交流场所');
    expect(seen.last.queryParameters, {'aid': '170001'});
    expect(await titles(200, {'code': -404, 'message': 'x'}).lookup(bv, CancellationToken()), isNull);
    expect(await titles(200, {'title': '  '}).lookup(youtube, CancellationToken()), isNull);
    expect(await titles(404, {}).lookup(youtube, CancellationToken()), isNull);
    final calls = seen.length;
    final web = ResearchSource(
      id: 'w',
      url: 'https://e.com',
      canonicalUrl: 'https://e.com/',
      kind: 'web',
      title: 'W',
      fetchedAt: now,
    );
    expect(await titles(200, {'title': 'x'}).lookup(web, CancellationToken()), isNull);
    expect(seen.length, calls);
  });

  test('a real video title replaces a link or ID placeholder but not a known title', () {
    final now = DateTime(2026);
    final link = videoSource(Uri.parse('https://youtu.be/dQw4w9WgXcQ'), now);
    ResearchSource titled(ResearchSource s, String title) => ResearchSource.fromJson({...s.toJson(), 'title': title});
    for (final placeholder in [link, titled(link, 'dQw4w9WgXcQ')]) {
      final sources = [placeholder];
      mergeSource(sources, titled(link, 'Real'));
      expect(sources.single.title, 'Real');
    }
    final sources = [titled(link, 'Real')];
    mergeSource(sources, link);
    expect(sources.single.title, 'Real');
  });

  test('OpenAlex query, metadata, abstract inversion and optional bearer credential', () async {
    final search = OpenAlexSearch(
      apiKey: 'test-key',
      http: transport((r) async {
        expect(r.url.queryParameters, {'search': '中文 query', 'per-page': '2'});
        expect(r.headers['authorization'], 'Bearer test-key');
        return http.Response(
          jsonEncode({
            'results': [
              {
                'id': 'https://openalex.org/W1',
                'doi': 'https://doi.org/10.1234/ABC',
                'title': 'Paper',
                'publication_date': '2026-01-02',
                'abstract_inverted_index': {
                  'second': [1],
                  'first': [0, 2],
                },
                'authorships': [
                  {
                    'author': {'display_name': 'Author'},
                  },
                ],
                'open_access': {'is_oa': true, 'oa_url': 'https://example.com/full.pdf'},
              },
              {
                'id': 'https://openalex.org/W2',
                'primary_location': {'landing_page_url': 'https://example.com/landing'},
              },
            ],
          }),
          200,
        );
      }),
    );
    final hits = await search.search(const SearchRequest('中文 query', limit: 2), CancellationToken());
    expect(hits.first.snippet, 'first second first');
    expect(hits.first.doi, '10.1234/abc');
    expect(hits.first.authors, ['Author']);
    expect(hits.first.openAccess, isTrue);
    expect(hits.first.openAccessUrl.toString(), 'https://example.com/full.pdf');
    expect(hits.first.publishedAt, DateTime(2026, 1, 2));
    expect(hits.last.url.toString(), 'https://example.com/landing');
    expect(hits.last.snippet, isEmpty);
    expect(hits.last.kind, 'paper');
    expect(hits.last.openAccess, isNull);
    for (final request in [
      const SearchRequest(''),
      const SearchRequest('q', limit: 0),
      const SearchRequest('q', limit: 101),
    ]) {
      await expectLater(search.search(request, CancellationToken()), throwsA(isA<ResearchFailure>()));
    }
  });
  test('malformed results, dangerous URLs and malformed abstracts fail explicitly', () async {
    for (final data in ['bad-json', '{"results":[{}]}', '{"results":[{"id":"file:///etc/passwd"}]}']) {
      await expectLater(
        OpenAlexSearch(http: transport((r) async => http.Response(data, 200)))
            .search(const SearchRequest('q'), CancellationToken()),
        throwsA(isA<ResearchFailure>()),
      );
    }
    for (final value in [
      {
        'a': [-1],
      },
      {
        'a': [0],
        'b': [0],
      },
      {
        'a': [100001],
      },
      {
        'a': ['1'],
      },
    ]) {
      expect(() => restoreAbstract(value), throwsFormatException);
    }
    expect(restoreAbstract({}), '');
  });
  test('snapshot lengths prevent forged paragraph markers inside code', () {
    final text = 'before\n<!-- paragraph:abc-1; length:4 -->\nevil\nafter';
    final encoded = encodeSnapshot({'abc-1': text, 'def-1': 'real'});
    expect(snapshotParagraphs(encoded), {'abc-1': text, 'def-1': 'real'});
    for (final broken in [
      'garbage',
      '<!-- paragraph:abc-1; length:99 -->\nx',
      '<!-- paragraph:abc-1; length:1 -->\nxBAD',
      '<!-- paragraph:abc-1; length:1 -->\nx\n\n<!-- paragraph:abc-1; length:1 -->\ny',
    ]) {
      expect(() => snapshotParagraphs(broken), throwsFormatException);
    }
  });
  test('redirected document uses final URL; binary and unsupported encodings fail', () async {
    final extractor = MarkdownArticleExtractor(
      http: transport((r) async {
        if (r.url.path == '/article') return http.Response('', 302, headers: {'location': '/moved/'});
        return http.Response('<p>body</p>', 200, headers: {'content-type': 'text/html; charset=utf-8'});
      }),
      parser: Parser((uri, html) {
        expect(uri.path, '/moved/');
        return ReadableHtml(url: uri, title: '', html: html);
      }),
    );
    expect((await extractor.extract(url, CancellationToken())).url.path, '/moved/');
    for (final type in ['application/pdf', 'text/html; charset=gbk']) {
      final bad = MarkdownArticleExtractor(
        http: transport((r) async => http.Response('x', 200, headers: {'content-type': type})),
        parser: Parser((u, h) => throw StateError('not reached')),
      );
      await expectLater(bad.extract(url, CancellationToken()), throwsA(isA<ResearchFailure>()));
    }
  });

  test('canonical URL / DOI and source merge preserve retained versions', () {
    expect(
      canonicalUrl(Uri.parse('https://EXAMPLE.com/a?z=2&utm_source=x&a=1&fbclid=foo#part')),
      'https://example.com/a?a=1&z=2',
    );
    expect(canonicalDoi('DOI:10.1234/AbC'), '10.1234/abc');
    expect(canonicalDoi('invalid'), isNull);
    expect(externalSearchLink('测试 & question').queryParameters['q'], '测试 & question');
    final first = sourceFromHit(SearchHit(url: url, title: ''), DateTime(2026));
    final sources = [first];
    final merged = mergeSource(
      sources,
      sourceFromHit(SearchHit(url: url, title: 'A', snippet: 'summary'), DateTime(2026)),
    );
    expect(merged.id, first.id);
    expect(merged.title, 'A');
    expect(merged.readState, 'snippet');
    expect(sources, hasLength(1));
  });
  test('Markdown preserves structure and stable paragraph IDs; removes active HTML and image URLs', () {
    final article = ReadableHtml(
      url: url,
      title: 'Title',
      html: '''
      <article><h1>标题</h1><p>A <strong>bold</strong> <em>italic</em> <a href="/page">link</a>.</p>
      <ul><li>one</li><li>two</li></ul><ol><li>ordered</li></ol>
      <table><tr><th>A</th><th>B</th></tr><tr><td>x|y</td><td>value</td></tr></table>
      <pre><code>print('hello');\n\n```</code></pre><p>inline <code>x</code><br>next</p>
      <p><img src="http://127.0.0.1/secret" alt="caption"><a href="javascript:alert(1)">plain</a></p>
      <iframe src="http://10.0.0.1"></iframe><script>secret()</script><hr><p>repeat</p><p>repeat</p>
      </article>''',
    );
    final content = markdownArticle(article);
    final markdown = encodeSnapshot(content.paragraphs);
    expect(markdown, contains('# 标题'));
    expect(markdown, contains('**bold** *italic* [link](https://example.com/page)'));
    expect(markdown, contains('- one\n- two'));
    expect(markdown, contains('| A | B |'));
    expect(markdown, contains('| x\\|y | value |'));
    expect(markdown, contains("````\nprint('hello');\n\n```\n````"));
    expect(markdown, contains('captionplain'));
    expect(markdown, isNot(contains('127.0.0.1')));
    expect(markdown, isNot(contains('secret()')));
    expect(markdown, isNot(contains('javascript:')));
    expect(snapshotParagraphs(markdown), content.paragraphs);
    expect(markdownArticle(article).paragraphs.keys, content.paragraphs.keys);
    final duplicateIds = content.paragraphs.entries.where((e) => e.value == 'repeat').map((e) => e.key).toList();
    expect(duplicateIds.first, endsWith('-1'));
    expect(duplicateIds.last, endsWith('-2'));
    expect(
      () => markdownArticle(ReadableHtml(url: url, title: '', html: '<script>x()</script>')),
      throwsA(isA<ResearchFailure>()),
    );
  });
  test('embedded backticks cannot break inline-code boundaries into HTML or links', () {
    final content = markdownArticle(
      ReadableHtml(
        url: url,
        title: '',
        html: '<p><code>``&lt;img src="http://127.0.0.1/"&gt;[x](javascript:alert(1))</code></p>',
      ),
    );
    expect(content.paragraphs.values.single, '``` ``<img src="http://127.0.0.1/">[x](javascript:alert(1)) ```');
  });

  test('extraction passes safely fetched document to parser, cancellation and local exception rejected', () async {
    final extractor = MarkdownArticleExtractor(
      http: transport((r) async => http.Response('<p>raw</p>', 200)),
      parser: Parser((uri, html) {
        expect(uri, url);
        expect(html, '<p>raw</p>');
        return ReadableHtml(url: uri, title: 'A', html: '<p>cleaned</p>');
      }),
    );
    expect((await extractor.extract(url, CancellationToken())).paragraphs.values, ['cleaned']);
    await expectLater(extractor.extract(url, CancellationToken()..cancel()), throwsA(isA<ResearchFailure>()));
    final local = MarkdownArticleExtractor(
      http: ResearchHttp(policy: UrlPolicy(localEndpoint: Uri.parse('http://localhost'))),
      parser: Parser((u, h) => throw StateError('not reached')),
    );
    await expectLater(local.extract(url, CancellationToken()), throwsA(isA<ResearchFailure>()));
  });
}
