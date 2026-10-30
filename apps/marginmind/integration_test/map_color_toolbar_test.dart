import 'package:integration_test/integration_test.dart';

import '../test/map_color_toolbar_test.dart' as colors;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  colors.mapColorToolbarTests(native: true);
}
