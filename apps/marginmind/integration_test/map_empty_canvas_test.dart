import 'package:integration_test/integration_test.dart';

import '../test/map_empty_canvas_test.dart' as canvas;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  canvas.main();
}
