import 'package:integration_test/integration_test.dart';

import '../test/support/sync_native_acceptance.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  syncNativeAcceptance();
}
