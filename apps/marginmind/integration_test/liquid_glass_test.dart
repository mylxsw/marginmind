import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/main.dart' as app;
import 'package:marginmind/settings/app_settings.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_pdf/mm_pdf.dart';

Future<void> idle(WidgetTester tester, int seconds) async {
  for (var i = 0; i < seconds * 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> capture(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull);
  // The host captures the actual simulator screen during this interval.
  // ignore: avoid_print
  print('SHOT:$name');
  await idle(tester, 3);
}

/// Library, reader and map of a phone in light and dark, with the floating
/// glass tab bar and toolbar over content, and frame timings of scrolling
/// and map dragging beneath them.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('phone Liquid Glass chrome over library, reader and map', (tester) async {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await app.main();
    await idle(tester, 6);
    final container = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final navigation = container.read(navigationProvider.notifier);
    navigation.showLibrary();
    await idle(tester, 2);
    await tester.tap(find.text('Open Sample Study Set'));
    await idle(tester, 6);
    // Enough study sets for the library to scroll beneath the bars.
    final repository = container.read(studySetRepositoryProvider);
    for (var i = 0; i < 8; i++) {
      await repository.create(NewStudySet(title: 'Study set ${i + 1}', colorIndex: i % 6));
    }
    final route = container.read(navigationProvider) as WorkspaceRoute;
    final workspace = container.read(workspaceProvider(route.studySetId).notifier);
    workspace.openDocument(workspace.content.documents.first.id);
    await idle(tester, 4);

    for (final appearance in [AppearancePreference.light, AppearancePreference.dark]) {
      final name = appearance.name;
      await container.read(settingsProvider.notifier).setAppearance(appearance);
      await tester.tap(find.byKey(const ValueKey('mm-tab-0')));
      await idle(tester, 2);
      final library = find.byType(CustomScrollView).first;
      // Partway down: cards pass beneath the toolbar and the tab bar.
      await tester.drag(library, const Offset(0, -160));
      await idle(tester, 2);
      await capture(tester, '$name-library');
      if (appearance == AppearancePreference.light) {
        await binding.watchPerformance(() async {
          for (var i = 0; i < 3; i++) {
            await tester.fling(library, const Offset(0, -500), 1500);
            await tester.pumpAndSettle();
            await tester.fling(library, const Offset(0, 500), 1500);
            await tester.pumpAndSettle();
          }
        }, reportKey: 'library_scroll');
      }

      await tester.tap(find.byKey(const ValueKey('mm-tab-1')));
      await idle(tester, 4);
      final pdf = find.byType(MMPdfView);
      await tester.drag(pdf, const Offset(0, -300));
      await idle(tester, 3);
      await capture(tester, '$name-reader');
      if (appearance == AppearancePreference.light) {
        await binding.watchPerformance(() async {
          for (var i = 0; i < 3; i++) {
            await tester.fling(pdf, const Offset(0, -600), 1500);
            await tester.pumpAndSettle();
            await tester.fling(pdf, const Offset(0, 600), 1500);
            await tester.pumpAndSettle();
          }
        }, reportKey: 'reader_scroll');
      }

      await tester.tap(find.byKey(const ValueKey('mm-tab-2')));
      await idle(tester, 3);
      await capture(tester, '$name-map');
      if (appearance == AppearancePreference.light) {
        final map = find.byType(MindMapCanvas);
        await binding.watchPerformance(() async {
          for (var i = 0; i < 3; i++) {
            await tester.timedDrag(map, const Offset(-160, -220), const Duration(milliseconds: 800));
            await tester.pumpAndSettle();
            await tester.timedDrag(map, const Offset(160, 220), const Duration(milliseconds: 800));
            await tester.pumpAndSettle();
          }
        }, reportKey: 'map_drag');
      }
      expect(find.byKey(const ValueKey('mm-tab-bar-glass')), findsOneWidget);
      expect(find.byKey(const ValueKey('mm-glass-bar')), findsOneWidget);
    }
    // ignore: avoid_print
    print('SHOT:done');
    expect(tester.takeException(), isNull);
  });
}
