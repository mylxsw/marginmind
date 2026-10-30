import 'package:integration_test/integration_test.dart';

import '../test/map_node_bar_test.dart' as toolbar;

// Exercise the selection-to-toolbar path in a native window using isolated
// in-memory fixtures, without opening or modifying the user's study sets.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  toolbar.toolbarResponseTests(native: true);
}
