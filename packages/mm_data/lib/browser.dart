/// Browser composition entry point; only import through a web conditional import.
library;

import 'src/file_library_store.dart';
import 'src/library_browser_io.dart';

Future<FileLibraryStore> openBrowserLibrary() async {
  await BrowserFiles.open();
  return FileLibraryStore.browser();
}
