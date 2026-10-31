import 'package:integration_test/integration_test.dart';

import '../test/map_attached_notes_test.dart' as notes;

// Native input, layout and fonts, using in-memory study sets only.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  notes.attachedNoteTests(native: true);
}
