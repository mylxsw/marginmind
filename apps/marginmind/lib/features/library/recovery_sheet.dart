import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../app/providers.dart';
import '../../shared/l10n.dart';

final libraryRecoveryEnabledProvider = FutureProvider.autoDispose<bool>((ref) {
  final repository = ref.watch(studySetRepositoryProvider);
  return repository is LibraryRecoveryRepository
      ? (repository as LibraryRecoveryRepository).libraryRecoveryEnabled
      : Future.value(false);
});

final libraryRecoveryProvider = StreamProvider.autoDispose<LibraryRecovery>((ref) {
  final repository = ref.watch(studySetRepositoryProvider);
  return repository is LibraryRecoveryRepository
      ? (repository as LibraryRecoveryRepository).watchLibraryRecovery()
      : Stream.value(LibraryRecovery());
});

Future<void> showLibraryRecovery(BuildContext context) =>
    showMMSheet<void>(context: context, width: 640, builder: (_) => const LibraryRecoverySheet());

class LibraryRecoverySheet extends ConsumerStatefulWidget {
  const LibraryRecoverySheet({super.key});
  @override
  ConsumerState<LibraryRecoverySheet> createState() => _LibraryRecoverySheetState();
}

class _LibraryRecoverySheetState extends ConsumerState<LibraryRecoverySheet> {
  LibraryRecoveryEntry? _selected;
  final _title = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _success = false;
  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _recover() async {
    final selected = _selected;
    if (_busy || selected == null || _title.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repository = ref.read(studySetRepositoryProvider) as LibraryRecoveryRepository;
      await repository.recoverLibraryCopy(selected, title: _title.text);
      if (mounted) {
        setState(() {
          _selected = null;
          _success = true;
        });
      }
    } on ContentSyncActionException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.reason == ContentSyncActionFailure.stale
              ? context.l10n.syncStale
              : context.l10n.syncInvalidCandidate,
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = context.l10n.recoveryFailed);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        ref.invalidate(libraryRecoveryProvider);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n, state = ref.watch(libraryRecoveryProvider);
    return PopScope(
      canPop: !_busy,
      child: MMSheet(
        title: l.libraryRecovery,
        actions: [MMButton(label: l.closePanel, onPressed: _busy ? null : () => Navigator.of(context).pop())],
        child: SizedBox(
          height: (MediaQuery.sizeOf(context).height * .65).clamp(220, 620),
          child: ListView(
            children: [
              Text(l.recoveryExplanation),
              const SizedBox(height: MMSpacing.m),
              if (_error != null) Text(_error!, key: const ValueKey('recovery-error')),
              if (_success) Text(l.recoveryCreated),
              if (_selected case final selected?) ...[
                Text(selected.title, style: context.mmText.headline),
                Text(selected.documents.join(' · ')),
                for (final text in selected.preview) Text(text, maxLines: 3, overflow: TextOverflow.ellipsis),
                if (selected.hasUnresolvedChoices) Text(l.recoveryPending),
                MMTextField(
                  key: const ValueKey('recovery-title'),
                  controller: _title,
                  semanticLabel: l.recoveryCopyTitle,
                  enabled: !_busy,
                  onSubmitted: (_) => _recover(),
                ),
                Wrap(
                  spacing: MMSpacing.s,
                  children: [
                    MMButton(
                      key: const ValueKey('recovery-confirm'),
                      label: l.recoverCopy,
                      onPressed: _busy ? null : _recover,
                    ),
                    MMButton(
                      label: l.cancel,
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _selected = null;
                              _error = null;
                            }),
                    ),
                  ],
                ),
              ] else
                ...state.when(
                  loading: () => [const Center(child: CircularProgressIndicator())],
                  error: (_, _) => [
                    Text(l.syncLoadFailed),
                    MMButton(label: l.syncRetry, onPressed: () => ref.invalidate(libraryRecoveryProvider)),
                  ],
                  data: (value) => [
                    if (value.entries.isEmpty) Text(l.recoveryEmpty),
                    for (final entry in value.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: MMSpacing.s),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entry.title, style: context.mmText.headline),
                            Text(entry.deleted ? l.recoveryDeletedSet : l.recoveryDeletedDocuments),
                            Text(l.recoveryContents(entry.cards, entry.documents.length)),
                            Text(entry.documents.join(' · ')),
                            for (final text in entry.preview) Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
                            if (entry.copyId != null)
                              Text(l.recoveryCreated)
                            else
                              MMButton(
                                label: l.recoverCopy,
                                onPressed: () => setState(() {
                                  _selected = entry;
                                  _title.text = l.recoveryDefaultTitle(entry.title);
                                  _error = null;
                                  _success = false;
                                }),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
