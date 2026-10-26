import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app_commands.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/shared/l10n.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import 'helpers.dart';
import 'reader_navigation_test.dart' show openReader, pressWithControl;
import 'reader_zoom_test.dart' show flatten;

void main() {
  testWidgets('the HUD stays above the page pill while a reader is open', (tester) async {
    final container = await pumpApp(tester);
    double hudBottom() => tester.widget<MMHudHost>(find.byType(MMHudHost)).bottom;
    expect(hudBottom(), MMHudHost.defaultBottom);

    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final controller = container.read(workspaceProvider('demo-1').notifier);
    controller.openDocument('c1');
    await tester.pumpAndSettle();
    expect(hudBottom(), pagePillClearance + MMSpacing.s);
    final pill = tester.getRect(find.text('1 / 164'));
    MMHud.show(tester.element(find.byType(ReaderPane)), 'Saved');
    await tester.pump();
    expect(tester.getRect(find.text('Saved')).bottom, lessThan(pill.top));

    controller.setLayout(MMSplitMode.secondary);
    await tester.pumpAndSettle();
    expect(hudBottom(), MMHudHost.defaultBottom, reason: 'no reader, no page pill');
    controller.setLayout(MMSplitMode.split);
    controller.closeDocument('c1');
    await tester.pumpAndSettle();
    expect(hudBottom(), MMHudHost.defaultBottom);
    await tester.pump(MMMotion.hud);
  });

  testWidgets('Go to Page opens the page field; the map alone has none', (tester) async {
    final r = await openReader(tester);
    final field = find.byType(MMInlineTextField);
    expect(field, findsNothing);
    await pressWithControl(tester, LogicalKeyboardKey.keyG, alt: true);
    expect(field, findsOneWidget);
    expect(
      tester.widget<TextField>(find.descendant(of: field, matching: find.byType(TextField))).focusNode!.hasFocus,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(field, findsNothing);

    // Asking again opens it again.
    await pressWithControl(tester, LogicalKeyboardKey.keyG, alt: true);
    expect(field, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    r.controller.setLayout(MMSplitMode.secondary);
    await tester.pumpAndSettle();
    await pressWithControl(tester, LogicalKeyboardKey.keyG, alt: true);
    expect(field, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Go menu has Go to Page… and View menu follows the full screen state', (tester) async {
    final container = await pumpApp(tester);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    container.read(workspaceProvider('demo-1').notifier).openDocument('c1');
    await tester.pumpAndSettle();
    final l = AppLocalizations.of(tester.element(find.byType(ReaderPane)));
    PlatformMenuItem item(String label) =>
        flatten(tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar)).menus).firstWhere((i) => i.label == label);

    final goToPage = item(l.goToPage);
    expect(goToPage.shortcut, AppShortcuts.goToPage);
    expect(goToPage.onSelected, isNotNull);
    goToPage.onSelected!();
    await tester.pumpAndSettle();
    expect(find.byType(MMInlineTextField), findsOneWidget);

    addTearDown(() => DesktopWindow.debugSetFullScreen(false));
    expect(item(l.enterFullScreen).shortcut, AppShortcuts.fullScreen);
    expect(item(l.enterFullScreen).onSelected, isNotNull);
    DesktopWindow.debugSetFullScreen(true);
    await tester.pumpAndSettle();
    expect(item(l.exitFullScreen).onSelected, isNotNull);
    expect(
      flatten(tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar)).menus).map((i) => i.label),
      isNot(contains(l.enterFullScreen)),
    );
    DesktopWindow.debugSetFullScreen(false);
    await tester.pumpAndSettle();
    expect(item(l.enterFullScreen), isNotNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  test('the gallery shortcut does not share Go to Page', () {
    expect(AppShortcuts.gallery.shift, isTrue);
    expect(AppShortcuts.goToPage.shift, isFalse);
  });
}
