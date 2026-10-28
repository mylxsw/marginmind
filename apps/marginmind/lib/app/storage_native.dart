import 'dart:io';

import 'package:mm_data/mm_data.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<({FileLibraryStore store, ResearchWebCache? cache})> openStorage() async {
  final support = await getApplicationSupportDirectory();
  return (store: FileLibraryStore(Directory(p.join(support.path, 'Library'))), cache: ResearchWebCache(support));
}
