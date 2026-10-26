import 'dart:convert';
import 'dart:io';

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:test/test.dart';

void main() {
  test('360 legacy cards preserve exact due curve, serialize memory, and reopen without reinitialization', () async {
    final root = await Directory.systemTemp.createTemp('fsrs_migration_');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/sets/cohort.mmset/studyset.json');
    await file.parent.create(recursive: true);
    final bytes = await File('test/fixtures/fsrs-cohort.json').readAsBytes();
    await file.writeAsBytes(bytes);
    final before = StudySetContent.fromJson((jsonDecode(utf8.decode(bytes))['content'] as Map).cast());
    final store = FileLibraryStore(root);
    addTearDown(store.dispose);
    final after = await store.load('cohort');
    expect(after.memoryStates, hasLength(360));
    expect(after.reviews.map((r) => r.toJson()), before.reviews.map((r) => r.toJson()));
    expect(after.reviewLogs, isEmpty);
    for (var day = -14; day <= 91; day++) {
      final now = DateTime.utc(2026, 10, 26).add(Duration(days: day));
      expect(after.reviewQueue(now).map((c) => c.id), before.reviewQueue(now).map((c) => c.id));
    }
    await store.update('cohort', (c) => c);
    expect(jsonDecode(await file.readAsString())['content']['memoryStates'], hasLength(360));
    final reopened = FileLibraryStore(root);
    addTearDown(reopened.dispose);
    expect((await reopened.load('cohort')).toJson(), after.toJson());
    expect(await File('${file.path}.format-5.bak').readAsBytes(), bytes);
  });
}
