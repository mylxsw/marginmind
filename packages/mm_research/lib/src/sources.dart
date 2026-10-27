import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'package:mm_core/mm_core.dart';

import 'transport.dart';
import 'url_policy.dart';

String canonicalUrl(Uri url) {
  final stripped = url.removeFragment();
  UrlPolicy.syntax(stripped);
  final query = <String, dynamic>{};
  for (final entry in stripped.queryParametersAll.entries) {
    if (!entry.key.toLowerCase().startsWith('utm_') && !const ['fbclid', 'gclid'].contains(entry.key)) {
      query[entry.key] = entry.value;
    }
  }
  final keys = query.keys.toList()..sort();
  return stripped
      .replace(
        host: stripped.host.toLowerCase(),
        path: stripped.path.isEmpty ? '/' : stripped.path,
        queryParameters: {for (final k in keys) k: query[k]},
      )
      .toString()
      .replaceFirst(RegExp(r'\?$'), '');
}

String? canonicalDoi(String? doi) {
  if (doi == null) return null;
  final value = doi.trim().toLowerCase().replaceFirst(RegExp(r'^https?://(dx\.)?doi\.org/|^doi:\s*'), '');
  return RegExp(r'^10\.\d{4,9}/\S+$').hasMatch(value) ? value : null;
}

/// Accept only concrete video pages; never treat a search page as evidence.
ResearchSource videoSource(Uri url, DateTime now) {
  UrlPolicy.syntax(url);
  final host = url.host.toLowerCase();
  String? id;
  Uri? canonical;
  if (const ['youtube.com', 'www.youtube.com', 'm.youtube.com', 'youtu.be'].contains(host)) {
    id = host == 'youtu.be'
        ? url.pathSegments.firstOrNull
        : url.path == '/watch'
        ? url.queryParameters['v']
        : url.pathSegments.length == 2 && const ['shorts', 'embed'].contains(url.pathSegments.first)
        ? url.pathSegments.last
        : null;
    if (id != null && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)) {
      canonical = Uri.https('www.youtube.com', '/watch', {'v': id});
    }
  } else if (const ['bilibili.com', 'www.bilibili.com', 'm.bilibili.com'].contains(host)) {
    id = url.pathSegments.length >= 2 && url.pathSegments.first == 'video' ? url.pathSegments[1] : null;
    if (id != null && RegExp(r'^(BV[A-Za-z0-9]{10}|av[0-9]+)$').hasMatch(id)) {
      canonical = Uri.https('www.bilibili.com', '/video/$id', {
        if (int.tryParse(url.queryParameters['p'] ?? '') case final int page when page > 0) 'p': '$page',
      });
    }
  }
  if (canonical == null) throw const ResearchFailure(ResearchFailureKind.invalidRequest, 'invalid_video_link');
  final normalized = canonicalUrl(canonical);
  return ResearchSource(
    id: sha256.convert(utf8.encode(normalized)).toString(),
    url: canonical.toString(),
    canonicalUrl: normalized,
    kind: 'video',
    // The page title is looked up separately; the link stands in until then.
    title: canonical.toString(),
    videoId: id,
    fetchedAt: now,
    readState: 'noTranscript',
  );
}

/// Video titles from keyless public endpoints: YouTube oEmbed and Bilibili's
/// video info. Any failure returns null so the link remains the title.
class VideoTitles {
  VideoTitles({ResearchHttp? http}) : http = http ?? ResearchHttp();
  final ResearchHttp http;

  Future<String?> lookup(ResearchSource source, CancellationToken cancellation) async {
    final id = source.videoId;
    if (source.kind != 'video' || id == null) return null;
    final bilibili = Uri.parse(source.url).host == 'www.bilibili.com';
    final url = !bilibili
        ? Uri.https('www.youtube.com', '/oembed', {'url': source.canonicalUrl, 'format': 'json'})
        : Uri.https('api.bilibili.com', '/x/web-interface/view', {
            if (id.startsWith('BV')) 'bvid': id else 'aid': id.substring(2),
          });
    try {
      final bytes = await http
          .send(
            url,
            cancellation: cancellation,
            headers: {'accept': 'application/json'},
            budget: const ResearchBudget(duration: Duration(seconds: 8), responseBytes: 262144),
          )
          .expand((e) => e)
          .toList();
      final json = jsonDecode(utf8.decode(bytes)) as Map;
      final data = json['data'];
      final title = !bilibili
          ? json['title']
          : json['code'] == 0 && data is Map
          ? data['title']
          : null;
      return title is String && title.trim().isNotEmpty ? title.trim() : null;
    } catch (_) {
      return null;
    }
  }
}

