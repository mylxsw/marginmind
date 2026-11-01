import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:path/path.dart' as p;

import '../../../app/providers.dart';
import '../../../shared/l10n.dart';
import '../assistant_routing.dart';
import '../assistant_services.dart';
import '../task_run_store.dart';
import 'ai_task_status.dart';

/// The read-only usage index for deletion checks, with what a resumable run
/// is called (its feature and study set).
abstract interface class AiRoutingUsageIndex implements RoutingUsageIndex {
  /// Valid after [listModelUses]; null for a run it did not list.
  (TaskType, String)? run(String runId);
}

/// Every study set's conversation archive and resumable runs, read through
/// the shared [PersistentTaskAssembly] composition. Nothing is migrated or
/// written, and a failed read fails the query rather than reporting no users.
class StudySetRoutingUsageIndex implements AiRoutingUsageIndex {
  StudySetRoutingUsageIndex({required this.studySets, required this.assembly});

  /// `(title, package directory)` of each study set kept on disk.
  final Future<List<(String, String)>> Function() studySets;
  final PersistentTaskAssembly Function(String directory) assembly;
  final _runs = <String, (TaskType, String)>{};

  @override
  (TaskType, String)? run(String runId) => _runs[runId];

  @override
  Future<List<RoutingUse>> listModelUses() async {
    final uses = <RoutingUse>[];
    _runs.clear();
    for (final (title, directory) in await studySets()) {
      final composed = assembly(directory);
      uses.addAll(await composed.usageIndex.listModelUses());
      for (final manifest in await composed.runs.resumable()) {
        _runs[manifest.context.runId] = (manifest.taskType, title);
      }
    }
    return List.unmodifiable(uses);
  }
}

final aiRoutingUsageIndexProvider = Provider<AiRoutingUsageIndex>(
  (ref) => StudySetRoutingUsageIndex(
    studySets: () async {
      if (kIsWeb) return const [];
      final content = ref.read(contentRepositoryProvider);
      return [
        for (final set in await ref.read(studySetsProvider.future))
          if (content.resolveFile(set.id, '') case final directory when p.isAbsolute(directory)) (set.title, directory),
      ];
    },
    assembly: (directory) => PersistentTaskAssembly(
      studySetDirectory: directory,
      tasks: TaskRegistry(),
      services: ref.read(assistantServicesStoreProvider),
      routing: ref.read(assistantRoutingStoreProvider),
      profiles: ref.read(assistantCapabilityProfilesProvider),
    ),
  ),
);

/// Who uses [model] (or any model of [serviceId]) as user-facing lines.
/// Throws when the archive or run index cannot be read.
Future<List<String>> routingUsageLines(
  WidgetRef ref,
  AppLocalizations l, {
  ModelReference? model,
  String? serviceId,
}) async {
  final index = ref.read(aiRoutingUsageIndexProvider);
  final uses = await RoutingUsage(
    routing: () => ref.read(assistantRoutingStoreProvider).load(),
    index: index,
  ).of(model: model, serviceId: serviceId);
  final lines = <String>[];
  var conversations = 0;
  final seen = <String>{};
  for (final use in uses) {
    final line = switch (use.kind) {
      RoutingUsageKind.categoryDefault =>
        use.id == TaskCategory.quick.name ? l.aiTasksQuickDefault : l.aiTasksHeavyDefault,
      RoutingUsageKind.functionBinding => switch (TaskType.fromKey(use.id)) {
        final type? => aiTaskName(l, type),
        null => use.id, // A feature from a newer version: still listed.
      },
      RoutingUsageKind.conversationOverride => null,
      RoutingUsageKind.recoverableRun => switch (index.run(use.id)) {
        (final type, final source) => l.aiTasksRunLabel(aiTaskName(l, type), source),
        null => use.id,
      },
    };
    if (use.kind == RoutingUsageKind.conversationOverride) {
      conversations++;
    } else if (seen.add('${use.kind.name}:${use.id}')) {
      lines.add(line!);
    }
  }
  if (conversations > 0) lines.add(l.aiTasksConversations(conversations));
  return lines;
}

/// Confirms removing a model or service that is in use: true to remove,
/// false to keep, null when nothing uses it (the caller's usual flow runs).
/// A failed usage query still asks, saying the usage could not be checked.
Future<bool?> confirmRoutedRemoval(
  BuildContext context,
  WidgetRef ref, {
  required String name,
  required String confirmLabel,
  ModelReference? model,
  String? serviceId,
}) async {
  final l = context.l10n;
  List<String>? lines;
  try {
    lines = await routingUsageLines(ref, l, model: model, serviceId: serviceId);
  } catch (_) {
    lines = null;
  }
  if (!context.mounted) return false;
  if (lines != null && lines.isEmpty) return null;
  final c = context.mmColors;
  final t = context.mmText;
  final shown = lines == null || lines.length <= 6 ? lines : [...lines.take(5), l.aiTasksMore(lines.length - 5)];
  final ok = await showMMSheet<bool>(
    context: context,
    builder: (context) => MMSheet(
      title: l.aiTasksRemoveTitle(name),
      actions: [
        MMButton(label: l.cancel, onPressed: () => Navigator.of(context).pop(false)),
        MMButton(
          key: const ValueKey('routed-remove-confirm'),
          label: confirmLabel,
          variant: MMButtonVariant.primary,
          color: c.critical,
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
      child: shown == null
          ? Text(l.aiTasksUsageUnavailable, key: const ValueKey('routed-usage-unavailable'), style: t.body)
          : Container(
              key: const ValueKey('routed-usage'),
              padding: const EdgeInsets.symmetric(horizontal: MMSpacing.m, vertical: MMSpacing.s),
              decoration: BoxDecoration(color: c.quaternaryFill, borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final line in shown)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.body),
                    ),
                ],
              ),
            ),
    ),
  );
  return ok ?? false;
}
