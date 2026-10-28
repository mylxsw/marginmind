import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:marginmind/main.dart' as app;
import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:path_provider/path_provider.dart';

// Build and install once, then terminate and launch the same binary twice.
// flutter test uninstalls afterward, so separate flutter test invocations cannot
// verify persistence. Host screenshots capture the native share sheet.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('mobile credentials, import persistence and system share', (tester) async {
    var verify = const bool.fromEnvironment('VERIFY_ONLY');
    const secrets = KeychainSecretStore();
    await tester.runAsync(() async {
      final support = await getApplicationSupportDirectory();
      final marker = File('${support.path}/gul539-imported');
      verify = verify || await marker.exists();
      final store = FileLibraryStore(Directory('${support.path}/Library'));
      if (!verify) {
        await secrets.write('gul539.probe', 'device-only-probe');
        expect(await secrets.read('gul539.probe'), 'device-only-probe');
        await secrets.write('gul539.delete', 'temporary');
        await secrets.delete('gul539.delete');
        expect(await secrets.read('gul539.delete'), isNull);
        final set = await store.create(const NewStudySet(title: 'Mobile import probe', colorIndex: 0));
        final data = await rootBundle.load('assets/sample/sample.pdf');
        final source = File('${(await getTemporaryDirectory()).path}/probe-source.pdf');
        await source.writeAsBytes(data.buffer.asUint8List());
        final name = await store.importFile(set.id, source.path);
        final editor = StudySetEditor(newId: newId, now: DateTime.now);
        await store.update(
          set.id,
          (c) => editor.addDocument(c, title: 'Imported PDF', fileName: name, pageCount: 1).$1,
        );
        await source.delete();
        await marker.writeAsString('ready');
      } else {
        expect(await secrets.read('gul539.probe'), 'device-only-probe');
        final sets = await store.watchAll().first;
        final set = sets.firstWhere((s) => s.title == 'Mobile import probe');
        final content = await store.load(set.id);
        final file = File(store.resolveFile(set.id, content.documents.single.fileName));
        expect(await file.length(), greaterThan(100));
        expect(String.fromCharCodes((await file.readAsBytes()).take(4)), '%PDF');
        // ignore: avoid_print
        print('GUL539_PERSISTED_OK');
      }
      await store.dispose();
      await app.main();
    });
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(MaterialApp), findsOneWidget);
    if (!verify) {
      unawaited(const MobileFileShare().share('probe.md', Uint8List.fromList('# Mobile export'.codeUnits)));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // ignore: avoid_print
      print('GUL539_SHARE_READY');
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 5)));
    }
  });
}
