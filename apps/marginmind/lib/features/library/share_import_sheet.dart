import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../shared/l10n.dart';
import '../workspace/widgets/notices.dart';
import '../workspace/workspace_browser.dart';
import '../workspace/workspace_controller.dart';
import 'library_controller.dart';

final incomingSharesProvider = Provider<MMIncomingShareSource>((ref) {
  final source = MMIncomingShares();
  ref.onDispose(source.dispose);
  return source;
});

typedef ShareImportTarget = ({String? studySetId, String title});

/// Lives above route changes. Both startup and resume read the durable inbox;
/// native notifications are hints, rather than the only copy of an event.
class IncomingShareHost extends ConsumerStatefulWidget {
  const IncomingShareHost({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<IncomingShareHost> createState() => _IncomingShareHostState();
}

class _IncomingShareHostState extends ConsumerState<IncomingShareHost> with WidgetsBindingObserver {
  StreamSubscription<void>? _subscription;
  late final MMIncomingShareSource _source;
  final _handled = <String>{};
  bool _busy = false, _again = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _source = ref.read(incomingSharesProvider);
    _subscription = _source.changes.listen(
      (_) => _refresh(),
      onError: (Object _) {
        if (mounted) MMHud.show(context, context.l10n.somethingWentWrong);
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        final batches = await _source.pending();
        for (final batch in batches) {
          if (!mounted) return;
          if (!_handled.add(batch.id)) continue;
          try {
            if (batch.error != null) {
              MMHud.show(context, _shareError(context, batch.error!));
              continue;
            }
            Widget builder(BuildContext context) => ShareImportSheet(batch: batch);
            final target = await (MMInput.of(context).phone || MMSizeClass.of(context) == MMSizeClass.compact
                ? showMMBottomSheet<ShareImportTarget>(context: context, expand: false, builder: builder)
                : showMMSheet<ShareImportTarget>(
                    context: context,
                    width: MMSizes.incomingShareSheetWidth,
                    builder: builder,
                  ));
            if (target == null || !mounted) continue;
            final notice = await importSharedContent(ProviderScope.containerOf(context), batch, target);
            if (mounted && notice != null) showNotice(context, notice, rootTitle: '');
          } catch (_) {
            if (mounted) MMHud.show(context, context.l10n.somethingWentWrong);
          } finally {
            // Files stay available throughout parsing, including partial failure.
            // An unmounted app leaves the manifest for the next launch.
            if (mounted) {
              try {
                await _source.complete(batch.id);
              } catch (_) {
                if (mounted) MMHud.show(context, context.l10n.somethingWentWrong);
              }
            }
          }
        }
      } while (_again && mounted);
    } catch (_) {
      if (mounted) MMHud.show(context, context.l10n.somethingWentWrong);
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

String _shareError(BuildContext context, String error) => switch (error) {
  'unsupported' => context.l10n.incomingShareUnsupported,
  'limit' => context.l10n.incomingShareLimit,
  _ => context.l10n.somethingWentWrong,
};

/// Reuses the same import transaction and browser sessions as in-app entry.
Future<ImportedNotice?> importSharedContent(
  ProviderContainer container,
  MMIncomingShareBatch batch,
  ShareImportTarget target,
) async {
  final library = container.read(libraryViewProvider.notifier);
  if (batch.files.isNotEmpty) {
    if (target.studySetId == null) return library.createFromFiles(batch.files, title: target.title);
    await library.open(target.studySetId!);
    return container.read(workspaceProvider(target.studySetId!).notifier).importDocuments(batch.files);
  }
  final url = batch.url;
  if (url == null) return null;
  final id = target.studySetId ?? (await library.createBlank(target.title)).id;
  if (target.studySetId != null) await library.open(id);
  final browser = workspaceBrowserProvider(id);
  final lease = container.listen(browser, (_, _) {});
  try {
    container.read(browser.notifier).open(url);
    await WidgetsBinding.instance.endOfFrame;
  } finally {
    lease.close();
  }
  return null;
}

List<StudySet> shareImportStudySets(List<StudySet> sets, String? recentId, String query) {
  final search = query.trim().toLowerCase();
  final result = sets.where((s) => s.title.toLowerCase().contains(search)).toList();
  result.sort((a, b) {
    if (a.id == recentId && b.id != recentId) return -1;
    if (b.id == recentId && a.id != recentId) return 1;
    final recent = b.lastOpenedAt.compareTo(a.lastOpenedAt);
    return recent == 0 ? a.id.compareTo(b.id) : recent;
  });
  return result;
}

class ShareImportSheet extends ConsumerStatefulWidget {
  const ShareImportSheet({super.key, required this.batch});
  final MMIncomingShareBatch batch;

  @override
  ConsumerState<ShareImportSheet> createState() => _ShareImportSheetState();
}

class _ShareImportSheetState extends ConsumerState<ShareImportSheet> {
  late final TextEditingController _title;
  bool? _newSet;
  String? _selected;
  String _query = '';

  @override
  void initState() {
    super.initState();
    final batch = widget.batch;
    _title = TextEditingController(
      text: batch.files.isNotEmpty
          ? batch.files.first.name.replaceFirst(RegExp(r'\.[^.]+$'), '')
          : (batch.title?.trim().isNotEmpty == true ? batch.title!.trim() : batch.url?.host ?? ''),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    final data = ref.watch(studySetsProvider);
    final recent = ref.read(navigationProvider.notifier).recentStudySetId;
    final all = shareImportStudySets(data.value ?? [], recent, '');
    final visible = shareImportStudySets(all, recent, _query);
    final createNew = _newSet ?? (data.hasValue && all.isEmpty);
    final selected = visible.any((s) => s.id == _selected) ? _selected : visible.firstOrNull?.id;
    final enabled = createNew || (selected != null && data.hasValue);
    final submit = MMButton(
      label: createNew ? l.incomingShareCreate : l.incomingShareImport,
      variant: MMButtonVariant.primary,
      onPressed: !enabled
          ? null
          : () => Navigator.of(context).pop<ShareImportTarget>((
              studySetId: createNew ? null : selected,
              title: _title.text.trim().isEmpty ? l.newStudySetDefaultName : _title.text.trim(),
            )),
    );
    final batch = widget.batch;
    return MMSheet(
      title: l.incomingShareTitle,
      icon: batch.files.isEmpty ? MMIcons.web : MMIcons.import,
      titleTrailing: MMBottomSheet.contains(context) ? submit : null,
      actions: [
        MMButton(label: l.cancel, onPressed: () => Navigator.of(context).pop()),
        if (!MMBottomSheet.contains(context)) submit,
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(MMSpacing.m),
            decoration: BoxDecoration(color: c.quaternaryFill, borderRadius: BorderRadius.circular(MMRadii.card)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (batch.files.isEmpty) ...[
                  Text(
                    batch.title?.trim().isNotEmpty == true ? batch.title!.trim() : batch.url!.host,
                    style: context.mmText.headline,
                    maxLines: 2,
                  ),
                  Text(
                    batch.url.toString(),
                    style: context.mmText.footnote.copyWith(color: c.secondaryLabel),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ] else ...[
                  Text(l.incomingShareFiles(batch.files.length), style: context.mmText.headline),
                  for (final file in batch.files.take(3))
                    Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.mmText.callout),
                ],
              ],
            ),
          ),
          if (batch.url != null) ...[
            const SizedBox(height: MMSpacing.s),
            Text(l.incomingShareWebHint, style: context.mmText.footnote.copyWith(color: c.secondaryLabel)),
          ],
          const SizedBox(height: MMSpacing.l),
          MMSegmentedControl<bool>(
            expand: true,
            value: createNew,
            onChanged: (value) => setState(() => _newSet = value),
            segments: [
              MMSegment(value: false, label: l.incomingShareExisting),
              MMSegment(value: true, label: l.newStudySet),
            ],
          ),
          const SizedBox(height: MMSpacing.m),
          if (createNew)
            MMTextField(controller: _title, semanticLabel: l.newStudySetName, placeholder: l.newStudySetName)
          else ...[
            MMSearchField(placeholder: l.incomingShareSearch, onChanged: (value) => setState(() => _query = value)),
            const SizedBox(height: MMSpacing.s),
            if (data.hasError)
              MMButton(label: l.incomingShareRetry, onPressed: () => ref.invalidate(studySetsProvider))
            else if (!data.hasValue)
              const Center(child: CircularProgressIndicator.adaptive())
            else if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.all(MMSpacing.m),
                child: Text(l.incomingShareNoResults, style: context.mmText.callout.copyWith(color: c.secondaryLabel)),
              )
            else
              for (final set in visible)
                MMInteractive(
                  semanticLabel: set.title,
                  semanticValue: set.id == recent ? l.incomingShareRecent : null,
                  selected: set.id == selected,
                  onTap: () => setState(() => _selected = set.id),
                  builder: (context, state) => Container(
                    constraints: const BoxConstraints(minHeight: MMSizes.touchTarget),
                    padding: const EdgeInsets.all(MMSpacing.s),
                    decoration: BoxDecoration(
                      color: set.id == selected
                          ? c.accentTint
                          : state.hovered
                          ? c.quaternaryFill
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(MMRadii.row),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          set.id == selected ? MMIcons.radioSelected : MMIcons.radio,
                          size: MMSpacing.l,
                          color: set.id == selected ? c.accent : c.secondaryLabel,
                        ),
                        const SizedBox(width: MMSpacing.s),
                        Expanded(
                          child: Text(
                            set.title,
                            style: context.mmText.body,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (set.id == recent)
                          Text(l.incomingShareRecent, style: context.mmText.footnote.copyWith(color: c.secondaryLabel)),
                      ],
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}
