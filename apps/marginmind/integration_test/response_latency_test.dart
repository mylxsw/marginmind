import 'package:integration_test/integration_test.dart';

import '../test/immediate_gestures_test.dart' as gestures;
import 'research_note_preview_test.dart' as native_pdf;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  gestures.immediateGestureTests(native: true);
  native_pdf.main();
}
