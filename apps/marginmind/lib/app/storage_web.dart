import 'package:mm_data/mm_data.dart';
import 'package:mm_data/browser.dart';

Future<({FileLibraryStore store, FileVocabularyStore vocabulary, ResearchWebCache? cache})> openStorage() async {
  final store = await openBrowserLibrary();
  return (store: store, vocabulary: FileVocabularyStore.browser(sync: await store.syncLedger), cache: null);
}
