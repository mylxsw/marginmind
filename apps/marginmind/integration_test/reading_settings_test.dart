import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mm_platform/mm_platform.dart';

import '../test/reading_settings_design_test.dart' show verifyReadingSettingsFlow;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native reading settings matches selected design and remains interactive', (tester) async {
    await DesktopWindow.initialize(
      title: 'MarginMind — Reading Settings Check',
      minimumSize: const Size(960, 600),
      initialSize: const Size(1280, 820),
    );
    await verifyReadingSettingsFlow(tester, prefix: 'native-reading');
  });
}
