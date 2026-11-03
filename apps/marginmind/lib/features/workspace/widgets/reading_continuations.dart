import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../app/providers.dart';
import '../../../shared/l10n.dart';
import '../workspace_controller.dart';

final readingContinuationsProvider = StreamProvider.autoDispose.family<ReadingContinuations, String>((ref, id) {
  final repository = ref.watch(contentRepositoryProvider);
  return repository is ReadingContinuationRepository
      ? (repository as ReadingContinuationRepository).watchReadingContinuations(id)
      : Stream.value(ReadingContinuations());
});

class ReadingContinuationsSection extends ConsumerStatefulWidget {
  const ReadingContinuationsSection({super.key, required this.studySetId});
  final String studySetId;
  @override
  ConsumerState<ReadingContinuationsSection> createState() => _ReadingContinuationsSectionState();
}

class _ReadingContinuationsSectionState extends ConsumerState<ReadingContinuationsSection> {
  bool _busy = false;
  String? _error;
  Future<void> _continue(ReadingContinuation choice) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(workspaceProvider(widget.studySetId).notifier).continueReading(choice, cancelled: () => !mounted);
      if (mounted) Navigator.of(context).pop();
    } on ContentSyncActionException catch (e) {
      if (mounted) {
        _error = switch (e.reason) {
          ContentSyncActionFailure.stale => context.l10n.syncStale,
          ContentSyncActionFailure.editing => context.l10n.syncEditing,
          ContentSyncActionFailure.invalidCandidate => context.l10n.readerPositionMissing,
        };
      }
    } catch (_) {
      if (mounted) _error = context.l10n.syncActionFailed;
    } finally {
      if (mounted) {
        ref.invalidate(readingContinuationsProvider(widget.studySetId));
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return ref
        .watch(readingContinuationsProvider(widget.studySetId))
        .when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => Column(
            children: [
              Text(l.syncLoadFailed),
              MMButton(
                label: l.syncRetry,
                onPressed: () => ref.invalidate(readingContinuationsProvider(widget.studySetId)),
              ),
            ],
          ),
          data: (status) {
            if (!status.enabled || status.items.isEmpty) return const SizedBox.shrink();
            final devices = status.items.map((c) => c.deviceId).toSet().toList()..sort();
            final material = MaterialLocalizations.of(context);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: MMSpacing.m),
                Text(l.readingContinuationsTitle, style: context.mmText.headline),
                Text(l.readingContinuationsHint, style: context.mmText.callout),
                if (_error != null) Text(_error!, key: const ValueKey('reading-continuation-error')),
                for (final choice in status.items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: MMSpacing.s),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(choice.title, style: context.mmText.headline),
                        Text(
                          '${l.readingOtherDevice(devices.indexOf(choice.deviceId) + 1)} · ${material.formatShortDate(choice.readAt.toLocal())} ${material.formatTimeOfDay(TimeOfDay.fromDateTime(choice.readAt.toLocal()))}',
                        ),
                        Text(
                          choice.position is PdfPosition
                              ? l.pageNumber((choice.position as PdfPosition).page)
                              : l.readingTextPosition,
                        ),
                        if (choice.availability != ReadingContinuationAvailability.ready)
                          Text(
                            choice.availability == ReadingContinuationAvailability.documentChanged
                                ? l.readingVersionChanged
                                : l.readingResourceMissing,
                          ),
                        MMButton(
                          key: ValueKey('reading-continue-${choice.deviceId}-${choice.documentId}'),
                          label: l.readingContinue,
                          onPressed:
                              _busy || status.editing || choice.availability != ReadingContinuationAvailability.ready
                              ? null
                              : () => _continue(choice),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        );
  }
}
