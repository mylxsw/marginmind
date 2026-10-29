import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../../app/app_commands.dart';
import '../../../app/providers.dart';

import 'package:mm_assistant/mm_assistant.dart' show AssistantProvider;

import '../../../shared/l10n.dart';
import '../../../shared/pdf_picker.dart';
import '../../assistant/assistant_settings.dart';
import '../reader_compare.dart';
import '../workspace_controller.dart';
import 'notices.dart';

class ReaderCompareMenu extends ConsumerWidget {
  const ReaderCompareMenu({super.key, required this.studySetId, this.enabled = true, this.document, this.left = false});
  final String studySetId;
  final bool enabled, left;
  final Document? document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n, c = context.mmColors;
    final buttonSize = context.mmTouch ? context.mmToolbarButton : const Size(30, 26);
    final pair = ref.watch(readerCompareProvider(studySetId));
    final content = ref.watch(workspaceContentProvider(studySetId)) ?? StudySetContent.empty;
    final workspace = ref.read(workspaceProvider(studySetId).notifier);
    final current = pair?.leftDocumentId ?? ref.watch(workspaceProvider(studySetId).select((s) => s.activeDocumentId));
    String? docLanguage(Document doc) =>
        ref.watch(compareDocumentInfoProvider((studySetId, doc.id))).value?.language ?? compareLanguage(doc.title);
    final source = content.documents.where((d) => d.id == current).firstOrNull;
    final language = source == null ? null : docLanguage(source);
    bool recommended(Document d) => language != null && docLanguage(d) != null && docLanguage(d) != language;
    // Two stable passes preserve study-set order within each group.
    final others = content.documents.where((d) => left || d.id != current).toList();
    final ordered = left ? others : [...others.where(recommended), ...others.where((d) => !recommended(d))];
    final tooNarrow = MMSizeClass.of(context) == MMSizeClass.medium && MediaQuery.sizeOf(context).width < 874;
    final model = MMPlatformCapabilities.current.assistant ? ref.watch(assistantDefaultModelProvider) : null;
    final hasText = current == null
        ? null
        : ref.watch(compareDocumentInfoProvider((studySetId, current))).value?.hasText;
    final reason = model == null
        ? l.assistantConnectFirst
        : !(ref.watch(sharedPreferencesProvider).getBool(assistantOnlineKey(studySetId)) ??
                  ref.read(sharedPreferencesProvider).getBool('assistant.online') ??
                  true) &&
              model.provider != AssistantProvider.ollama
        ? l.compareAiOffline
        : hasText == false
        ? l.compareAiNeedsOcr
        : l.compareAiPending;

    Future<void> select(String id) async {
      try {
        final hidden = await ref
            .read(readerCompareProvider(studySetId).notifier)
            .select(id, left: left, readerWidth: ReaderCompareWidth.of(context));
        if (hidden && context.mounted) MMHud.show(context, l.compareMapHiddenHud(describeShortcut(AppShortcuts.view2)));
      } catch (_) {
        if (context.mounted) MMHud.show(context, l.somethingWentWrong);
      }
    }

    String? selectedId = left ? current : (pair?.right as PdfCompareTarget?)?.documentId;
    return PopupMenuButton<String>(
      key: document == null
          ? const ValueKey('reader-compare')
          : ValueKey(left ? 'compare-left-document' : 'compare-right-document'),
      enabled: enabled,
      tooltip: document == null ? l.compareReading : l.switchDocument,
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 340, maxWidth: 340),
      color: c.glassOpaque,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: c.hairline, width: .5),
      ),
      menuPadding: const EdgeInsets.all(4),
      onSelected: (value) async {
        if (value == 'exit') {
          ref.read(readerCompareProvider(studySetId).notifier).exit();
        } else if (value == 'import') {
          final files = await ref.read(pdfPickerProvider)(l.pdfFiles);
          if (files.isEmpty || !context.mounted) return;
          final before = workspace.content.documents.map((d) => d.id).toSet();
          final notice = await workspace.importDocuments(files, open: false);
          final imported = workspace.content.documents.where((d) => !before.contains(d.id)).lastOrNull;
          if (!context.mounted) return;
          if (notice.failed.isNotEmpty) showNotice(context, notice, rootTitle: '');
          if (imported != null && !tooNarrow) await select(imported.id);
        } else {
          await select(value);
        }
      },
      itemBuilder: (_) => [
        if (tooNarrow)
          PopupMenuItem<String>(
            enabled: false,
            height: 26,
            child: Text(l.compareTooNarrow, style: context.mmText.footnote),
          ),
        for (final doc in ordered)
          PopupMenuItem<String>(
            value: doc.id,
            enabled: !tooNarrow,
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            child: Semantics(
              selected: doc.id == selectedId,
              child: Row(
                children: [
                  Icon(doc.id == selectedId ? MMIcons.check : MMIcons.document, size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(doc.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.mmText.callout),
                  ),
                  if (!left && recommended(doc)) ...[const SizedBox(width: 6), MMPill(l.compareRecommended)],
                  if (docLanguage(doc) case final lang?) ...[
                    const SizedBox(width: 6),
                    Text(
                      lang == 'zh' ? l.languageCodeZh : l.languageCodeEn,
                      style: context.mmText.footnote.copyWith(color: c.secondaryLabel),
                    ),
                  ],
                ],
              ),
            ),
          ),
        if (!left) ...[
          PopupMenuItem<String>(value: 'import', height: 30, child: _menuRow(MMIcons.add, l.importPdf)),
          if (MMPlatformCapabilities.current.assistant) ...[
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              enabled: false,
              height: 50,
              child: Opacity(
                opacity: .5,
                child: Row(
                  children: [
                    const Icon(MMIcons.translate, size: 14),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l.compareAiTranslate(language == 'zh' ? l.languageEnglish : l.languageChinese),
                            style: context.mmText.callout,
                          ),
                          Text(reason, style: context.mmText.footnote.copyWith(color: c.secondaryLabel)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (pair != null) ...[
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              value: 'exit',
              height: 30,
              child: Row(
                children: [
                  const Icon(MMIcons.close, size: 14),
                  const SizedBox(width: 8),
                  Expanded(child: Text(l.compareExit)),
                  Text('Esc', style: context.mmText.footnote),
                ],
              ),
            ),
          ],
        ],
      ],
      child: document == null
          ? Container(
              width: buttonSize.width,
              height: buttonSize.height,
              decoration: BoxDecoration(
                color: pair == null ? Colors.transparent : c.accentTint,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                MMIcons.compare,
                size: 16,
                color: !enabled
                    ? c.secondaryLabel
                    : pair != null
                    ? c.accent
                    : c.icon,
              ),
            )
          : SizedBox(
              height: 24,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(MMIcons.document, size: 14),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      document!.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.mmText.callout.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(MMIcons.chevronDown, size: 10),
                ],
              ),
            ),
    );
  }

  Widget _menuRow(IconData icon, String label) =>
      Row(children: [Icon(icon, size: 14), const SizedBox(width: 8), Text(label)]);
}

