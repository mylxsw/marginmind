import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app_commands.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
import 'package:marginmind/shared/l10n.dart';
import 'package:mm_platform/mm_platform.dart';

import 'helpers.dart';

Iterable<PlatformMenuItem> flatten(Iterable<PlatformMenuItem> items) sync* {
  for (final item in items) {
    yield item;
    if (item is PlatformMenu) yield* flatten(item.menus);
    if (item is PlatformMenuItemGroup) yield* flatten(item.members);
  }
}

void main() {
  testWidgets('reader focus enables View zoom menus and keeps map fit separate', (tester) async {
    final container = await pumpApp(tester);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final l = AppLocalizations.of(tester.element(find.byType(ReaderPane)));
    final readerFocus = tester
        .widgetList<Focus>(find.descendant(of: find.byType(ReaderPane), matching: find.byType(Focus)))
        .firstWhere((f) => f.focusNode?.debugLabel == 'PDF reader')
        .focusNode!;
    readerFocus.requestFocus();
    await tester.pumpAndSettle();
    final context = readerFocus.context!;
    expect(Actions.maybeFind<ReaderZoomIntent>(context), isNotNull);
    for (final command in ReaderZoomCommand.values) {
      Actions.invoke(context, ReaderZoomIntent(command));
      await tester.pumpAndSettle();
    }
    // All shortcuts are registered in the real reader's focus subtree.
    for (final shortcut in readerZoomShortcuts.keys.cast<SingleActivator>()) {
      final modifier = shortcut.meta ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      if (shortcut.shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(shortcut.trigger);
      if (shortcut.shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
    }
    if (DesktopWindow.isMacOS) {
      PlatformMenuItem item(String label) =>
          flatten(tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar)).menus)
              .firstWhere((i) => i.label == label);
      for (final label in [l.zoomIn, l.zoomOut, l.pdfActualSize, l.pdfFitWidth, l.pdfFitPage]) {
        expect(item(label).onSelected, isNotNull);
        item(label).onSelected!();
        await tester.pumpAndSettle();
      }
      expect(item(l.fitMap).onSelected, isNull);
      expect(item(l.fitMap).shortcut, isNull);
      expect(item(l.pdfActualSize).shortcut, isNotNull);
      await tester.tap(find.byType(MindMapCanvas));
      await tester.pumpAndSettle();
      expect(item(l.pdfActualSize).onSelected, isNull);
      expect(item(l.fitMap).onSelected, isNotNull);
      expect(item(l.pdfActualSize).shortcut, isNull);
      expect(item(l.fitMap).shortcut, isNotNull);
    }
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant({TargetPlatform.macOS, TargetPlatform.linux}));
}
