import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../workspace_controller.dart';

Future<void> showMapSwitchSheet(BuildContext context, WidgetRef ref, String studySetId) async {
  final controller = ref.read(workspaceProvider(studySetId).notifier);
  final id = await showMMSheet<String>(
    context: context,
    width: 420,
    builder: (_) => _MapSwitchSheet(studySetId: studySetId),
  );
  if (id != null && context.mounted) await controller.selectMap(id);
}

class _MapSwitchSheet extends ConsumerWidget {
  const _MapSwitchSheet({required this.studySetId});
  final String studySetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceProvider(studySetId));
    final maps = state.content?.maps ?? [];
    final l = context.l10n;
    return MMSheet(
      title: l.switchMap,
      icon: MMIcons.mindMap,
      actions: [MMButton(label: l.cancel, onPressed: () => Navigator.of(context).pop())],
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .55),
        child: Material(
          type: MaterialType.transparency,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: maps.length,
            itemBuilder: (context, index) {
              final map = maps[index];
              final selected = map.id == state.activeMapId;
              return ListTile(
                key: ValueKey('map-switch-${map.id}'),
                leading: const Icon(MMIcons.mindMap),
                title: Text(map.title.isEmpty ? l.mainMap : map.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                selected: selected,
                trailing: selected ? const Icon(MMIcons.check) : null,
                onTap: () => Navigator.of(context).pop(map.id),
              );
            },
          ),
        ),
      ),
    );
  }
}
