import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../shared/l10n.dart';
import '../assistant/assistant_routing.dart';
import '../assistant/assistant_services.dart';
import '../assistant/settings/ai_task_status.dart';
import '../assistant/settings/model_route_picker.dart';

final noteRoutingRowProvider = FutureProvider.family<RoutingRowState, ModelReference?>((ref, model) async {
  final routing = await ref.watch(assistantRoutingProvider.future);
  ref.watch(assistantServicesProvider);
  return ref
      .read(assistantModelResolverProvider)
      .inspect(
        TaskRequest<Map<String, dynamic>>(
          spec: studyNotesSpec,
          input: const {'operation': 'text', 'data': <String, dynamic>{}},
          inputFingerprint: 'note-preflight',
          modelOverride: model,
        ),
        routing,
      );
});

final noteAiAvailableProvider = FutureProvider<bool>((ref) async {
  try {
    return (await ref.watch(noteRoutingRowProvider(null).future)).effective != null;
  } catch (_) {
    return false;
  }
});

class NoteModelRoute extends ConsumerWidget {
  const NoteModelRoute({super.key, required this.selected, required this.onChanged});
  final ModelReference? selected;
  final ValueChanged<ModelReference?> onChanged;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final catalog = ref.watch(assistantServicesProvider).value;
    final state = ref.watch(noteRoutingRowProvider(selected));
    final row = state.value;
    final effective = row?.effective;
    final label = catalog != null && effective != null ? routeModelLabel(catalog, effective) : l.aiTasksChooseModel;
    final issue = row == null ? null : routingIssueText(l, row.issue, failureCode: row.failureCode);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MMSpacing.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ModelRoutePicker(
            label: label,
            tone: row == null || row.issue != RoutingIssue.none
                ? ModelRouteTone.caution
                : selected == null
                ? ModelRouteTone.inherited
                : ModelRouteTone.explicit,
            groups: [
              if (catalog != null)
                for (final service in catalog.services.where((s) => s.enabled))
                  ModelRouteGroup(service.name, [
                    for (final model in service.models.where((m) => m.enabled))
                      ModelRouteOption(model: ModelReference(service.id, model.id), label: model.displayName),
                  ]),
            ],
            selected: selected,
            onChanged: onChanged,
            followLabel: l.aiTasksUseSetting,
            semanticLabel: l.aiTaskStudyNotes,
            semanticValue: label,
          ),
          if (issue != null) RoutingIssueLine(text: issue),
          if (state.hasError) RoutingIssueLine(text: l.aiTasksIssueUnknown),
        ],
      ),
    );
  }
}
