// Standalone simulator probe: build with -t tool/mobile_probe.dart, install once,
// launch, terminate, then relaunch. Unlike flutter test, it never uninstalls data.
import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:marginmind/main.dart' as app;
import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const secrets = KeychainSecretStore();
  final support = await getApplicationSupportDirectory();
  final marker = File('${support.path}/gul539-standalone');
  final store = FileLibraryStore(Directory('${support.path}/Library'));
  final verify = await marker.exists();
  if (verify) {
    if (await secrets.read('gul539.standalone') != 'device-only-probe') throw StateError('Credential lost');
    final id = await marker.readAsString();
    final content = await store.load(id);
    final bytes = await File(store.resolveFile(id, content.documents.single.fileName)).readAsBytes();
    if (String.fromCharCodes(bytes.take(4)) != '%PDF') throw StateError('PDF lost');
    // ignore: avoid_print
    print('GUL539_PERSISTED_OK');
  } else {
    await secrets.writeVerified('gul539.standalone', 'device-only-probe');
    final set = await store.create(const NewStudySet(title: 'Mobile persistence', colorIndex: 0));
    final asset = await rootBundle.load('assets/sample/sample.pdf');
    final source = File('${(await getTemporaryDirectory()).path}/probe.pdf');
    await source.writeAsBytes(asset.buffer.asUint8List());
    final name = await store.importFile(set.id, source.path);
    final editor = StudySetEditor(newId: newId, now: DateTime.now);
    await store.update(set.id, (c) => editor.addDocument(c, title: 'Imported PDF', fileName: name, pageCount: 1).$1);
    await source.delete();
    await marker.writeAsString(set.id);
  }
  await store.dispose();
  await app.main();
  if (!verify) {
    await Future<void>.delayed(const Duration(seconds: 3));
    unawaited(const MobileFileShare().share('probe.md', Uint8List.fromList('# Mobile export'.codeUnits)));
    await Future<void>.delayed(const Duration(seconds: 3));
    // ignore: avoid_print
    print('GUL539_SHARE_READY');
  }
}
