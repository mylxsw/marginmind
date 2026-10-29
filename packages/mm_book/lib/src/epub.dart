part of '../mm_book.dart';

Book _epub(Uint8List bytes, int maxBytes, int maxEntries) {
  if (bytes.length > maxBytes) _limit();
  final zip = ZipDirectory()..read(InputMemoryStream(bytes));
  if (zip.fileHeaders.length > maxEntries) _limit();
  var size = 0;
  final files = <String, Uint8List>{};
  for (final header in zip.fileHeaders) {
    final entry = header.file;
    if (entry == null) _damaged('Missing ZIP local entry');
    if (header.filename != entry.filename || header.crc32 != entry.crc32) _damaged('Inconsistent ZIP headers');
    if (!const {0, 8}.contains(header.compressionMethod)) _unsupported('Unsupported EPUB ZIP compression');
    final name = _resolve('', header.filename);
    if (header.filename.endsWith('/')) continue;
    if ((header.externalFileAttributes >> 16 & 0xf000) == 0xa000) _damaged('ZIP symlinks are not permitted');
    if ((entry.flags & 1) != 0) throw const BookParseException(BookErrorKind.drm, 'Encrypted ZIP member');
    if (files.containsKey(name)) _damaged('Duplicate ZIP member');
    size += entry.uncompressedSize;
    if (size > maxBytes ||
        (entry.uncompressedSize > 1024 * 1024 && entry.uncompressedSize > entry.compressedSize * 200)) {
      _limit();
    }
    final data = entry.getStream().toUint8List();
    if (data.length != entry.uncompressedSize || getCrc32(data) != entry.crc32) _damaged('Invalid ZIP size or CRC');
    files[name] = data;
  }
  Uint8List readBytes(String path) => files[path] ?? _damaged('Missing EPUB member: $path');
  String read(String path) => utf8.decode(readBytes(path));
  Iterable<XmlElement> elements(XmlNode root, String name) =>
      root.descendants.whereType<XmlElement>().where((e) => e.name.local == name);
  final container = XmlDocument.parse(read('META-INF/container.xml'));
  final rootfile = elements(container, 'rootfile').firstOrNull;
  final rootPath = rootfile?.getAttribute('full-path');
  if (rootPath == null || rootPath.isEmpty) _damaged('Missing EPUB rootfile');
  final opfPath = _resolve('', rootPath);
  final opf = XmlDocument.parse(read(opfPath));
  final metadata = <String, List<String>>{};
  for (final m in elements(opf, 'metadata').expand((e) => e.childElements)) {
    final key = m.getAttribute('property') ?? m.name.local;
    metadata.putIfAbsent(key, () => []).add(m.innerText.trim());
  }
  final manifest = <String, (String, String, Set<String>)>{};
  for (final item in elements(opf, 'manifest').expand((m) => m.childElements)) {
    final id = item.getAttribute('id'), href = item.getAttribute('href');
    if (id == null || href == null || manifest.containsKey(id)) _damaged('Invalid EPUB manifest');
    manifest[id] = (
      _resolve(opfPath, href),
      item.getAttribute('media-type') ?? '',
      (item.getAttribute('properties') ?? '').split(RegExp(r'\s+')).toSet(),
    );
  }
  if (files.containsKey('META-INF/encryption.xml')) {
    final encryption = XmlDocument.parse(read('META-INF/encryption.xml'));
    for (final encrypted in elements(encryption, 'EncryptedData')) {
      final algorithm = elements(encrypted, 'EncryptionMethod').firstOrNull?.getAttribute('Algorithm');
      final href = elements(encrypted, 'CipherReference').firstOrNull?.getAttribute('URI');
      final path = href == null ? null : _resolve('', href);
      final font = manifest.values.where((m) => m.$1 == path).firstOrNull;
      // Obfuscation is permitted only on manifest-declared font resources.
      if (font == null ||
          !(font.$2.startsWith('font/') || font.$2.contains('font') || font.$2 == 'application/vnd.ms-opentype') ||
          !const {'http://www.idpf.org/2008/embedding', 'http://ns.adobe.com/pdf/enc#RC'}.contains(algorithm)) {
        throw const BookParseException(BookErrorKind.drm, 'EPUB uses encrypted content');
      }
      final data = Uint8List.fromList(readBytes(path!));
      final identifierId = opf.rootElement.getAttribute('unique-identifier');
      final identifier =
          elements(opf, 'identifier').where((e) => e.getAttribute('id') == identifierId).firstOrNull ??
          elements(opf, 'identifier').firstOrNull;
      if (identifier == null) _damaged('Missing font obfuscation identifier');
      List<int> key;
      int count;
      if (algorithm == 'http://www.idpf.org/2008/embedding') {
        key = sha1.convert(utf8.encode(identifier.innerText.replaceAll(RegExp(r'[\t\n\r ]'), ''))).bytes;
        count = 1040;
      } else {
        final uuid = identifier.innerText.trim().replaceFirst('urn:uuid:', '').replaceAll('-', '');
        if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(uuid)) _damaged('Invalid font UUID');
        key = [for (var i = 0; i < 32; i += 2) int.parse(uuid.substring(i, i + 2), radix: 16)];
        count = 1024;
      }
      for (var i = 0; i < data.length && i < count; i++) {
        data[i] ^= key[i % key.length];
      }
      files[path] = data;
    }
  }
  final diagnostics = <String>[];
  final chapters = <BookChapter>[];
  const parser = EpubParser();
  for (final ref in elements(opf, 'spine').expand((s) => s.childElements).where((e) => e.name.local == 'itemref')) {
    final item = manifest[ref.getAttribute('idref')];
    if (item == null) _damaged('Missing EPUB spine item');
    if (item.$2.isNotEmpty && !const {'application/xhtml+xml', 'text/html', 'image/svg+xml'}.contains(item.$2)) {
      _unsupported('Unsupported EPUB spine media type: ${item.$2}');
    }
    final document = html.parse(read(item.$1));
    for (final link in document.querySelectorAll('link[rel="stylesheet"]')) {
      final href = link.attributes['href'];
      if (href == null) continue;
      String path;
      try {
        path = _resolve(item.$1, href);
      } on FormatException {
        diagnostics.add('Blocked stylesheet URL: $href');
        continue;
      }
      if (!files.containsKey(path)) {
        diagnostics.add('Missing stylesheet: $path');
        continue;
      }
      final style = dom.Element.tag('style')
        ..attributes['data-mm-source'] = path
        ..text = read(path);
      link.replaceWith(style);
    }
    chapters.add(parser.parseHtml(item.$1, document.outerHtml, diagnostics));
  }
  if (chapters.isEmpty) _damaged('Empty EPUB spine');
  final toc = <BookTocEntry>[];
  BookTocEntry? target(String id, String label, String base, String href, List<BookTocEntry> children) {
    final path = _resolve(base, href);
    final chapter = chapters.where((c) => c.id == path).firstOrNull;
    if (chapter == null) {
      diagnostics.add('Unresolved TOC target: $href');
      return null;
    }
    final fragment = Uri.parse(href).fragment;
    var offset = 0;
    if (fragment.isNotEmpty) {
      final targetOffset = chapter.elementOffsets[fragment];
      if (targetOffset == null) {
        diagnostics.add('Unresolved TOC fragment: $href');
      } else {
        offset = targetOffset;
      }
    }
    return BookTocEntry(id, label, path, offset, children);
  }

  final nav = manifest.values.where((m) => m.$3.contains('nav')).firstOrNull;
  if (nav != null) {
    final doc = html.parse(read(nav.$1));
    final root = doc
        .querySelectorAll('nav')
        .where((n) => (n.attributes['epub:type'] ?? n.attributes['type'] ?? '').split(' ').contains('toc'))
        .firstOrNull;
    List<BookTocEntry> walk(dom.Element list, [String prefix = 'nav']) {
      final result = <BookTocEntry>[];
      var index = 0;
      for (final li in list.children.where((e) => e.localName == 'li')) {
        final id = '$prefix-${index++}';
        final a = li.children.where((e) => e.localName == 'a').firstOrNull;
        final nested = li.children.where((e) => e.localName == 'ol').firstOrNull;
        final children = nested == null ? <BookTocEntry>[] : walk(nested, id);
        if (a == null || a.attributes['href'] == null) {
          result.addAll(children);
          continue;
        }
        final entry = target(id, a.text.trim(), nav.$1, a.attributes['href']!, children);
        if (entry != null) result.add(entry);
      }
      return result;
    }

    final list = root?.children.where((e) => e.localName == 'ol').firstOrNull;
    if (list != null) toc.addAll(walk(list));
  }
  if (toc.isEmpty) {
    final ncxId = elements(opf, 'spine').firstOrNull?.getAttribute('toc');
    final ncx = manifest[ncxId] ?? manifest.values.where((m) => m.$2 == 'application/x-dtbncx+xml').firstOrNull;
    if (ncx != null) {
      final doc = XmlDocument.parse(read(ncx.$1));
      List<BookTocEntry> walk(XmlElement parent) => [
        for (final p in parent.childElements.where((e) => e.name.local == 'navPoint'))
          if (elements(p, 'content').firstOrNull?.getAttribute('src') case final String href)
            if (target(
                  p.getAttribute('id') ?? href,
                  elements(p, 'text').firstOrNull?.innerText ?? '',
                  ncx.$1,
                  href,
                  walk(p),
                )
                case final BookTocEntry e)
              e,
      ];
      final map = elements(doc, 'navMap').firstOrNull;
      if (map != null) toc.addAll(walk(map));
    }
  }
  return Book(
    metadata['title']?.firstOrNull ?? '',
    chapters,
    files,
    diagnostics,
    metadata: Map.unmodifiable(metadata.map((k, v) => MapEntry(k, List<String>.unmodifiable(v)))),
    toc: List.unmodifiable(toc),
    fixedLayout: metadata['rendition:layout']?.contains('pre-paginated') ?? false,
  );
}
