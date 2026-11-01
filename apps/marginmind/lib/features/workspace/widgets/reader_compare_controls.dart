import 'dart:async';

import '../../../shared/document_icon.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../app/app_commands.dart';

import 'package:mm_platform/mm_platform.dart';

import '../../../shared/l10n.dart';
import '../../../shared/pdf_picker.dart';
import '../reader_compare.dart';
import 'reader_translation_view.dart';
import 'reading_settings.dart';
import '../workspace_controller.dart';
import 'notices.dart';

class ReaderCompareSubmenu<T> extends PopupMenuEntry<T> {
  const ReaderCompareSubmenu({super.key, required this.studySetId, this.enabled = true});
  final String studySetId;
  final bool enabled;
  @override
  double get height => MMSizes.dropdownRowHeight;
  @override
  bool represents(T? value) => false;
  @override
  State<ReaderCompareSubmenu<T>> createState() => _ReaderCompareSubmenuState<T>();
}

class _ReaderCompareSubmenuState<T> extends State<ReaderCompareSubmenu<T>> {
  @override
  Widget build(BuildContext context) => ReaderCompareMenu<T>(
    studySetId: widget.studySetId,
    enabled: widget.enabled,
    menuLabel: context.l10n.compareReading,
  );
}

class ReaderCompareMenu<T> extends ConsumerWidget {
  const ReaderCompareMenu({
    super.key,
    required this.studySetId,
    this.enabled = true,
    this.document,
    this.translationLanguage,
    this.left = false,
    this.menuLabel,
    this.onInvoked,
  });
  final String studySetId;
  final String? menuLabel;
  final VoidCallback? onInvoked;
  final bool enabled, left;
  final Document? document;
  final String? translationLanguage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n, c = context.mmColors;
    final container = ProviderScope.containerOf(context);
    final actionContext = Navigator.of(context).context;
    final readerWidth = ReaderCompareWidth.of(context);
    final buttonSize = context.mmTouch ? context.mmToolbarButton : MMSizes.readerToolbarButton;
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
    Future<void> select(String id) async {
      try {
        final hidden = await container
            .read(readerCompareProvider(studySetId).notifier)
            .select(id, left: left, readerWidth: readerWidth);
        if (hidden && actionContext.mounted) {
          MMHud.show(actionContext, l.compareMapHiddenHud(describeShortcut(AppShortcuts.view2)));
        }
      } catch (_) {
        if (actionContext.mounted) MMHud.show(actionContext, l.somethingWentWrong);
      }
    }

    String? selectedId = left
        ? current
        : switch (pair?.right) {
            PdfCompareTarget(:final documentId) => documentId,
            _ => null,
          };
    Future<void> invoke(String value) async {
      try {
        if (value == 'exit') {
          container.read(readerCompareProvider(studySetId).notifier).exit();
        } else if (value == 'import') {
          final files = await container.read(pdfPickerProvider)(l.documentFiles);
          if (files.isEmpty || !actionContext.mounted) return;
          final before = workspace.content.documents.map((d) => d.id).toSet();
          final notice = await workspace.importDocuments(files, open: false);
          final imported = workspace.content.documents.where((d) => !before.contains(d.id)).lastOrNull;
          if (!actionContext.mounted) return;
          if (notice.failed.isNotEmpty) showNotice(actionContext, notice, rootTitle: '');
          if (imported != null && !tooNarrow) await select(imported.id);
        } else {
          await select(value);
        }
      } finally {
        if (actionContext.mounted) onInvoked?.call();
      }
    }

