import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../app/providers.dart';
import '../../../shared/l10n.dart';
import '../content_sync.dart';

Future<void> showContentSyncSheet(BuildContext context, String studySetId) => showMMSheet<void>(
  context: context,
  width: 680,
  builder: (_) => ContentSyncSheet(studySetId: studySetId),
);

class ContentSyncSidebarItem extends ConsumerWidget {
  const ContentSyncSidebarItem({super.key, required this.studySetId});
  final String studySetId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(contentSyncProvider(studySetId));
    final status = state.asData?.value;
    if (status?.enabled != true && !state.hasError) return const SizedBox.shrink();
    final attention = state.hasError || status!.needsAttention;
    final item = MMSidebarItem(
      key: const ValueKey('content-sync-open'),
      icon: attention ? MMIcons.warning : MMIcons.regenerate,
      label: context.l10n.syncTitle,
      trailing: attention ? Icon(MMIcons.warning, size: 14, color: context.mmColors.caution) : null,
      onTap: () => showContentSyncSheet(context, studySetId),
    );
    return MMInput.of(context).phone ? MMPhoneNavigationRow(item: item) : item;
  }
}

class ContentSyncSheet extends ConsumerStatefulWidget {
  const ContentSyncSheet({super.key, required this.studySetId});
  final String studySetId;
  @override
  ConsumerState<ContentSyncSheet> createState() => _ContentSyncSheetState();
}

class _ContentSyncSheetState extends ConsumerState<ContentSyncSheet> {
  bool _busy = false;
  String? _error;
  Future<void> _run(Future<void> Function(ContentSyncRepository) action) async {
    if (_busy) return;
    final repository = ref.read(contentRepositoryProvider);
    if (repository is! ContentSyncRepository) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(repository as ContentSyncRepository);
    } on ContentSyncActionException catch (error) {
      if (mounted) {
        _error = switch (error.reason) {
          ContentSyncActionFailure.stale => context.l10n.syncStale,
          ContentSyncActionFailure.editing => context.l10n.syncEditing,
          ContentSyncActionFailure.invalidCandidate => context.l10n.syncInvalidCandidate,
        };
      }
    } catch (_) {
      if (mounted) _error = context.l10n.syncActionFailed;
    } finally {
      if (mounted) {
        ref.invalidate(contentSyncProvider(widget.studySetId));
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final state = ref.watch(contentSyncProvider(widget.studySetId));
    return MMSheet(
      title: l.syncTitle,
      actions: [MMButton(label: l.closePanel, onPressed: () => Navigator.of(context).pop())],
      child: SizedBox(
        height: (MediaQuery.sizeOf(context).height * .65).clamp(220, 620),
        child: state.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.syncLoadFailed),
              MMButton(label: l.syncRetry, onPressed: () => ref.invalidate(contentSyncProvider(widget.studySetId))),
            ],
          ),
          data: (status) => ListView(
            key: const ValueKey('content-sync-status'),
            children: [
              Text(l.syncLocalOnly, style: context.mmText.callout),
              if (status.queued > 0)
                Padding(padding: const EdgeInsets.only(top: 8), child: Text(l.syncWaitingTransfer)),
              if (_error != null) _notice(_error!, key: const ValueKey('content-sync-error')),
              if (status.recoveryId case final recovery?)
                _notice(
                  l.syncRecovered,
                  action: MMButton(
                    key: const ValueKey('content-sync-acknowledge'),
                    label: l.syncAcknowledge,
                    onPressed: _busy
                        ? null
                        : () => _run((r) => r.acknowledgeContentRecovery(widget.studySetId, recovery)),
                  ),
                ),
              if (status.repairNeeded) _notice(l.syncRepair),
              if (status.retryFailed) _notice(l.syncActionFailed),
              if (status.editing) _notice(l.syncEditing),
              for (final problem in status.problems) _notice(l.syncProblem(problem.name)),
              if (status.enabled)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: MMButton(
                      key: const ValueKey('content-sync-retry'),
                      label: l.syncRetry,
                      onPressed: _busy ? null : () => _run((r) => r.retryContentSync(widget.studySetId)),
                    ),
                  ),
                ),
              if (status.conflicts.isNotEmpty)
                Text(l.syncConflictCount(status.conflicts.length), style: context.mmText.headline),
              for (final conflict in status.conflicts) _conflict(status, conflict),
              if (status.enabled && !status.needsAttention) Text(l.syncNoConflicts),
            ],
          ),
        ),
      ),
    );
  }

  Widget _notice(String text, {Widget? action, Key? key}) => Container(
    key: key,
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: context.mmColors.quaternaryFill, borderRadius: BorderRadius.circular(8)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: context.mmText.callout),
        if (action != null) Padding(padding: const EdgeInsets.only(top: 8), child: action),
      ],
    ),
  );

  Widget _conflict(ContentSyncStatus status, ContentSyncConflict conflict) {
    final l = context.l10n;
    final disabled = _busy || status.editing || status.revision == null;
    return Container(
      key: ValueKey('content-sync-conflict-${conflict.id}'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: context.mmColors.separator),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.syncChoiceHint, style: context.mmText.callout),
          for (final change in conflict.changes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${l.syncEntity(change.entity.name)}${change.title.isEmpty ? '' : ' · ${change.title}'}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: context.mmText.headline,
                  ),
                  Text(l.syncField(change.field.name), style: context.mmText.footnote),
                  const SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (_, constraints) {
                      final current = _value(l.syncCurrent, change.current),
                          candidate = _value(l.syncCandidate, change.candidate);
                      return constraints.maxWidth >= 480
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: current),
                                const SizedBox(width: 16),
                                Expanded(child: candidate),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [current, const SizedBox(height: 12), candidate],
                            );
                    },
                  ),
                ],
              ),
            ),
          if (!conflict.canUseCandidate)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(l.syncInvalidCandidate)),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              MMButton(
                key: ValueKey('content-sync-keep-${conflict.id}'),
                label: l.syncKeep,
                onPressed: disabled
                    ? null
                    : () => _run(
                        (r) => r.chooseContentSync(
                          widget.studySetId,
                          conflict.id,
                          expectedRevision: status.revision!,
                          useCandidate: false,
                        ),
                      ),
              ),
              MMButton(
                key: ValueKey('content-sync-use-${conflict.id}'),
                label: l.syncUse,
                onPressed: disabled || !conflict.canUseCandidate
                    ? null
                    : () => _run(
                        (r) => r.chooseContentSync(
                          widget.studySetId,
                          conflict.id,
                          expectedRevision: status.revision!,
                          useCandidate: true,
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _value(String label, String? value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: context.mmText.subheadline),
      const SizedBox(height: 4),
      SelectableText(
        value == null
            ? context.l10n.syncAbsent
            : value.isEmpty
            ? context.l10n.syncStructureValue
            : value,
        style: context.mmText.body,
      ),
    ],
  );
}