ResearchSource sourceFromHit(SearchHit hit, DateTime now) {
  try {
    final video = videoSource(hit.url, now);
    return ResearchSource.fromJson({...video.toJson(), 'title': hit.title.isEmpty ? video.title : hit.title});
  } on ResearchFailure {
    /* Other search hits use the ordinary source pipeline. */
  }
  final url = canonicalUrl(hit.url);
  final doi = canonicalDoi(hit.doi ?? (hit.url.host.toLowerCase() == 'doi.org' ? hit.url.path.substring(1) : null));
  return ResearchSource(
    id: sha256.convert(utf8.encode(doi ?? url)).toString(),
    url: hit.url.toString(),
    canonicalUrl: url,
    kind: hit.kind == 'paper' || doi != null || hit.openAccess != null ? 'paper' : 'web',
    title: hit.title,
    authors: hit.authors,
    publishedAt: hit.publishedAt,
    doi: doi,
    fetchedAt: now,
    readState: hit.snippet.isEmpty
        ? 'unread'
        : hit.kind == 'paper' || doi != null || hit.openAccess != null
        ? 'abstractOnly'
        : 'snippet',
  );
}

/// Only explicit URL / DOI identity, never title similarity. Existing IDs and
/// versions remain authoritative so saved evidence cannot be silently retargeted.
ResearchSource mergeSource(List<ResearchSource> sources, ResearchSource incoming) {
  final index = sources.indexWhere(
    (s) => s.canonicalUrl == incoming.canonicalUrl || (s.doi != null && s.doi == incoming.doi),
  );
  if (index < 0) {
    sources.add(incoming);
    return incoming;
  }
  final old = sources[index];
  final merged = ResearchSource.fromJson({
    ...old.toJson(),
    'title': old.title.isEmpty || (old.kind == 'video' && _linkTitle(old)) ? incoming.title : old.title,
    'doi': old.doi ?? incoming.doi,
    'readState': old.readState == 'unread' ? incoming.readState : old.readState,
    'authors': old.authors.isEmpty ? incoming.authors : old.authors,
  });
  sources[index] = merged;
  return merged;
}

/// A video saved before its title was known shows its link (or, in older
/// sessions, its ID); a later save with a real title replaces it.
bool _linkTitle(ResearchSource s) => s.title == s.url || s.title == s.videoId;

/// A browser action, not a source and never consumed by the extraction pipeline.
Uri externalSearchLink(String query) => Uri.https('www.google.com', '/search', {'q': query});

class OpenAlexSearch implements SearchProvider {
  OpenAlexSearch({ResearchHttp? http, this.apiKey}) : http = http ?? ResearchHttp();
  final ResearchHttp http;
  final String? apiKey;
  @override
  Future<List<SearchHit>> search(SearchRequest request, CancellationToken cancellation) async {
    if (request.query.trim().isEmpty || request.limit < 1 || request.limit > 100) {
      throw const ResearchFailure(ResearchFailureKind.invalidRequest);
    }
    final url = Uri.https('api.openalex.org', '/works', {'search': request.query, 'per-page': '${request.limit}'});
    final bytes = await http
        .send(
          url,
          cancellation: cancellation,
          headers: {'accept': 'application/json', if (apiKey != null) 'authorization': 'Bearer $apiKey'},
          budget: const ResearchBudget(duration: Duration(seconds: 30)),
        )
        .expand((e) => e)
        .toList();
    try {
      final results = (jsonDecode(utf8.decode(bytes)) as Map)['results'] as List;
      return [for (final raw in results) _hit((raw as Map).cast())];
    } on ResearchFailure {
      rethrow;
    } catch (_) {
      throw const ResearchFailure(ResearchFailureKind.protocol, 'invalid_search_response');
    }
  }

