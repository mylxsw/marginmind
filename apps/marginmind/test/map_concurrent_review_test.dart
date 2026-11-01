import 'package:flutter_test/flutter_test.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';

import 'map_task_recovery_test.dart' show Fixture;

void main() {
  test('two continuations of one saved workflow cannot buy the same missing stage twice', () async {
    final fixture = Fixture();
    await fixture.open();
    try {
      final original = fixture.session(mapGenerateSpec);
      await original.saveWorkflow({'request': {}, 'sourceRevision': 'same'});
      await original.execute('fixed', {'stage': 'complete'}, CancellationToken(), (_) => ValidationReport());
      final left = await fixture.restore(mapGenerateSpec, original.id!);
      final right = await fixture.restore(mapGenerateSpec, original.id!);
      final results = await Future.wait([
        left
            .execute('fixed', {'stage': 'next'}, CancellationToken(), (_) => ValidationReport())
            .then<Object>((v) => v, onError: (Object e) => e),
        right
            .execute('fixed', {'stage': 'next'}, CancellationToken(), (_) => ValidationReport())
            .then<Object>((v) => v, onError: (Object e) => e),
      ]);
      expect(results.whereType<String>(), isNotEmpty);
      expect(
        fixture.calls,
        2,
        reason: 'one complete stage plus one claimed missing stage; the other continuation must reuse or reject',
      );
    } finally {
      await fixture.close();
    }
  });
}
