import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart' show describeShortcut;

import '../../../app/app_commands.dart' show AppShortcuts;
import '../../../settings/settings_window.dart';
import '../../../shared/l10n.dart';
import '../assistant_controller.dart';
import '../assistant_services.dart';
import '../settings/model_settings.dart' show modelLabel;

/// The name the composer shows for the open conversation's model.
String conversationModelLabel(WidgetRef ref, AssistantModel model) {
  final services = ref.watch(assistantServicesProvider).value;
  return services == null ? model.model : modelLabel(services, model);
}

bool sameModel(AssistantModel a, AssistantModel b) =>
    a.model == b.model &&
    (a.serviceId == null || b.serviceId == null ? a.provider == b.provider : a.serviceId == b.serviceId);

/// The model menu above [anchor]: enabled models grouped by service, names
/// only, then “Manage Models…”. A choice changes this conversation only.
Future<void> showModelMenu(BuildContext context, WidgetRef ref, Rect anchor) async {
  final l = context.l10n;
  final services = await ref.read(assistantServicesProvider.future);
  if (!context.mounted) return;
  final current = ref.read(assistantControllerProvider).model;
  final controller = ref.read(assistantControllerProvider.notifier);
  final groups = [
    for (final s in services.services)
      if (services.enabledModelsByService[s.id] case final models? when models.isNotEmpty) (s, models),
  ];
  await showMMMenu(
    context,
    position: anchor.topLeft,
    minWidth: 220,
    entries: [
      for (final (i, (service, models)) in groups.indexed) ...[
        if (i > 0) const MMMenuDivider(),
        MMMenuHeader(service.name),
        for (final m in models)
          MMMenuItem(
            modelLabel(services, m),
            () => unawaited(controller.switchModel(m).catchError((Object _) {})),
            checked: sameModel(m, current),
          ),
      ],
      if (groups.isNotEmpty) const MMMenuDivider(),
      MMMenuItem(
        l.assistantManageModels,
        () => showSettings(context, tab: SettingsTab.models),
        shortcut: describeShortcut(AppShortcuts.settings),
        checked: groups.isEmpty ? null : false,
      ),
    ],
  );
}
