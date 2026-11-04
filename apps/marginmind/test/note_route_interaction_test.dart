import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/assistant/assistant_routing.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/assistant/settings/model_route_picker.dart';
import 'package:marginmind/features/study_notes/note_model_route.dart';
import 'package:marginmind/features/study_notes/note_session.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import 'assistant_settings_test.dart' show Secrets;
import 'helpers.dart';
import 'study_notes_ai_ui_test.dart' show FakeNoteOrganizer, FakeNoteSession, generate;

const good = ModelReference('service', 'gpt-4.1-2025-04-14');
const unknown = ModelReference('service', 'unknown-fixture');
const deleted = ModelReference('service', 'deleted-fixture');
final service = AssistantService(
  id: 'service',
  protocol: ServiceProtocol.openai,
  name: 'Service',
  endpoint: 'https://api.openai.com/v1',
  models: const [
    ServiceModel(id: 'gpt-4.1-2025-04-14', name: 'Good Fixture'),
    ServiceModel(id: 'unknown-fixture', name: 'Unknown Fixture'),
  ],
);
Future<ProviderContainer> open(
  WidgetTester tester, {
  ModelReference? defaultModel,
  required Future<NoteSession> Function(ModelReference?) create,
}) async {
  final container = await pumpApp(
    tester,
    size: const Size(1600, 1100),
    prefs: {
      'settings.betaFeaturesEnabled': true,
      AssistantServicesStore.settingsKey: jsonEncode(AssistantServices(services: [service]).toJson()),
      AssistantRoutingStore.settingsKey: jsonEncode({
        'version': 1,
        'revision': 1,
        'defaults': {if (defaultModel != null) 'heavy': defaultModel.toJson()},
        'bindings': <String, dynamic>{},
        'heavyReasoning': 'auto',
      }),
    },
    overrides: [
      assistantSecretsProvider.overrideWithValue(
        Secrets()..values[AssistantServicesStore.account('service')] = 'fixture-only',
      ),
      noteSessionFactoryProvider.overrideWithValue(({studySetId, sessionId, modelOverride}) => create(modelOverride)),
    ],
  );
  container.read(navigationProvider.notifier).openStudySet('demo-1');
  await tester.pumpAndSettle();
  await tapWorkspaceCommand(tester, 'organize-note');
  await tester.pumpAndSettle();
  return container;
}

MMButton button(WidgetTester tester, String key) => tester.widget<MMButton>(find.byKey(ValueKey(key)));
Future<void> choose(WidgetTester tester, String name) async {
  await tester.tap(find.byType(ModelRoutePicker));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

const modelRequired = 'No model is selected.';
const modelDeleted = 'Model removed';
const serviceOff = 'Service off';

/// Generating over an unusable route explains itself and leaves the sheet open.
Future<void> expectBlocked(WidgetTester tester, String message) async {
  await generate(tester);
  await tester.pumpAndSettle();
  expect(find.textContaining(message), findsOneWidget);
  expect(button(tester, 'note-generate').onPressed, isNotNull);
}

void main() {
  testWidgets('no default: selecting the admitted override enables AI and forwards it without global writes', (
    tester,
  ) async {
    final calls = <ModelReference?>[];
    final container = await open(
      tester,
      create: (model) async {
        calls.add(model);
        return FakeNoteSession(FakeNoteOrganizer());
      },
    );
    final prefs = container.read(sharedPreferencesProvider);
    final original = prefs.getString(AssistantRoutingStore.settingsKey);
    expect(find.byType(NoteModelRoute), findsOneWidget);
    // AI actions stay available; only the attempt reports the missing model.
    await tester.tap(find.byKey(const ValueKey('depth-deep')));
    await tester.pumpAndSettle();
    await expectBlocked(tester, modelRequired);
    expect(calls, isEmpty);
    await choose(tester, 'Good Fixture');
    expect((await container.read(noteRoutingRowProvider(good).future)).ready, isTrue);
    expect(button(tester, 'depth-deep').onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('depth-deep')));
    await tester.pumpAndSettle();
    await generate(tester);
    await tester.pumpAndSettle();
    expect(calls, [good]);
    expect(prefs.getString(AssistantRoutingStore.settingsKey), original);
    expect(
      container.read(workspaceProvider('demo-1').notifier).content.studyNotes.single.settings.depth,
      NoteDepth.deep,
    );
    await tester.pump(const Duration(seconds: 5));
  });
  testWidgets('clearing to a deleted default and service invalidation block execution; restoring runs it again', (
    tester,
  ) async {
    var calls = 0;
    final container = await open(
      tester,
      defaultModel: deleted,
      create: (_) async {
        calls++;
        return FakeNoteSession(FakeNoteOrganizer());
      },
    );
    await choose(tester, 'Good Fixture');
    await tester.tap(find.byKey(const ValueKey('depth-context')));
    await tester.pumpAndSettle();
    expect(button(tester, 'note-generate').onPressed, isNotNull);
    final follow = tester.widget<ModelRoutePicker>(find.byType(ModelRoutePicker)).followLabel!;
    await choose(tester, follow);
    await expectBlocked(tester, modelDeleted);
    // Models without verified capabilities are admitted; dispatch reports real failures.
    await choose(tester, 'Unknown Fixture');
    expect((await container.read(noteRoutingRowProvider(unknown).future)).ready, isTrue);
    await choose(tester, 'Good Fixture');
    await tester.runAsync(
      () => container.read(assistantServicesProvider.notifier).upsert(service.copyWith(enabled: false)),
    );
    await tester.pumpAndSettle();
    await expectBlocked(tester, serviceOff);
    expect(calls, 0);
    await tester.runAsync(
      () => container.read(assistantServicesProvider.notifier).upsert(service.copyWith(enabled: true)),
    );
    await tester.pumpAndSettle();
    await generate(tester);
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 5));
  });
  testWidgets('explicit local depth stays local even after selecting a ready override', (tester) async {
    var calls = 0;
    final container = await open(
      tester,
      create: (_) async {
        calls++;
        return FakeNoteSession(FakeNoteOrganizer());
      },
    );
    await choose(tester, 'Good Fixture');
    await tester.tap(find.byKey(const ValueKey('depth-none')));
    await tester.pumpAndSettle();
    await generate(tester);
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(
      container.read(workspaceProvider('demo-1').notifier).content.studyNotes.single.settings.depth,
      NoteDepth.none,
    );
    await tester.pump(const Duration(seconds: 5));
  });
}
