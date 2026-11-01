import 'dart:io';

import 'package:marginmind/features/assistant/map_task_journal.dart';

// A real second process owns the workflow until the test asks it to exit.
// Intentionally skip release to exercise crash recovery, not orderly shutdown.
Future<void> main(List<String> args) async {
  await MapTaskJournal(args[0]).claimExecution(args[1]);
  stdout.writeln('ready');
  await stdin.first;
  exit(0);
}
