import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';
import 'workspace_tabs_test.dart' show openTabs;

void main() {
  testWidgets('top controls undo document and map edits in order and redo both', (tester) async {
    final c = await openTabs(tester);
    final owner = c.read(workspaceProvider('demo-1').notifier);
    final undo = find.byKey(const ValueKey('workspace-undo'));
    final redo = find.byKey(const ValueKey('workspace-redo'));
    bool enabled(Finder button) => tester.widget<MMIconButton>(button).onPressed != null;
    expect(enabled(undo), isFalse);
    expect(enabled(redo), isFalse);
    final tabs = tester.getRect(find.byKey(const ValueKey('workspace-main-tabs')));
    expect(tester.getCenter(undo).dy, closeTo(tabs.center.dy, 1));
    expect(tester.getRect(redo).right, lessThanOrEqualTo(tabs.left));

    final annotation = owner.content.annotations.first;
    final originalColor = annotation.colorIndex;
    final nextColor = originalColor == MMAnnotationColor.blue.index ? MMAnnotationColor.yellow : MMAnnotationColor.blue;
    await owner.recolor(annotation.id, nextColor);
    final card = await owner.addTopic('History test');
    await tester.pumpAndSettle();
    expect(enabled(undo), isTrue);
    await tester.tap(undo);
    await tester.pumpAndSettle();
    expect(owner.content.card(card.id), isNull);
    expect(owner.content.annotations.firstWhere((a) => a.id == annotation.id).colorIndex, nextColor.index);
    await tester.tap(undo);
    await tester.pumpAndSettle();
    expect(owner.content.annotations.firstWhere((a) => a.id == annotation.id).colorIndex, originalColor);
    expect(enabled(undo), isFalse);
    expect(enabled(redo), isTrue);
    await tester.tap(redo);
    await tester.pumpAndSettle();
    expect(owner.content.annotations.firstWhere((a) => a.id == annotation.id).colorIndex, nextColor.index);
    await tester.tap(redo);
    await tester.pumpAndSettle();
    expect(owner.content.card(card.id), isNotNull);
    expect(enabled(redo), isFalse);
    await tester.tap(undo);
    await tester.pumpAndSettle();
    await owner.addTopic('New branch');
    await tester.pumpAndSettle();
    expect(enabled(redo), isFalse);
    expect(tester.takeException(), isNull);
    await settleHud(tester);
  });

  for (final size in [const Size(820, 1180), const Size(393, 852), const Size(320, 740)]) {
    testWidgets('history controls remain usable on touch at $size', (tester) async {
      final c = await openTabs(tester, size: size, touch: true);
      final owner = c.read(workspaceProvider('demo-1').notifier);
      final card = await owner.addTopic('Touch history');
      await tester.pumpAndSettle();
      final compact = size.width < 600;
      if (compact) {
        await tester.tap(find.byKey(const ValueKey('workspace-history')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('workspace-undo')));
      await tester.pumpAndSettle();
      expect(owner.content.card(card.id), isNull);
      if (compact) {
        await tester.tap(find.byKey(const ValueKey('workspace-history')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('workspace-redo')));
      await tester.pumpAndSettle();
      expect(owner.content.card(card.id), isNotNull);
      expect(tester.takeException(), isNull);
      await settleHud(tester);
    });
  }
}
