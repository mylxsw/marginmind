import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/main.dart' as app;
import 'package:marginmind/settings/app_settings.dart';
import 'package:mm_design/mm_design.dart';
import 'package:path_provider/path_provider.dart';

Future<void> idle(WidgetTester tester, [int seconds = 2]) async {
  for (var i = 0; i < seconds * 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('iPad cascading menus stay compact with finger-sized rows', (tester) async {
    const landscape = bool.fromEnvironment('IPAD_MENU_LANDSCAPE');
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    await app.main();
    await idle(tester, 6);
    final container = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    container.read(settingsProvider.notifier).setLanguage(LanguagePreference.en);
    container.read(settingsProvider.notifier).setAppearance(AppearancePreference.light);
    container.read(navigationProvider.notifier).showLibrary();
    await idle(tester);
    final sample = find.text('Open Sample Study Set');
    if (sample.evaluate().isNotEmpty) {
      await tester.tap(sample);
    } else {
      await tester.tap(find.textContaining('Sample:').first);
    }
    await idle(tester, 6);
    final route = container.read(navigationProvider) as WorkspaceRoute;
    final controller = container.read(workspaceProvider(route.studySetId).notifier);
    controller.openDocument(controller.content.documents.first.id);
    controller.setLayout(MMSplitMode.split);
    await idle(tester, 4);

    final marker = File('${(await getTemporaryDirectory()).path}/ipad-menu-shot');
    Future<void> shot(String name) async {
      await idle(tester);
      expect(tester.takeException(), isNull);
      if (!const bool.fromEnvironment('CAPTURE_IPAD_MENUS')) return;
      await tester.runAsync(() async {
        await marker.writeAsString(name);
        // The host saves the actual simulator screen, then acknowledges it.
        // ignore: avoid_print
        print('IPAD_MENU_SHOT:$name:${marker.path}');
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (await marker.readAsString() != 'captured:$name') {
          if (DateTime.now().isAfter(deadline)) throw TimeoutException('Screenshot not captured: $name');
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      });
    }

    // iPad multitasking can ignore orientation locks. Rotate the simulator
    // itself before running, and verify the actual viewport before labeling shots.
    expect(
      MediaQuery.orientationOf(tester.element(find.byType(AppShell))),
      landscape ? Orientation.landscape : Orientation.portrait,
    );
    final orientation = landscape ? 'landscape' : 'portrait';
    await tester.tap(find.byKey(const ValueKey('reader-more')).hitTestable().first);
    await shot('$orientation-reader-menu');
    await tester.tap(find.text('Switch Document').hitTestable().first);
    await shot('$orientation-document-submenu');
    final document = find.ancestor(
      of: find.text(controller.content.documents.first.title).hitTestable().last,
      matching: find.byType(MenuItemButton),
    );
    expect(tester.getSize(document).height, greaterThanOrEqualTo(44));
    // Selecting the active document closes both menu levels.
    await tester.tap(document);
    await idle(tester);
    expect(find.text('Switch Document').hitTestable(), findsNothing);
    await tester.tap(find.byKey(const ValueKey('map-more')).hitTestable().first);
    await shot('$orientation-map-menu');
    await tester.tap(find.text('Switch Map').hitTestable().first);
    await shot('$orientation-map-submenu');
    final leaf = find.byType(MenuItemButton).hitTestable().last;
    expect(tester.getSize(leaf).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(leaf).width, lessThan(328));
    await tester.tap(leaf);
    await idle(tester);
    expect(find.text('Switch Map').hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