/// Captured outside the toolbar so entry decisions use the full source width.
class ReaderCompareWidth extends InheritedWidget {
  const ReaderCompareWidth({super.key, required this.width, required super.child});
  final double width;
  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ReaderCompareWidth>()?.width ?? 0;
  @override
  bool updateShouldNotify(ReaderCompareWidth oldWidget) => width != oldWidget.width;
}

class ReaderCompareView extends ConsumerWidget {
  const ReaderCompareView({super.key, required this.studySetId, required this.viewport});
  final String studySetId;
  final Widget Function(Document document, int side) viewport;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pair = ref.watch(readerCompareProvider(studySetId))!;
    final content = ref.watch(workspaceContentProvider(studySetId))!;
    final session = ref.read(readerCompareProvider(studySetId).notifier);
    final l = context.l10n, c = context.mmColors;
    Widget column(String id, int side) {
      final doc = content.document(id);
      if (doc == null) return const SizedBox.shrink();
      return Expanded(
        child: Column(
          key: ValueKey('compare-column-$id'),
          children: [
            Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.separator, width: .5)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 230),
                        child: ReaderCompareMenu(studySetId: studySetId, document: doc, left: side == 0),
                      ),
                    ),
                  ),
                  if ((ref.watch(compareDocumentInfoProvider((studySetId, doc.id))).value?.language ??
                          compareLanguage(doc.title))
                      case final language?) ...[
                    const SizedBox(width: 6),
                    Container(
                      height: 15,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        border: Border.all(color: c.separator),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        language == 'zh' ? l.languageCodeZh : l.languageCodeEn,
                        style: context.mmText.footnote.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: c.secondaryLabel,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 6),
                  Consumer(
                    builder: (context, ref, _) {
                      final page =
                          ref.watch(readingPagesProvider(studySetId).select((pages) => pages[id])) ?? doc.lastPage;
                      return Text(l.pageNumber(page), style: context.mmText.callout.copyWith(color: c.secondaryLabel));
                    },
                  ),
                  if (side == 1) ...[
                    MMIconButton(
                      key: const ValueKey('compare-swap'),
                      icon: MMIcons.swapSides,
                      tooltip: l.compareSwap,
                      size: 24,
                      iconSize: 12,
                      onPressed: session.swap,
                    ),
                    MMIconButton(
                      key: const ValueKey('compare-exit'),
                      icon: MMIcons.close,
                      tooltip: '${l.compareExit} (Esc)',
                      size: 24,
                      iconSize: 12,
                      onPressed: session.exit,
                    ),
                  ],
                ],
              ),
            ),
            Expanded(child: viewport(doc, side)),
          ],
        ),
      );
    }

    Future<void> action(Future<void> Function() run) async {
      try {
        await run();
      } catch (_) {
        if (context.mounted) MMHud.show(context, l.somethingWentWrong);
      }
    }

    return Row(
      key: const ValueKey('reader-compare-view'),
      children: [
        column(pair.leftDocumentId, 0),
        Container(
          width: 34,
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: c.separator, width: .5),
              right: BorderSide(color: c.separator, width: .5),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: MMToolbarButton(
                  compact: true,
                  key: const ValueKey('compare-sync'),
                  icon: MMIcons.link,
                  tooltip: l.compareSync,
                  selected: pair.sync,
                  onPressed: () => action(session.toggleSync),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: 28,
                height: 28,
                child: MMToolbarButton(
                  compact: true,
                  key: const ValueKey('compare-align'),
                  icon: MMIcons.alignHere,
                  tooltip: l.compareAlign,
                  onPressed: () => action(() async {
                    if (await session.align() && context.mounted) {
                      MMHud.show(
                        context,
                        l.compareAlignedHud,
                        action: (l.undo, () => ref.read(workspaceProvider(studySetId).notifier).undo()),
                      );
                    }
                  }),
                ),
              ),
            ],
          ),
        ),
        column((pair.right as PdfCompareTarget).documentId, 1),
      ],
    );
  }
}
