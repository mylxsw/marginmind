import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';
import '../assistant_controller.dart';

class ReadPermissionCard extends ConsumerWidget {
  const ReadPermissionCard({super.key, required this.messageId, required this.view});
  final String messageId;
  final ReadPermissionView view;

  Future<void> _decide(BuildContext context, WidgetRef ref, bool allow) async {
    try {
      await ref
          .read(assistantControllerProvider.notifier)
          .resolveReadPermission(messageId, view.request.id, allow: allow);
    } catch (_) {
      if (context.mounted) MMHud.show(context, context.l10n.assistantErrorFailed, icon: MMIcons.warning);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mmColors, t = context.mmText;
    final l = context.l10n;
    final request = view.request;
    final conversation = ref.watch(assistantControllerProvider);
    final live =
        !conversation.readOnly &&
        conversation.messages.any((m) => m.id == messageId && m.status == MessageStatus.running);
    final pending = live && view.status == ReadPermissionStatus.pending;
    final title = switch (view.status) {
      ReadPermissionStatus.pending => live ? l.assistantPermissionTitle : l.assistantPermissionCancelled,
      ReadPermissionStatus.allowed => l.assistantPermissionAllowed,
      ReadPermissionStatus.denied => l.assistantPermissionDenied,
      ReadPermissionStatus.cancelled => l.assistantPermissionCancelled,
    };
    final target = switch (request.kind) {
      ReadPermissionKind.pages => l.assistantPermissionPages(request.title, request.from!, request.to!),
      ReadPermissionKind.selection => l.assistantPermissionSelection(request.title),
      ReadPermissionKind.branch => l.assistantPermissionBranch(
        request.title.isEmpty ? l.assistantWholeMap : request.title,
      ),
      ReadPermissionKind.map => request.title.isEmpty ? l.assistantWholeMap : l.assistantMapContext(request.title),
    };
    return Semantics(
      container: true,
      liveRegion: pending,
      child: Container(
        margin: const EdgeInsets.only(bottom: MMSpacing.m),
        padding: const EdgeInsets.all(MMSpacing.m),
        decoration: BoxDecoration(
          color: c.researchTint,
          borderRadius: BorderRadius.circular(MMRadii.card),
          border: Border.all(color: c.separator),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: t.callout.copyWith(fontWeight: FontWeight.w600, color: c.label),
            ),
            const SizedBox(height: MMSpacing.s),
            Text(target, style: t.body.copyWith(color: c.label)),
            if (pending) ...[
              const SizedBox(height: MMSpacing.s),
              Text(l.assistantPermissionExplain, style: t.callout.copyWith(color: c.secondaryLabel)),
              const SizedBox(height: MMSpacing.xs),
              Text(l.assistantPermissionScope, style: t.footnote.copyWith(color: c.secondaryLabel)),
              const SizedBox(height: MMSpacing.m),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: MMSpacing.s,
                runSpacing: MMSpacing.s,
                children: [
                  MMButton(
                    key: ValueKey('permission-deny-${request.id}'),
                    label: l.assistantPermissionDeny,
                    onPressed: () => _decide(context, ref, false),
                  ),
                  MMButton(
                    key: ValueKey('permission-allow-${request.id}'),
                    label: l.assistantPermissionAllow,
                    variant: MMButtonVariant.primary,
                    color: c.research,
                    onPressed: () => _decide(context, ref, true),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
