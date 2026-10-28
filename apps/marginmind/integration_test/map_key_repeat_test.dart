import 'package:integration_test/integration_test.dart';

import '../test/map_keyboard_test.dart' as keyboard;

// Run the same focus/selection assertions in the native macOS application,
// with the in-memory fixtures supplied by the widget scenarios.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  keyboard.keyRepeatTests(native: true);
}
