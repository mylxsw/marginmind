import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/window_title.dart';

void main() {
  test('titles omit empty and duplicate parts', () {
    expect(workspaceWindowTitle(' Doc ', 'Set', 'MarginMind'), 'Doc — Set — MarginMind');
    expect(workspaceWindowTitle('Set', 'Set', 'MarginMind'), 'Set — MarginMind');
    expect(workspaceWindowTitle('', '', 'MarginMind'), 'MarginMind');
  });
  test('serializes title writes, coalesces changes and stops on dispose', () async {
    final writes = <String>[];
    final pending = <Completer<void>>[];
    final queue = WindowTitleQueue((title) {
      writes.add(title);
      final c = Completer<void>();
      pending.add(c);
      return c.future;
    });
    queue.set('old');
    queue.set('middle');
    queue.set('latest');
    expect(writes, ['old']);
    pending.first.complete();
    await Future<void>.delayed(Duration.zero);
    expect(writes, ['old', 'latest']);
    pending.last.complete();
    await Future<void>.delayed(Duration.zero);
    queue.set('latest');
    expect(writes, hasLength(2));
    queue.dispose();
    queue.set('after dispose');
    expect(writes, hasLength(2));
  });
}
