import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/main.dart' as app;
import 'package:marginmind/settings/app_settings.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native status bar hides and shows with matching safe area', (tester) async {
    await app.main();
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(MarginMindApp)));
    final controller = container.read(settingsProvider.notifier);
    final original = container.read(settingsProvider).showSystemStatusBar;
    Future<double> top(bool visible) async {
      await controller.setShowSystemStatusBar(visible);
      await tester.pumpAndSettle();
      await Future<void>.delayed(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      final view = PlatformDispatcher.instance.views.first;
      return view.padding.top / view.devicePixelRatio;
    }

    try {
      final shown = await top(true);
      final hidden = await top(false);
      final restored = await top(true);
      // iPads without a camera cutout release the status bar's entire inset.
      // Phones retain the physical camera safe area even when status text hides.
      expect(shown, greaterThan(0));
      expect(hidden, lessThan(shown));
      expect(restored, shown);
      // ignore: avoid_print
      print('Native status bar top insets: shown=$shown hidden=$hidden restored=$restored');
    } finally {
      await controller.setShowSystemStatusBar(original);
      await tester.pumpAndSettle();
    }
  });
}
