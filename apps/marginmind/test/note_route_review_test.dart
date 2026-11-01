import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/study_notes/note_model_route.dart';
import 'package:mm_assistant/mm_assistant.dart';

import 'helpers.dart';

void main() {
  testWidgets('a configured model can be selected for notes without a default binding', (tester) async {
    final container = await pumpApp(
      tester,
      size: const Size(1600, 1100),
      prefs: {
        'settings.betaFeaturesEnabled': true,
        AssistantServicesStore.settingsKey: jsonEncode(
          AssistantServices(
            services: [
              AssistantService(
                id: 'service',
                protocol: ServiceProtocol.openai,
                name: 'Service',
                endpoint: 'https://api.openai.com/v1',
                models: [const ServiceModel(id: 'gpt-4.1-2025-04-14')],
              ),
            ],
          ).toJson(),
        ),
      },
      overrides: [noteAiAvailableProvider.overrideWith((ref) async => false)],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    await tapWorkspaceCommand(tester, 'organize-note');
    await tester.pumpAndSettle();
    expect(
      find.byType(NoteModelRoute),
      findsOneWidget,
      reason: 'No default must not hide the per-task model picker behind disabled AI depth controls.',
    );
  });
}
