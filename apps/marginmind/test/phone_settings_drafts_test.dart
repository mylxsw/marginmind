import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/settings/settings_window.dart';
import 'package:mm_assistant/mm_assistant.dart';

import 'assistant_support.dart';

void main() {
  testWidgets('phone model draft survives category navigation, and discard never writes it', (tester) async {
    final app = await openAssistantApp(
      tester,
      size: const Size(393, 852),
      overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(true)],
    );
    final services = app.container.read(assistantServicesProvider.notifier);
    await services.upsert(
      AssistantService(
        id: 'draft',
        name: 'Local',
        protocol: ServiceProtocol.ollama,
        endpoint: 'http://localhost:11434/v1/chat/completions',
        localEnabled: true,
        models: const [ServiceModel(id: 'model', name: 'Model')],
      ),
    );
    showSettings(tester.element(find.byType(AppShell)), tab: SettingsTab.models);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('service-header-draft')));
    await tester.pumpAndSettle();
    final field = find.descendant(of: find.byKey(const ValueKey('service-name')), matching: find.byType(EditableText));
    await tester.enterText(field, 'Unsaved');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('service-header-draft')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('phone-settings-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-tab-models')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('service-header-draft')));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('service-header-draft')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('phone-settings-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-tasks-discard')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-tasks-discard')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsWindow), findsNothing);
    expect(
      app.container.read(assistantServicesProvider).value!.services.firstWhere((s) => s.id == 'draft').name,
      'Local',
    );
    expect(tester.takeException(), isNull);
  });
}
