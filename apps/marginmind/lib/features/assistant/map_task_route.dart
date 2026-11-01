import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';

import '../../shared/l10n.dart';
import 'assistant_routing.dart';
import 'assistant_services.dart';
import 'settings/ai_task_status.dart';
import 'settings/model_route_picker.dart';

final mapTaskChoicesProvider = NotifierProvider<MapTaskChoices, Map<String, ModelReference>>(MapTaskChoices.new);

class MapTaskChoices extends Notifier<Map<String, ModelReference>> {
  @override
  Map<String, ModelReference> build() => {};
  void select(String key, ModelReference? model) {
    final next = {...state}..remove(key);
    if (model != null) next[key] = model;
    state = next;
  }
}

String mapRouteKey(String studySetId, TaskType type) => '$studySetId:${type.key}';

final mapTaskRouteProvider = FutureProvider.family<RoutingRowState, (String, TaskType)>((ref, scope) async {
  final (studySetId, type) = scope;
  final selected = ref.watch(mapTaskChoicesProvider)[mapRouteKey(studySetId, type)];
  ref.watch(assistantServicesProvider);
  final routing = await ref.watch(assistantRoutingProvider.future);
  return ref
      .read(assistantModelResolverProvider)
      .inspect(
        TaskRequest<String>(
          spec: type == TaskType.mapExpand ? mapExpandSpec : mapGenerateSpec,
          input: const {},
          inputFingerprint: 'route-preview',
          modelOverride: selected,
        ),
        routing,
      );
});

final mapTaskReadyProvider = FutureProvider.family<bool, (String, TaskType)>(
  (ref, scope) async => (await ref.watch(mapTaskRouteProvider(scope).future)).ready,
);

/// Domain setup uses the same resolver and real specs as execution.
class MapTaskRoute extends ConsumerWidget {
  const MapTaskRoute({super.key, required this.studySetId, required this.type});
  final String studySetId;
  final TaskType type;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final catalog = ref.watch(assistantServicesProvider).value;
    final row = ref.watch(mapTaskRouteProvider((studySetId, type)));
    final selected = ref.watch(mapTaskChoicesProvider)[mapRouteKey(studySetId, type)];
    return row.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => RoutingIssueLine(text: l.aiTasksIssueInvalid),
      data: (value) {
        final label = catalog == null || value.effective == null
            ? l.aiTasksUseSetting
            : routeModelLabel(catalog, value.effective!);
        final issue = routingIssueText(l, value.issue, failureCode: value.failureCode);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ModelRoutePicker(
              label: label,
              tone: value.issue == RoutingIssue.none
                  ? (selected == null ? ModelRouteTone.inherited : ModelRouteTone.explicit)
                  : ModelRouteTone.caution,
              groups: [
                for (final service in catalog?.services ?? <AssistantService>[])
                  if (service.enabled)
                    ModelRouteGroup(service.name, [
                      for (final model in service.models)
                        if (model.enabled)
                          ModelRouteOption(model: ModelReference(service.id, model.id), label: model.displayName),
                    ]),
              ],
              selected: selected,
              followLabel: l.aiTasksUseSetting,
              semanticLabel: l.aiTasksModel,
              semanticValue: label,
              onChanged: (model) =>
                  ref.read(mapTaskChoicesProvider.notifier).select(mapRouteKey(studySetId, type), model),
            ),
            if (issue != null) RoutingIssueLine(text: issue),
          ],
        );
      },
    );
  }
}
