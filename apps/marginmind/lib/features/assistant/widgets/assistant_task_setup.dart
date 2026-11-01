import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../assistant_routing.dart';
import '../assistant_controller.dart';
import '../assistant_tasks.dart';
import '../assistant_services.dart';
import '../settings/ai_task_status.dart';
import '../settings/model_route_picker.dart';

final assistantTaskRouteProvider = FutureProvider.autoDispose.family<RoutingRowState, (TaskType, ModelReference?)>((
  ref,
  selection,
) async {
  final spec = assistantTaskSpecs.firstWhere((spec) => spec.type == selection.$1);
  return ref
      .read(assistantModelResolverProvider)
      .inspect(
        TaskRequest<String>(
          spec: spec,
          input: {'question': 'preflight'},
          inputFingerprint: 'preflight',
          modelOverride: selection.$2,
        ),
        await ref.watch(assistantRoutingProvider.future),
      );
});

class AssistantTaskSetup {
  const AssistantTaskSetup(this.model, this.messages);
  final ModelReference? model;
  final List<String>? messages;
}

Future<AssistantTaskSetup?> showAssistantTaskSetup(BuildContext context, TaskSpec spec, Conversation conversation) =>
    showDialog<AssistantTaskSetup>(context: context, builder: (_) => _Setup(spec, conversation));

class _Setup extends ConsumerStatefulWidget {
  const _Setup(this.spec, this.conversation);
  final TaskSpec spec;
  final Conversation conversation;
  @override
  ConsumerState<_Setup> createState() => _SetupState();
}

class _SetupState extends ConsumerState<_Setup> {
  ModelReference? _model;
  late final _messages = {
    for (final m in widget.conversation.messages)
      if (m.status == MessageStatus.done && m.text.trim().isNotEmpty) m.id,
  };
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final route = ref.watch(assistantTaskRouteProvider((widget.spec.type, _model)));
    final catalog = ref.watch(assistantServicesProvider).value;
    final row = route.value;
    final issue = row == null ? null : routingIssueText(l, row.issue, failureCode: row.failureCode);
    final range = widget.spec.type == TaskType.conversationSummarize;
    return AlertDialog(
      title: Text(aiTaskName(l, widget.spec.type)),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ModelRoutePicker(
              label: row?.effective == null || catalog == null
                  ? l.aiTasksNotSet
                  : routeModelLabel(catalog, row!.effective!),
              tone: row?.issue == RoutingIssue.none
                  ? (_model == null ? ModelRouteTone.inherited : ModelRouteTone.explicit)
                  : ModelRouteTone.caution,
              groups: [
                for (final service in catalog?.services ?? <AssistantService>[])
                  if (service.enabled && (service.protocol != ServiceProtocol.ollama || service.localEnabled))
                    ModelRouteGroup(service.name, [
                      for (final model in service.models)
                        if (model.enabled)
                          ModelRouteOption(model: ModelReference(service.id, model.id), label: model.displayName),
                    ]),
              ],
              selected: _model,
              onChanged: (value) => setState(() => _model = value),
              followLabel: l.aiTasksUseSetting,
              semanticLabel: l.assistantModel,
              semanticValue: row?.modelLabel ?? '',
            ),
            if (issue != null)
              Padding(
                padding: const EdgeInsets.only(top: MMSpacing.s),
                child: RoutingIssueLine(text: issue),
              ),
            if (route.hasError) RoutingIssueLine(text: l.aiTasksIssueConnection),
            if (range)
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final message in widget.conversation.messages)
                        if (message.status == MessageStatus.done && message.text.trim().isNotEmpty)
                          CheckboxListTile(
                            value: _messages.contains(message.id),
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(message.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                            onChanged: (selected) => setState(() {
                              if (selected == true) {
                                _messages.add(message.id);
                              } else {
                                _messages.remove(message.id);
                              }
                            }),
                          ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        TextButton(
          onPressed: row?.issue == RoutingIssue.none && (!range || _messages.isNotEmpty)
              ? () => Navigator.pop(context, AssistantTaskSetup(_model, range ? _messages.toList() : null))
              : null,
          child: Text(l.assistantSend),
        ),
      ],
    );
  }
}