    List<PopupMenuEntry<String>> items(BuildContext context) => [
      if (tooNarrow)
        MMDropdownItem<String>(
          enabled: false,
          height: 26,
          child: Text(l.compareTooNarrow, style: context.mmText.footnote),
        ),
      for (final doc in ordered)
        MMDropdownItem<String>(
          key: ValueKey('compare-document-${doc.id}'),
          value: doc.id,
          enabled: !tooNarrow,
          child: Semantics(
            selected: doc.id == selectedId,
            child: Row(
              children: [
                Icon(documentIcon(doc), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Tooltip(
                    message: doc.title,
                    child: Text(doc.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.mmText.callout),
                  ),
                ),
                if (!left && recommended(doc)) ...[const SizedBox(width: 6), MMPill(l.compareRecommended)],
                if (docLanguage(doc) case final lang?) ...[
                  const SizedBox(width: 6),
                  Text(
                    lang == 'zh' ? l.languageCodeZh : l.languageCodeEn,
                    style: context.mmText.footnote.copyWith(color: c.secondaryLabel),
                  ),
                ],
                const SizedBox(width: 10),
                SizedBox(
                  width: 16,
                  child: doc.id == selectedId ? Icon(MMIcons.check, size: 14, color: c.accent) : null,
                ),
              ],
            ),
          ),
        ),
      if (!left) ...[
        if (ordered.isNotEmpty) const PopupMenuDivider(),
        MMDropdownItem<String>(value: 'import', child: _menuRow(context, MMIcons.add, l.importDocument)),
        if (pair != null) ...[
          const PopupMenuDivider(),
          MMDropdownItem<String>(
            value: 'exit',
            child: Row(
              children: [
                const Icon(MMIcons.close, size: 14),
                const SizedBox(width: 8),
                Expanded(child: Text(l.compareExit, style: context.mmText.callout)),
                Text('Esc', style: context.mmText.footnote),
              ],
            ),
          ),
        ],
      ],
    ];
    if (menuLabel != null) {
      return MMDropdownSubmenu<T>.items(
        key: const ValueKey('reader-compare'),
        label: menuLabel!,
        icon: MMIcons.compare,
        width: MMSizes.dropdownWideWidth,
        enabled: enabled,
        selected: pair != null,
        itemBuilder: (context) => [
          for (final item in items(context))
            if (item is PopupMenuItem<String>)
              MMDropdownItem<T>(
                key: item.key,
                enabled: item.enabled && item.value != null,
                value: item.value == null ? null : (() => unawaited(invoke(item.value!))) as T,
                child: item.child,
              )
            else if (item is PopupMenuDivider)
              const PopupMenuDivider(),
        ],
      );
    }
    return MMDropdownButton<String>(
      key: document == null
          ? const ValueKey('reader-compare')
          : ValueKey(left ? 'compare-left-document' : 'compare-right-document'),
      enabled: enabled,
      tooltip: document == null ? l.compareReading : l.switchDocument,
      width: MMSizes.dropdownWideWidth,
      onSelected: invoke,
      itemBuilder: items,
      child: document == null
          ? Semantics(
              button: true,
              enabled: enabled,
              selected: pair != null,
              child: Container(
                width: buttonSize.width,
                height: buttonSize.height,
                decoration: BoxDecoration(
                  color: pair == null ? Colors.transparent : c.accentTint,
                  borderRadius: BorderRadius.circular(MMRadii.row),
                ),
                child: Icon(
                  MMIcons.compare,
                  semanticLabel: l.compareReading,
                  size: context.mmTouchPlatform ? MMSizes.tabletToolbarIcon : MMSpacing.l,
                  color: !enabled
                      ? c.label.withValues(alpha: .3)
                      : pair != null
                      ? c.accent
                      : c.label,
                ),
              ),
            )
          : SizedBox(
              height: 24,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(translationLanguage == null ? documentIcon(document!) : MMIcons.translate, size: 14),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      translationLanguage == null
                          ? document!.title
                          : l.translationLanguageCodeName(translationLanguage!),
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

  Widget _menuRow(BuildContext context, IconData icon, String label) => Row(
    children: [
      Icon(icon, size: 14),
      const SizedBox(width: 8),
      Expanded(
        child: Text(label, style: context.mmText.callout, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    ],
  );
}

/// Captured outside the toolbar so entry decisions use the full source width.
class ReaderCompareWidth extends InheritedTheme {
  const ReaderCompareWidth({super.key, required this.width, required super.child});
  final double width;
  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ReaderCompareWidth>()?.width ?? 0;
  @override
  bool updateShouldNotify(ReaderCompareWidth oldWidget) => width != oldWidget.width;
  @override
  Widget wrap(BuildContext context, Widget child) => ReaderCompareWidth(width: width, child: child);
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
    Future<void> action(Future<void> Function() run) async {
      try {
        await run();
      } catch (_) {
        if (context.mounted) MMHud.show(context, l.somethingWentWrong);
      }
    }

    Widget floatingControls() => Column(
      key: const ValueKey('compare-floating-controls'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (session.usesSourceAlignment && pair.right is PdfCompareTarget)
          MMIconButton(
            key: const ValueKey('compare-align'),
            icon: MMIcons.compare,
            tooltip: l.compareAlign,
            size: context.mmTouch ? MMSizes.touchTarget : MMSizes.readerCompareControl,
            iconSize: MMSizes.dropdownIcon,
            onPressed: () => action(() async {
              await session.align();
            }),
          ),
        MMIconButton(
          size: context.mmTouch ? MMSizes.touchTarget : MMSizes.readerCompareControl,
          iconSize: MMSizes.dropdownIcon,
          key: const ValueKey('compare-sync'),
          icon: MMIcons.link,
          tooltip: l.compareSync,
          selected: pair.sync,
          onPressed: () => action(session.toggleSync),
        ),
      ],
    );

    Widget column(String id, int side) {
      final doc = content.document(id);
      if (doc == null) return const SizedBox.shrink();
      return Expanded(
        child: Column(
          key: ValueKey('compare-column-$id'),
          children: [
            Container(
              height: context.mmTouch ? MMSizes.touchTarget : MMSizes.readerCompareHeader,
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
                  if (doc.capabilities().readingSettings)
                    MMToolbarButton(
                      key: ValueKey('compare-settings-$id'),
                      icon: MMIcons.readingSettings,
                      tooltip: l.readingSettings,
                      onPressed: () => showReadingSettings(context, ref, studySetId, document: doc),
                    ),
                  if (doc.contentManifest == null)
                    Consumer(
                      builder: (context, ref, _) {
                        final page =
                            ref.watch(readingPagesProvider(studySetId).select((pages) => pages[id])) ?? doc.lastPage;
                        return Text(
                          l.pageNumber(page),
                          style: context.mmText.callout.copyWith(color: c.secondaryLabel),
                        );
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

    return Stack(
      key: const ValueKey('reader-compare-view'),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            column(pair.leftDocumentId, 0),
            SizedBox(
              key: const ValueKey('compare-divider'),
              width: MMSizes.readerCompareDivider,
              child: ColoredBox(color: c.separator),
            ),
            if (pair.right is PdfCompareTarget)
              column((pair.right as PdfCompareTarget).documentId, 1)
            else
              Expanded(child: ReaderTranslationView(studySetId: studySetId)),
          ],
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(bottom: MMSizes.readerCompareBottomGap + MMChromeInsets.of(context).bottom),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(MMRadii.dropdown),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.glassOpaque,
                  borderRadius: BorderRadius.circular(MMRadii.dropdown),
                  border: Border.all(color: c.hairline, width: .5),
                ),
                child: Padding(padding: const EdgeInsets.all(MMSpacing.xxs), child: floatingControls()),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
