import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/assistant/assistant_controller.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/assistant/assistant_tasks.dart';
import 'package:marginmind/features/assistant/widgets/assistant_task_setup.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../packages/mm_assistant/test/assistant_summary_run_test.dart' show root;
import '../../../packages/mm_assistant/test/support.dart' show Reader;

class _Controller extends AssistantController {
  _Controller(this.conversation);
  final Conversation conversation;
  @override
  Conversation build() => conversation;
}

class _Services extends AssistantServicesController {
  @override
  Future<AssistantServices> build() async => AssistantServices(services: []);
}

class _Controls implements AssistantTaskControls {
  _Controls(this.changed);
  final void Function() changed;
  int pauses = 0, resumes = 0;
  @override
  RunContext get context => root();
  @override
  RunStatus status = RunStatus.running;
  @override
  bool saveFailed = false;
  @override
  int get completed => 1;
  @override
  int get total => 3;
  @override
  Future<void> pause() async {
    pauses++;
    status = RunStatus.paused;
    changed();
  }

  @override
  Future<void> resume() async {
    resumes++;
    saveFailed = false;
    status = RunStatus.running;
    changed();
  }

  @override
  Future<void> useModel(ModelReference model) async => throw StateError('Not selected');
}

void main() {
  testWidgets('same owner controls expose pause, resume and pending save retry at narrow width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final owner = AssistantTaskOwner(
      conversationState: sdk.AgentState(sessionId: 'conversation'),
      reader: Reader(),
      scope: ReadScope(studySetId: 'study'),
      requestId: 'question',
      mapId: 'map',
      baseRevision: 0,
      parents: {'root': null},
      online: false,
      execute: (_) async => throw StateError('UI only'),
    );
    final conversation = Conversation(
      id: 'conversation',
      studySetId: 'study',
      model: const AssistantModel(
        provider: AssistantProvider.ollama,
        model: 'fixture',
        endpoint: 'http://localhost:11434/v1',
      ),
      messages: [Message(id: 'answer', requestId: 'question', role: MessageRole.agent, status: MessageStatus.running)],
    );
    final container = ProviderContainer(
      overrides: [
        assistantControllerProvider.overrideWith(() => _Controller(conversation)),
        assistantServicesProvider.overrideWith(_Services.new),
      ],
    );
    addTearDown(container.dispose);
    late _Controls controls;
    void changed() => container
        .read(assistantTaskActivityProvider('study').notifier)
        .update(controls.context, TaskType.documentSummarize, controls.status, owner: owner);
    controls = _Controls(changed);
    owner.controls = controls;
    changed();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: MMTheme.light(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: AssistantTaskActivityView('study')),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('assistant-task-pause-resume')));
    await tester.pump();
    expect(controls.pauses, 1);
    expect(controls.status, RunStatus.paused);
    await tester.tap(find.byKey(const ValueKey('assistant-task-pause-resume')));
    await tester.pump();
    expect(controls.resumes, 1);
    controls.saveFailed = true;
    controls.status = RunStatus.paused;
    changed();
    await tester.pump();
    expect(find.text('Save'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(controls.resumes, 2);
    expect(owner.controls, same(controls));
    expect(tester.takeException(), isNull);
  });
}
