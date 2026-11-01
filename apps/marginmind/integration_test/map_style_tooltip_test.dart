import 'package:integration_test/integration_test.dart';

import '../test/map_style_test.dart' as styles;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  styles.styleTooltipRegressionTests(native: true);
}
