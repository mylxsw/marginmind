import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../app/providers.dart';
import '../../shared/l10n.dart';

final vocabularySyncProvider = StreamProvider.autoDispose<VocabularySyncState>((ref) {
  final repo = ref.watch(vocabularyRepositoryProvider);
  return repo is VocabularySyncRepository
      ? (repo as VocabularySyncRepository).watchVocabularySync()
      : Stream.value(VocabularySyncState());
});

class VocabularySyncButton extends ConsumerWidget {
  const VocabularySyncButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(vocabularySyncProvider);
    if (!state.hasError && state.value?.enabled != true) return const SizedBox.shrink();
    return MMButton(
      key: const ValueKey('vocabulary-sync-open'),
      label: context.l10n.syncTitle,
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const VocabularySyncSheet(),
      ),
    );
  }
}

class VocabularySyncSheet extends ConsumerStatefulWidget {
  const VocabularySyncSheet({super.key});
  @override
  ConsumerState<VocabularySyncSheet> createState() => _VocabularySyncSheetState();
}

class _VocabularySyncSheetState extends ConsumerState<VocabularySyncSheet> {
  bool _busy = false;
  String? _error;
  Future<void> _action(Future<void> Function(VocabularySyncRepository) action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(ref.read(vocabularyRepositoryProvider) as VocabularySyncRepository);
    } on ContentSyncActionException catch (e) {
      if (mounted) {
        _error = e.reason == ContentSyncActionFailure.editing ? context.l10n.syncEditing : context.l10n.syncStale;
      }
    } catch (_) {
      if (mounted) _error = context.l10n.syncActionFailed;
    } finally {
      if (mounted) {
        ref.invalidate(vocabularySyncProvider);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(MMSpacing.l),
        child: ref
            .watch(vocabularySyncProvider)
            .when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Column(
                children: [
                  Text(l.syncLoadFailed),
                  MMButton(label: l.syncRetry, onPressed: () => ref.invalidate(vocabularySyncProvider)),
                ],
              ),
              data: (state) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l.syncTitle, style: context.mmText.title3),
                  Text(l.syncLocalOnly),
                  if (_error != null) Text(_error!, key: const ValueKey('vocabulary-sync-error')),
                  if (state.repairNeeded) Text(l.syncRepair),
                  if (state.retryFailed) Text(l.syncActionFailed),
                  for (final problem in state.problems) Text(l.syncProblem(problem.name)),
                  if (state.editingEntries.isNotEmpty) Text(l.syncEditing),
                  if (state.conflicts.isEmpty) Text(l.syncNoConflicts),
                  for (final c in state.conflicts) ...[
                    const SizedBox(height: MMSpacing.l),
                    Text(c.term, style: context.mmText.headline),
                    Text(l.vocabularySyncField(c.field.name)),
                    for (final choice in c.choices)
                      Padding(
                        padding: const EdgeInsets.only(top: MMSpacing.s),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              choice.deleted == true
                                  ? l.vocabularyRemove
                                  : choice.deleted == false
                                  ? l.vocabularyKeep
                                  : c.field == VocabularySyncField.status
                                  ? (choice.text == 'known' ? l.vocabularyKnown : l.vocabularyLearning)
                                  : choice.text.isEmpty
                                  ? l.syncAbsent
                                  : choice.text,
                            ),
                            MMButton(
                              key: ValueKey('word-choice-${c.entryId}-${c.field.name}-${choice.id}'),
                              label: l.syncUse,
                              onPressed: _busy || state.editingEntries.contains(c.entryId)
                                  ? null
                                  : () => _action(
                                      (r) => r.chooseVocabulary(
                                        c.entryId,
                                        c.field,
                                        choice.id,
                                        expectedRevision: c.revision,
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  const SizedBox(height: MMSpacing.l),
                  MMButton(
                    key: const ValueKey('vocabulary-sync-retry'),
                    label: l.syncRetry,
                    onPressed: _busy ? null : () => _action((r) => r.retryVocabularySync()),
                  ),
                ],
              ),
            ),
      ),
    );
  }
}
