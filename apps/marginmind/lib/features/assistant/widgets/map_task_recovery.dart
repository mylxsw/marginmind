import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/l10n.dart';
import '../../map_generation/map_generation_controller.dart';
import '../expansion_controller.dart';
import '../map_task_factory.dart';

/// This entry only reads the domain index. A user action is required before
/// recovering an interrupted paid request or continuing missing stages.
class MapTaskRecovery extends ConsumerWidget {
  const MapTaskRecovery({super.key, required this.studySetId, required this.canContinue, this.taskType});
  final String studySetId;
  final bool canContinue;
  final String? taskType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final failures = ref.watch(mapSaveFailuresProvider).where((s) => s.studySetId == studySetId).toList();
    final tasks = canContinue ? ref.watch(mapRecoverableTasksProvider(studySetId)).asData?.value ?? [] : [];
    final matchingTasks = tasks.where((task) => taskType == null || task['type'] == taskType).toList();
    if (failures.isEmpty && matchingTasks.isEmpty) return const SizedBox.shrink();
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            if (failures.isNotEmpty) Text(l.mapTaskSaveFailed),
            for (final session in failures)
              TextButton(
                key: ValueKey('map-retry-save-${session.id}'),
                onPressed: session.retryingSave ? null : session.retrySave,
                child: Text(l.mapTaskRetrySave),
              ),
            if (matchingTasks.isNotEmpty)
              PopupMenuButton<Map<String, dynamic>>(
                tooltip: l.mapTaskContinue,
                child: Padding(padding: const EdgeInsets.all(8), child: Text(l.mapTaskContinue)),
                itemBuilder: (_) => [
                  for (final task in matchingTasks)
                    PopupMenuItem(
                      value: task,
                      child: Text(
                        '${task['type'] == 'mapGenerate' ? l.mapTaskGenerate : l.mapTaskExpand} · '
                        '${(task['workflow'] as Map)['request']['title'] ?? (task['workflow'] as Map)['request']['mapId']}',
                      ),
                    ),
                ],
                onSelected: (task) async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(l.mapTaskContinue),
                      content: Text(l.mapTaskContinueNotice),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
                        TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l.mapTaskContinue)),
                      ],
                    ),
                  );
                  if (confirmed != true || !context.mounted) return;
                  try {
                    if (task['type'] == 'mapGenerate') {
                      await ref.read(mapGenerationControllerProvider(studySetId).notifier).continueTask(task['id']);
                    } else {
                      await ref.read(expansionControllerProvider(studySetId).notifier).continueTask(task['id']);
                    }
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.mapTaskCannotContinue)));
                    }
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}
