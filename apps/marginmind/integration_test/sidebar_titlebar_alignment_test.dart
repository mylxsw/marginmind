import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:marginmind/settings/app_settings.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:window_manager/window_manager.dart';

import '../test/assistant_support.dart';

/// Uses isolated in-memory data and captures the native window, including
/// AppKit's traffic lights, rather than only Flutter's rendered content.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  const server = String.fromEnvironment('SIDEBAR_ALIGNMENT_SHOT_SERVER');

  testWidgets('sidebar buttons align with native traffic lights in both appearances and window sizes', (tester) async {
    await DesktopWindow.initialize(title: 'Foliarc · 侧栏对齐验证', minimumSize: MMSizes.windowMinSize);
    final app = await openAssistantApp(tester, settle: false);
    tester.view.reset();
    await pumpFor(tester, 20);
    for (final dark in [false, true]) {
      await app.container
          .read(settingsProvider.notifier)
          .setAppearance(dark ? AppearancePreference.dark : AppearancePreference.light);
      for (final width in [1280.0, 1000.0]) {
        await windowManager.setSize(Size(width, 820));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
        await pumpFor(tester, 20);
        for (final collapsed in [false, true]) {
          final button = find.byKey(ValueKey(collapsed ? 'workspace-show-sidebar' : 'workspace-hide-sidebar'));
          expect(button, findsOneWidget);
          expect(tester.getCenter(button).dy, 26);
          if (server.isNotEmpty) {
            final name = '${dark ? 'dark' : 'light'}-${width.toInt()}-${collapsed ? 'collapsed' : 'expanded'}';
            await tester.runAsync(() async {
              final client = HttpClient();
              try {
                final request = await client.getUrl(Uri.parse('$server/capture/$name?pid=$pid'));
                final response = await request.close();
                expect(response.statusCode, 200);
                await response.drain<void>();
              } finally {
                client.close(force: true);
              }
            });
          }
          await tester.tap(button);
          await pumpFor(tester, 20);
        }
      }
    }
    expect(tester.takeException(), isNull);
  });
}
