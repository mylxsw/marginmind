import 'package:mm_data/mm_data.dart';
import 'package:mm_data/browser.dart';

Future<({FileLibraryStore store, ResearchWebCache? cache})> openStorage() async =>
    (store: await openBrowserLibrary(), cache: null);
