import 'package:integration_test/integration_test.dart';

import '../test/map_command_bar_test.dart' as toolbar;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  toolbar.commandBarTests(native: true);
}