  SearchHit _hit(Map<String, dynamic> work) {
    final doi = canonicalDoi(work['doi'] as String?);
    final location = work['primary_location'] as Map?;
    final url = Uri.parse(
      doi != null ? 'https://doi.org/$doi' : location?['landing_page_url'] as String? ?? work['id'] as String,
    );
    UrlPolicy.syntax(url);
    final oa = work['open_access'] as Map?;
    final oaUrl = Uri.tryParse(oa?['oa_url'] as String? ?? '');
    return SearchHit(
      url: url,
      title: work['title'] as String? ?? '',
      kind: 'paper',
      doi: doi,
      snippet: restoreAbstract(work['abstract_inverted_index']),
      authors: [
        for (final a in work['authorships'] as List? ?? [])
          if ((a as Map)['author']?['display_name'] case final String name) name,
      ],
      publishedAt:
          DateTime.tryParse(work['publication_date'] as String? ?? '') ??
          (work['publication_year'] is int ? DateTime(work['publication_year'] as int) : null),
      openAccess: oa?['is_oa'] as bool?,
      openAccessUrl: oaUrl != null && ['https', 'http'].contains(oaUrl.scheme) && oaUrl.host.isNotEmpty ? oaUrl : null,
    );
  }
}

String restoreAbstract(Object? value) {
  if (value == null) return '';
  final words = <int, String>{};
  for (final e in (value as Map).entries) {
    for (final index in e.value as List) {
      if (index is! int || index < 0 || index > 100000 || words.containsKey(index)) {
        throw const FormatException('Invalid abstract');
      }
      words[index] = e.key as String;
    }
  }
  final indices = words.keys.toList()..sort();
  return indices.map((i) => words[i]!).join(' ');
}

/// Snapshot format is Markdown with stable markers. Raw source HTML never reaches
/// the reader. Image URLs are deliberately omitted (only their captions survive).
String encodeSnapshot(Map<String, String> paragraphs) =>
    paragraphs.entries.map((e) => '<!-- paragraph:${e.key}; length:${e.value.length} -->\n${e.value}').join('\n\n');
Map<String, String> snapshotParagraphs(String markdown) {
  final result = <String, String>{};
  final marker = RegExp(r'<!-- paragraph:([a-f0-9]+-\d+); length:(\d+) -->\n');
  var offset = 0;
  while (offset < markdown.length) {
    final match = marker.matchAsPrefix(markdown, offset);
    if (match == null) throw const FormatException('Invalid snapshot paragraph');
    final end = match.end + int.parse(match.group(2)!);
    if (end > markdown.length || result.containsKey(match.group(1))) {
      throw const FormatException('Invalid snapshot length or duplicate ID');
    }
    result[match.group(1)!] = markdown.substring(match.end, end);
    if (end == markdown.length) break;
    if (!markdown.startsWith('\n\n', end)) throw const FormatException('Invalid paragraph separator');
    offset = end + 2;
  }
  return result;
}

class MarkdownArticleExtractor implements ContentExtractor {
  MarkdownArticleExtractor({required this.parser, ResearchHttp? http, this.cache}) : http = http ?? ResearchHttp();
  final HtmlArticleParser parser;
  final ResearchDocumentCache? cache;
  final ResearchHttp http;
  @override
  Future<ExtractedContent> extract(Uri url, CancellationToken cancellation) async {
    // The WebView never fetches even the main document; this transport pins DNS
    // and checks every redirect. No local-provider exception is permitted here.
    if (http.policy.localEndpoint != null) throw const ResearchFailure(ResearchFailureKind.unsafeUrl);
    var finalUrl = url.removeFragment();
    var contentType = '';
    final bytes = await http
        .send(
          finalUrl,
          cancellation: cancellation,
          headers: {'accept': 'text/html'},
          onResponse: (uri, headers) {
            finalUrl = uri;
            contentType = headers['content-type'] ?? '';
          },
          budget: const ResearchBudget(duration: Duration(seconds: 30)),
        )
        .expand((e) => e)
        .toList();
    if (contentType.isNotEmpty &&
        !contentType.toLowerCase().contains('text/html') &&
        !contentType.toLowerCase().contains('application/xhtml+xml')) {
      throw const ResearchFailure(ResearchFailureKind.protocol, 'unsupported_content');
    }
    final charset = RegExp(
      r'''charset=["']?([^;"' ]+)''',
      caseSensitive: false,
    ).firstMatch(contentType)?.group(1)?.toLowerCase();
    if (charset != null && !const ['utf-8', 'utf8', 'us-ascii'].contains(charset)) {
      throw const ResearchFailure(ResearchFailureKind.protocol, 'unsupported_encoding');
    }
    String document;
    try {
      document = utf8.decode(bytes);
    } on FormatException {
      throw const ResearchFailure(ResearchFailureKind.protocol, 'unsupported_encoding');
    }
    // Cache failure cannot turn an otherwise readable source into a failure.
    // Explicit reading always fetches again; cached HTML is not a freshness claim.
    try {
      await cancellation.bind(cache?.write(finalUrl, document) ?? Future<void>.value());
    } on ResearchFailure {
      rethrow;
    } catch (_) {
      /* Disposable cache is best effort. */
    }
    final article = await cancellation.bind(parser.parse(finalUrl, document, cancellation));
    cancellation.check();
    return markdownArticle(article);
  }
}

