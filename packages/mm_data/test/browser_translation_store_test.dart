@TestOn('browser')
library;

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_data/src/library_browser_io.dart' show BrowserFiles;
import 'package:mm_data/src/library_io.dart' if (dart.library.js_interop) 'package:mm_data/src/library_browser_io.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

void main() {
  test('translation journal survives IndexedDB reopen, compact and removal', () async {
    final database = 'mm-translations-${newId()}';
    await BrowserFiles.open(name: database);
    final root = Directory('/Library/test.mmset');
    var store = FileTranslationStore(root);
    final now = DateTime.utc(2026);
    TranslationSegment segment(String text) => TranslationSegment(
      key: textKey('source', 'zh'),
      fingerprint: 'fp',
      page: 1,
      index: 0,
      text: text,
      model: 'm',
      profile: '',
      origin: TranslationOrigin.ai,
      at: now,
    );
    try {
      await store.append('doc', 'zh', segment('旧译文'));
      await store.append('doc', 'zh', segment('新译文'));
      await store.compact('doc', 'zh');
      BrowserFiles.close();
      await BrowserFiles.open(name: database);
      store = FileTranslationStore(root);
      final snapshot = await store.load('doc', 'zh');
      expect(snapshot.lineCount, 1);
      expect(snapshot.segments.values.single.text, '新译文');
      await store.remove('doc', 'zh');
      expect((await store.load('doc', 'zh')).segments, isEmpty);
      await store.removeDocument('doc');
      expect(await Directory('${root.path}/translations/doc').exists(), isFalse);
    } finally {
      BrowserFiles.close();
      web.window.indexedDB.deleteDatabase(database);
    }
  });
}
