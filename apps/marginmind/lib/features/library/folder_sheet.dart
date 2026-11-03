import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../app/providers.dart';
import '../../shared/l10n.dart';
import '../workspace/widgets/notices.dart';

final libraryOrganizationProvider = StreamProvider.autoDispose<LibraryOrganization>((ref) {
  final repository = ref.watch(studySetRepositoryProvider);
  return repository is LibraryOrganizationRepository
      ? (repository as LibraryOrganizationRepository).watchOrganization()
      : Stream.value(LibraryOrganization());
});

Future<void> showFolderSheet(BuildContext context, {StudySet? move}) => showMMSheet<void>(
  context: context,
  width: 600,
  builder: (_) => FolderSheet(move: move),
);

/// Names being typed retain their observed revision when received updates
/// arrive. A stale save is rejected, leaving the input available to copy/retry.
class FolderSheet extends ConsumerStatefulWidget {
  const FolderSheet({super.key, this.move});
  final StudySet? move;
  @override
  ConsumerState<FolderSheet> createState() => _FolderSheetState();
}

class _FolderSheetState extends ConsumerState<FolderSheet> {
  final _name = TextEditingController();
  FolderEntry? _editing;
  bool _busy = false;
  String? _error;
  String? _observedPlacement;
  bool _placementLoaded = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<bool> _run(Future<void> Function(LibraryOrganizationRepository) action) async {
    if (_busy) return false;
    final repository = ref.read(studySetRepositoryProvider);
    if (repository is! LibraryOrganizationRepository) return false;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(repository as LibraryOrganizationRepository);
      return true;
    } on ContentSyncActionException catch (error) {
      if (mounted) {
        _error = error.reason == ContentSyncActionFailure.stale
            ? context.l10n.syncStale
            : context.l10n.syncInvalidCandidate;
      }
    } catch (_) {
      if (mounted) _error = context.l10n.syncActionFailed;
    } finally {
      if (mounted) {
        ref.invalidate(libraryOrganizationProvider);
        setState(() => _busy = false);
      }
    }
    return false;
  }

  Future<void> _save() async {
    final name = _name.text.trim(), editing = _editing;
    if (name.isEmpty || name.length > 256) {
      setState(() => _error = context.l10n.folderNameInvalid);
      return;
    }
    final saved = await _run((repository) async {
      if (editing == null) {
        await repository.createFolder(name);
      } else {
        await repository.renameFolder(editing.id, name, expectedRevision: editing.revision);
      }
    });
    if (saved && mounted) {
      setState(() {
        _editing = null;
        _name.clear();
      });
    }
  }

  Future<void> _delete(FolderEntry entry) async {
    final confirmed = await showConfirmSheet(
      context,
      title: context.l10n.deleteFolder,
      message: context.l10n.deleteFolderMessage,
      confirmLabel: context.l10n.delete,
    );
    if (confirmed && mounted) {
      await _run((repository) => repository.deleteFolder(entry.id, expectedRevision: entry.revision));
    }
  }

  Future<void> _move(String? folderId) async {
    if (!_placementLoaded) return;
    final set = widget.move!;
    final saved = await _run(
      (repository) => repository.moveStudySet(set.id, folderId, expectedFolderId: _observedPlacement),
    );
    if (saved && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final state = ref.watch(libraryOrganizationProvider);
    final placements = state.asData?.value.placements;
    if (!_placementLoaded && widget.move != null && placements?.containsKey(widget.move!.id) == true) {
      _observedPlacement = placements![widget.move!.id];
      _placementLoaded = true;
    }
    return MMSheet(
      title: widget.move == null ? l.manageFolders : l.moveToFolder,
      actions: [MMButton(label: l.closePanel, onPressed: _busy ? null : () => Navigator.of(context).pop())],
      child: SizedBox(
        height: (MediaQuery.sizeOf(context).height * .65).clamp(220, 620),
        child: ListView(
          key: const ValueKey('folder-list'),
          children: [
            if (_error != null)
              Text(
                _error!,
                key: const ValueKey('folder-error'),
                style: context.mmText.callout.copyWith(color: context.mmColors.caution),
              ),
            if (widget.move == null) ...[
              MMTextField(
                key: const ValueKey('folder-name'),
                controller: _name,
                semanticLabel: l.folderName,
                placeholder: l.folderName,
                enabled: !_busy,
                onSubmitted: (_) => _save(),
              ),
              Wrap(
                spacing: MMSpacing.s,
                children: [
                  MMButton(
                    key: const ValueKey('folder-save'),
                    label: _editing == null ? l.create : l.save,
                    onPressed: _busy ? null : _save,
                  ),
                  if (_editing != null)
                    MMButton(
                      label: l.cancel,
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _editing = null;
                              _name.clear();
                              _error = null;
                            }),
                    ),
                ],
              ),
            ] else ...[
              Text(widget.move!.title, style: context.mmText.headline),
              MMButton(
                key: const ValueKey('folder-unfiled'),
                label: l.libraryUnfiled,
                onPressed: _busy || !_placementLoaded ? null : () => _move(null),
              ),
            ],
            const SizedBox(height: MMSpacing.m),
            ...state.when(
              loading: () => [const Center(child: CircularProgressIndicator())],
              error: (_, _) => [
                Text(l.syncLoadFailed),
                MMButton(label: l.syncRetry, onPressed: () => ref.invalidate(libraryOrganizationProvider)),
              ],
              data: (organization) => [
                if (organization.syncEnabled) ...[
                  Text(l.syncLocalOnly, style: context.mmText.callout),
                  if (organization.queued > 0) Text(l.syncWaitingTransfer, style: context.mmText.callout),
                ],
                if (organization.repairNeeded) Text(l.folderRepairNeeded, style: context.mmText.callout),
                for (final entry in organization.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: MMSpacing.s),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.folder?.name ?? l.folderUnavailable, style: context.mmText.headline),
                        if (entry.folder != null)
                          Wrap(
                            spacing: MMSpacing.s,
                            children: [
                              if (widget.move != null)
                                MMButton(
                                  key: ValueKey('folder-move-${entry.id}'),
                                  label: l.moveToFolder,
                                  onPressed: _busy || !_placementLoaded ? null : () => _move(entry.id),
                                )
                              else ...[
                                MMButton(
                                  key: ValueKey('folder-rename-${entry.id}'),
                                  label: l.rename,
                                  onPressed: _busy
                                      ? null
                                      : () => setState(() {
                                          _editing = entry;
                                          _name.text = entry.folder!.name;
                                          _error = null;
                                        }),
                                ),
                                MMButton(
                                  key: ValueKey('folder-delete-${entry.id}'),
                                  label: l.delete,
                                  onPressed: _busy || entry.choices.isNotEmpty ? null : () => _delete(entry),
                                ),
                              ],
                            ],
                          ),
                        for (final problem in entry.problems)
                          Text(l.syncProblem(problem.name), style: context.mmText.callout),
                        for (final choice in entry.choices) ...[
                          Text('${l.syncCurrent}: ${entry.folder?.name ?? l.folderUnavailable}'),
                          Text('${l.syncCandidate}: ${choice.name}'),
                          Wrap(
                            spacing: MMSpacing.s,
                            children: [
                              for (final use in [false, true])
                                MMButton(
                                  key: ValueKey('folder-choice-${choice.transaction}-$use'),
                                  label: use ? l.syncUse : l.syncKeep,
                                  onPressed: _busy
                                      ? null
                                      : () => _run(
                                          (repository) => repository.chooseFolderName(
                                            entry.id,
                                            choice.transaction,
                                            expectedRevision: entry.revision,
                                            useCandidate: use,
                                          ),
                                        ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                if (organization.syncEnabled)
                  MMButton(
                    key: const ValueKey('folder-retry'),
                    label: l.syncRetry,
                    onPressed: _busy ? null : () => _run((repository) => repository.retryOrganization()),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
