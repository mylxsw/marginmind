import 'package:mm_data/mm_data.dart';
import 'package:mm_data/browser.dart';

Future<({FileLibraryStore store, FileVocabularyStore vocabulary, ResearchWebCache? cache})> openStorage() async =>
    (store: await openBrowserLibrary(), vocabulary: FileVocabularyStore.browser(), cache: null);