class AssistantConversationRouteControl extends ConsumerWidget {
  const AssistantConversationRouteControl({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversation = ref.watch(assistantControllerProvider);
    final ModelReference? selected;
    try {
      selected = conversationRoutingOverride(conversation.toJson(), TaskType.assistantChat);
    } on ConfigurationFailure {
      return RoutingIssueLine(text: context.l10n.aiTasksIssueInvalid);
    }
    final route = ref.watch(assistantTaskRouteProvider((TaskType.assistantChat, selected)));
    final catalog = ref.watch(assistantServicesProvider).value;
    final row = route.value;
    final l = context.l10n;
    final issue = row == null ? null : routingIssueText(l, row.issue, failureCode: row.failureCode);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ModelRoutePicker(
          label: row?.effective == null || catalog == null
              ? l.aiTasksNotSet
              : routeModelLabel(catalog, row!.effective!),
          tone: row?.issue == RoutingIssue.none
              ? selected == null
                    ? ModelRouteTone.inherited
                    : ModelRouteTone.explicit
              : ModelRouteTone.caution,
          groups: [
            for (final service in catalog?.services ?? <AssistantService>[])
              if (service.enabled && (service.protocol != ServiceProtocol.ollama || service.localEnabled))
                ModelRouteGroup(service.name, [
                  for (final model in service.models)
                    if (model.enabled)
                      ModelRouteOption(model: ModelReference(service.id, model.id), label: model.displayName),
                ]),
          ],
          selected: selected,
          followLabel: l.aiTasksUseSetting,
          semanticLabel: l.assistantModel,
          semanticValue: row?.modelLabel ?? '',
          onChanged: conversation.running
              ? null
              : (value) async {
                  final controller = ref.read(assistantControllerProvider.notifier);
                  if (value == null) {
                    await controller.followTaskSettings();
                    return;
                  }
                  final service = catalog?.services.where((s) => s.id == value.serviceId).firstOrNull;
                  final model = service?.models.where((m) => m.id == value.modelId).firstOrNull;
                  if (service != null && model != null) await controller.switchModel(service.configuration(model));
                },
        ),
        if (issue != null) RoutingIssueLine(text: issue),
      ],
    );
  }
}

class AssistantTaskActivityView extends ConsumerStatefulWidget {
  const AssistantTaskActivityView(this.studySetId, {super.key});
  final String studySetId;
  @override
  ConsumerState<AssistantTaskActivityView> createState() => _ActivityState();
}

class _ActivityState extends ConsumerState<AssistantTaskActivityView> {
  bool _acting = false;
  bool _failed = false;
  Future<void> _act(Future<void> Function() action) async {
    setState(() {
      _acting = true;
      _failed = false;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final conversation = ref.watch(assistantControllerProvider);
    final controller = ref.read(assistantControllerProvider.notifier);
    final activity = ref.watch(assistantTaskActivityProvider(widget.studySetId));
    final current = activity?.context.inputRange['conversationId'] == conversation.id ? activity : null;
    final controls = conversation.running ? current?.owner?.controls : null;
    final l = context.l10n;
    if (controls == null) {
      if (!controller.canResumeTask) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RoutingIssueLine(
            text: l.aiTasksRunUnfinished,
            action: l.fullTranslationActionResume,
            onAction: _acting ? null : () => _act(controller.resumeTask),
          ),
          if (_failed) RoutingIssueLine(text: l.aiTasksIssueConnection),
        ],
      );
    }
    final catalog = ref.watch(assistantServicesProvider).value;
    final snapshot = controls.context;
    final label = catalog == null ? snapshot.modelDisplayName : routeModelLabel(catalog, snapshot.config.model);
    final paused = {RunStatus.paused, RunStatus.partial, RunStatus.interrupted}.contains(controls.status);
    return Padding(
      padding: const EdgeInsets.only(bottom: MMSpacing.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: MMSpacing.s,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ModelRoutePicker(
                label: label,
                tone: ModelRouteTone.explicit,
                groups: [
                  for (final service in catalog?.services ?? <AssistantService>[])
                    if (service.enabled && (service.protocol != ServiceProtocol.ollama || service.localEnabled))
                      ModelRouteGroup(service.name, [
                        for (final model in service.models)
                          if (model.enabled)
                            ModelRouteOption(model: ModelReference(service.id, model.id), label: model.displayName),
                      ]),
                ],
                selected: snapshot.config.model,
                semanticLabel: l.assistantModel,
                semanticValue: label,
                onChanged: paused && !controls.saveFailed && !_acting
                    ? (model) {
                        if (model != null) _act(() => controls.useModel(model));
                      }
                    : null,
              ),
              RunStatusCapsule(
                status: controls.status,
                done: controls.completed,
                total: controls.total,
                unfinished: controls.total == null ? null : controls.total! - (controls.completed ?? 0),
              ),
              TextButton(
                key: const ValueKey('assistant-task-pause-resume'),
                onPressed: _acting ? null : () => _act(paused ? controls.resume : controls.pause),
                child: Text(
                  controls.saveFailed
                      ? l.save
                      : paused
                      ? l.fullTranslationActionResume
                      : l.fullTranslationActionPause,
                ),
              ),
            ],
          ),
          if (controls.saveFailed)
            RoutingIssueLine(
              text: l.aiTasksRunUnfinished,
              action: l.assistantRetry,
              onAction: _acting ? null : () => _act(controls.resume),
            ),
          if (_failed) RoutingIssueLine(text: l.aiTasksIssueConnection),
        ],
      ),
    );
  }
}
