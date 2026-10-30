import 'package:integration_test/integration_test.dart';

import '../test/map_merge_test.dart' as merge;

// Use isolated in-memory content to exercise merge reflow and history in
// the native window without changing the user's library.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  merge.mergeViewportTests(native: true);
}
