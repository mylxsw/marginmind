import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/study_notes/note_session.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'assistant_settings_test.dart' show Secrets;
import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('production session factory uses configured service and closes its connection idempotently', () async {
    final services = AssistantServices(
      services: [
        AssistantService(
          id: 'local',
          protocol: ServiceProtocol.ollama,
          name: 'Local',
          endpoint: 'http://localhost:11434/v1',
          localEnabled: true,
          models: const [ServiceModel(id: 'local-model')],
        ),
      ],
    );
    SharedPreferences.setMockInitialValues({AssistantServicesStore.settingsKey: jsonEncode(services.toJson())});
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance()),
        assistantSecretsProvider.overrideWithValue(Secrets()),
      ],
    );
    addTearDown(container.dispose);
    final session = await container.read(noteSessionFactoryProvider)();
    addTearDown(session.close);
    final organizer = session.organizer as ModelNoteOrganizer;
    expect(organizer.model, 'local-model');
    expect(session.usedFallback, isFalse);
    final settings = NoteSettings(depth: NoteDepth.none);
    final materials = const NoteMaterialCollector().collect(demoContent(), const WholeSet(), settings, now: testNow);
    final outline = await organizer.outline(materials, settings);
    final draft = await session.write(materials, outline, settings, 0).toList();
    expect(draft.single.blocks.single.ref, materials.highlights.single.ref);
    session.close();
    session.close();
    expect(organizer.cancelToken.isCancelled, isTrue);
  });
}
