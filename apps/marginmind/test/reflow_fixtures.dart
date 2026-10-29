import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:mm_book/mm_book.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';

Future<Document> storeBook(
  InMemoryStudySetContentRepository repo, {
  String id = 'book',
  Book? book,
  DocumentFormat format = DocumentFormat.markdown,
}) async {
  final parsed =
      book ??
      Book(
        'Reading notes',
        [
          const EpubParser().parseHtml('main', '''
<h1>Learning by reading</h1><p>Source anchors keep annotations stable when the text is reflowed.</p>
<p>A remembered position belongs to the original text, independent of font size.</p>
<h2>Retrieval practice</h2><p>Recall a passage and connect it to your map.</p>
${List.generate(25, (i) => '<p>Paragraph $i: Read, select, annotate and return to the source. 中文与 emoji 👩‍👩‍👧‍👦 remain intact.</p>').join()}
'''),
        ],
        {},
        [],
      );
  final base = 'books/$id/${parsed.revision}';
  final data = parsed.toJson();
  final files = <String, List<int>>{};
  final spine = <Map<String, Object>>[];
  for (final c in data['spine'] as List) {
    final bytes = utf8.encode(jsonEncode(c)), hash = sha256.convert(utf8.encode(jsonEncode(c))).toString();
    final path = '$base/chapters/$hash.json';
    files[path] = bytes;
    spine.add({'id': (c as Map)['id'] as String, 'path': path, 'sha256': hash});
  }
  final resources = <Map<String, Object?>>[];
  for (final r in data['resources'] as List) {
    final e = (r as Map).cast<String, Object?>();
    final source = e['path'] as String;
    final path = '$base/resources/${e['sha256']}.bin';
    files[path] = parsed.resources[source]!;
    resources.add({...e, 'sourcePath': source, 'path': path});
  }
  final manifest = '$base/manifest.json';
  files[manifest] = utf8.encode(jsonEncode({...data, 'spine': spine, 'resources': resources}));
  final doc = Document(
    id: id,
    title: parsed.title,
    fileName: manifest,
    contentManifest: manifest,
    revision: parsed.revision,
    format: format,
    layout: parsed.fixedLayout ? DocumentLayout.fixed : DocumentLayout.reflow,
    readingPosition: TextReadingPosition(revision: parsed.revision, chapterId: parsed.chapters.first.id, offset: 0),
    pageCount: parsed.fixedLayout ? parsed.chapters.length : 0,
    importedAt: DateTime(2026, 10, 29),
  );
  await repo.importDocumentPackage('demo-1', DocumentPackage(document: doc, files: files));
  return doc;
}
