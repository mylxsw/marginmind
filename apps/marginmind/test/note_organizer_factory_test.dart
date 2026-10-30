import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/assistant/note_organizer_factory.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'assistant_settings_test.dart' show Secrets;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<AssistantServicesStore> store(Secrets secrets, {bool configured = true, bool local = false}) async {
    final services = AssistantServices(
      services: configured
          ? [
              AssistantService(
                id: 'notes',
                protocol: local ? ServiceProtocol.ollama : ServiceProtocol.openai,
                name: 'Notes',
                endpoint: local ? 'http://localhost:11434/v1' : 'https://example.com/v1',
                localEnabled: local,
                models: const [ServiceModel(id: 'selected-model')],
              ),
            ]
          : [],
    );
    SharedPreferences.setMockInitialValues({AssistantServicesStore.settingsKey: jsonEncode(services.toJson())});
    return AssistantServicesStore(await SharedPreferences.getInstance(), secrets);
  }

  test('factory uses selected service and its existing credential account', () async {
    final secrets = Secrets()..values[AssistantServicesStore.account('notes')] = 'fake-key';
    final organizer = await createModelNoteOrganizer(services: await store(secrets), secrets: secrets);
    expect(organizer.model, 'selected-model');
    expect(organizer.budget.outputTokens, studyNoteBudget.outputTokens);
    organizer.close();
    expect(organizer.cancelToken.isCancelled, isTrue);
  });

  test('missing config and missing key report typed errors', () async {
    final secrets = Secrets();
    await expectLater(
      createModelNoteOrganizer(services: await store(secrets, configured: false), secrets: secrets),
      throwsA(isA<ResearchFailure>().having((e) => e.kind, 'kind', ResearchFailureKind.invalidRequest)),
    );
    await expectLater(
      createModelNoteOrganizer(services: await store(secrets), secrets: secrets),
      throwsA(isA<ResearchFailure>().having((e) => e.kind, 'kind', ResearchFailureKind.authentication)),
    );
  });

  test('explicitly enabled local service needs no cloud credential', () async {
    final secrets = Secrets();
    final organizer = await createModelNoteOrganizer(services: await store(secrets, local: true), secrets: secrets);
    expect(organizer.model, 'selected-model');
    organizer.close();
  });
}
