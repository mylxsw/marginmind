// Run from repository root: dart run packages/mm_data/tool/fsrs_migration_curve.dart
import 'dart:convert';
import 'dart:io';

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';

Future<void> main() async {
  final root = await Directory.systemTemp.createTemp('fsrs_curve_');
  final store = FileLibraryStore(root);
  try {
    final file = File('${root.path}/sets/cohort.mmset/studyset.json');
    await file.parent.create(recursive: true);
    final bytes = await File('packages/mm_data/test/fixtures/fsrs-cohort.json').readAsBytes();
    await file.writeAsBytes(bytes);
    final before = StudySetContent.fromJson((jsonDecode(utf8.decode(bytes))['content'] as Map).cast());
    final after = await store.load('cohort');
    final csv = StringBuffer('date,before,after,delta\n');
    for (var day = -14; day <= 91; day++) {
      final date = DateTime.utc(2026, 10, 26).add(Duration(days: day));
      int count(StudySetContent c) =>
          c.reviews.where((r) => !r.due.isBefore(date) && r.due.isBefore(date.add(const Duration(days: 1)))).length;
      final a = count(before), b = count(after);
      if (a != b) throw StateError('Due curve changed at $date: $a -> $b');
      csv.writeln('${date.toIso8601String().substring(0, 10)},$a,$b,${b - a}');
    }
    final output = File('docs/evidence/gul-508/due-curve.csv');
    await output.parent.create(recursive: true);
    await output.writeAsString(csv.toString());
  } finally {
    await store.dispose();
    await root.delete(recursive: true);
  }
}
