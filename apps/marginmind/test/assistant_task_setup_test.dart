import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/assistant/widgets/assistant_task_setup.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

class _Services extends AssistantServicesController {
  _Services(this.catalog);
  final AssistantServices catalog;
  @override
  Future<AssistantServices> build() async => catalog;
}

void main() {
  for (final width in [1000.0, 390.0]) {
    testWidgets('summary setup selects a branch range and shows its own route at $width', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final service = AssistantService(
        id: 'local',
        name: 'Local',
        protocol: ServiceProtocol.ollama,
        endpoint: 'http://localhost:11434/v1',
        localEnabled: true,
        models: [const ServiceModel(id: 'summary', name: 'Summary model')],
      );
      final conversation = Conversation(
        id: 'c',
        studySetId: 's',
        model: service.configuration(service.models.single),
        messages: [
          Message(id: 'one', requestId: 'one', role: MessageRole.user, text: 'First question'),
          Message(id: 'two', requestId: 'one', role: MessageRole.agent, text: 'Decision and open question'),
        ],
      );
      AssistantTaskSetup? selection;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            assistantServicesProvider.overrideWith(() => _Services(AssistantServices(services: [service]))),
            assistantTaskRouteProvider((TaskType.conversationSummarize, null)).overrideWith(
              (ref) async => const RoutingRowState(
                effective: ModelReference('local', 'summary'),
                source: RoutingSource.functionBinding,
                issue: RoutingIssue.none,
                modelLabel: 'Summary model',
              ),
            ),
          ],
          child: MaterialApp(
            theme: MMTheme.light(),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    selection = await showAssistantTaskSetup(context, conversationSummarySpec, conversation);
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Summary model'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNWidgets(2));
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(selection!.messages, ['two']);
      expect(selection!.model, isNull);
      expect(tester.takeException(), isNull);
    });
  }
}