ExtractedContent markdownArticle(ReadableHtml article) {
  final document = html.parseFragment(article.html);
  for (final element in document.querySelectorAll('script,style,iframe,object,embed,form,meta,link,base,svg')) {
    element.remove();
  }
  String escape(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').replaceAllMapped(RegExp(r'[\\`*_\[\]<>]'), (m) => '\\${m[0]}');
  String render(Node node) {
    if (node is Text) return escape(node.data);
    if (node is! Element) return node.nodes.map(render).join();
    final body = node.nodes.map(render).join();
    switch (node.localName) {
      case 'br':
        return '\n';
      case 'hr':
        return '\n\n---\n\n';
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        return '\n\n${'#' * int.parse(node.localName!.substring(1))} ${body.trim()}\n\n';
      case 'p':
      case 'div':
      case 'section':
      case 'article':
      case 'blockquote':
        return '\n\n${body.trim()}\n\n';
      case 'li':
        return '\n- ${body.trim()}';
      case 'ul':
      case 'ol':
        return '\n\n${body.trim()}\n\n';
      case 'strong':
      case 'b':
        return '**$body**';
      case 'em':
      case 'i':
        return '*$body*';
      case 'pre':
        final text = node.text.trim();
        var fence = '```';
        while (text.contains(fence)) {
          fence += '`';
        }
        return '\n\n$fence\n$text\n$fence\n\n';
      case 'code':
        // Backslashes do not escape backticks inside CommonMark code spans.
        // A longer delimiter keeps source text from escaping into active markup.
        final text = node.text;
        if (!text.contains('`')) return '`$text`';
        var fence = '``';
        while (text.contains(fence)) {
          fence += '`';
        }
        return '$fence $text $fence';
      case 'a':
        final target = article.url.resolve(node.attributes['href'] ?? '');
        if (!['http', 'https'].contains(target.scheme) || target.userInfo.isNotEmpty) return body;
        return '[$body](${target.toString().replaceAll('(', '%28').replaceAll(')', '%29')})';
      case 'img':
        return escape(node.attributes['alt'] ?? '');
      case 'table':
        final rows = node
            .querySelectorAll('tr')
            .map(
              (row) => row.children
                  .where((e) => e.localName == 'td' || e.localName == 'th')
                  .map((e) => render(e).trim().replaceAll('|', '\\|').replaceAll('\n', ' '))
                  .toList(),
            )
            .toList();
        if (rows.isEmpty) return '';
        final width = rows.fold<int>(0, (n, row) => row.length > n ? row.length : n);
        String line(List<String> cells) => '| ${[...cells, ...List.filled(width - cells.length, '')].join(' | ')} |';
        return '\n\n${line(rows.first)}\n${line(List.filled(width, '---'))}\n${rows.skip(1).map(line).join('\n')}\n\n';
      default:
        return body;
    }
  }

  // Split only at top-level semantic blocks, so code blocks and tables retain
  // their internal newlines and cannot invent snapshot paragraph delimiters.
  final blocks = <String>[];
  void collect(Node node) {
    if (node is Element && const ['div', 'article', 'section', 'main'].contains(node.localName)) {
      for (final child in node.nodes) {
        collect(child);
      }
    } else {
      final value = render(node).trim();
      if (value.isNotEmpty) blocks.add(value);
    }
  }

  for (final node in document.nodes) {
    collect(node);
  }
  if (blocks.isEmpty) throw const ResearchFailure(ResearchFailureKind.protocol, 'unparseable');
  final counts = <String, int>{};
  final paragraphs = <String, String>{};
  for (final block in blocks) {
    final hash = sha256.convert(utf8.encode(block)).toString();
    final count = counts[hash] = (counts[hash] ?? 0) + 1;
    paragraphs['$hash-$count'] = block;
  }
  return ExtractedContent(
    url: article.url,
    title: article.title,
    paragraphs: paragraphs,
    canonicalUrl: article.canonicalUrl,
  );
}
