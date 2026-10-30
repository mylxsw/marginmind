import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../app/app_commands.dart';
import '../../../app/document_commands.dart';
import '../../../shared/document_icon.dart';
import '../../../shared/l10n.dart';
import '../workspace_browser.dart';
import '../reader_compare.dart';
import 'reader_compare_controls.dart';
import 'notices.dart';

/// Lists every document, including ones not yet opened in this session.
class DocumentSwitcher extends ConsumerWidget {
  const DocumentSwitcher({
    super.key,
    required this.studySetId,
    required this.documents,
    required this.activeDocumentId,
    required this.onOpen,
    required this.onClose,
    this.primaryCompare = false,
  });

  final bool primaryCompare;
  final String studySetId;
  final List<Document> documents;
  final String? activeDocumentId;
  final ValueChanged<String> onOpen;
  final VoidCallback? onClose;

  ({Map<WebSourceCommand, AppCommand> sourceCommands, ValueChanged<String> select}) _commands(
    BuildContext context,
    WidgetRef ref,
  ) {
    final l = context.l10n;
    final active = documents.where((d) => d.id == activeDocumentId).firstOrNull;
    final sourceCommands = active == null
        ? <WebSourceCommand, AppCommand>{}
        : webSourceCommands(
            l,
            active,
            canRefetch: ref.read(canAddWebPageProvider),
            refetch: () => ref
                .read(workspaceBrowserProvider(studySetId).notifier)
                .open(Uri.parse(active.origin!.url), documentId: active.id),
          );
    void select(String id) {
      if (id == ':import') {
        pickAndImportDocuments(context, ref, studySetId);
      } else if (id == ':web') {
        dispatchAddWebPage(context, ref, studySetId);
      } else if (id == ':original') {
        sourceCommands[WebSourceCommand.openOriginal]?.onInvoke?.call();
      } else if (id == ':refetch') {
        sourceCommands[WebSourceCommand.refetch]?.onInvoke?.call();
      } else if (id.isEmpty) {
        onClose?.call();
      } else if (primaryCompare) {
        ref
            .read(readerCompareProvider(studySetId).notifier)
            .select(
              id,
              left: true,
              readerWidth: ReaderCompareWidth.of(context) > 0
                  ? ReaderCompareWidth.of(context)
                  : context.size?.width ?? 0,
            );
      } else {
        onOpen(id);
      }
    }

    return (sourceCommands: sourceCommands, select: select);
  }

  List<MMMenuEntry> menuEntries(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final actions = _commands(context, ref);
    return [
      for (final document in documents)
        MMMenuItem(document.title, () => actions.select(document.id), checked: document.id == activeDocumentId),
      const MMMenuDivider(),
      MMMenuItem(l.importDocument, () => actions.select(':import')),
      if (ref.read(canAddWebPageProvider)) MMMenuItem(l.addWebPage, () => actions.select(':web')),
      if (actions.sourceCommands.isNotEmpty) ...[
        const MMMenuDivider(),
        MMMenuItem(l.openOriginalPage, () => actions.select(':original')),
        if (actions.sourceCommands.containsKey(WebSourceCommand.refetch))
          MMMenuItem(l.refetchPage, () => actions.select(':refetch')),
      ],
      const MMMenuDivider(),
      MMMenuItem(l.closeCurrentDocument, onClose == null ? null : () => actions.select('')),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.mmColors;
    final text = context.mmText.callout;
    final commandSet = _commands(context, ref);
    final sourceCommands = commandSet.sourceCommands;
    Widget row(IconData icon, String label, {bool selected = false, bool enabled = true}) => Row(
      children: [
        Icon(icon, size: 14, color: c.secondaryLabel),
        const SizedBox(width: MMSpacing.s),
        Expanded(
          child: Tooltip(
            message: label,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: enabled ? text : text.copyWith(color: c.secondaryLabel),
            ),
          ),
        ),
        const SizedBox(width: MMSpacing.s),
        SizedBox(width: 14, child: selected ? Icon(MMIcons.check, size: 14, color: c.accent) : null),
      ],
    );
    return MMDropdownButton<String>(
      key: const ValueKey('reader-documents'),
      tooltip: l.switchDocument,
      width: MMSizes.dropdownWideWidth,
      icon: Icon(MMIcons.collections, color: c.label, semanticLabel: l.switchDocument),
      onSelected: commandSet.select,
      itemBuilder: (_) => [
        for (final document in documents)
          MMDropdownItem<String>(
            value: document.id,
            labelTextStyle: WidgetStatePropertyAll(text),
            child: Semantics(
              selected: document.id == activeDocumentId,
              child: row(documentIcon(document), document.title, selected: document.id == activeDocumentId),
            ),
          ),
        const PopupMenuDivider(height: MMSpacing.s),
        MMDropdownItem<String>(value: ':import', child: row(MMIcons.import, l.importDocument)),
        if (ref.watch(canAddWebPageProvider))
          MMDropdownItem<String>(value: ':web', child: row(MMIcons.web, l.addWebPage)),
        if (sourceCommands.isNotEmpty) ...[
          const PopupMenuDivider(height: MMSpacing.s),
          MMDropdownItem<String>(value: ':original', child: row(MMIcons.web, l.openOriginalPage)),
          if (sourceCommands.containsKey(WebSourceCommand.refetch))
            MMDropdownItem<String>(value: ':refetch', child: row(MMIcons.history, l.refetchPage)),
        ],
        const PopupMenuDivider(height: MMSpacing.s),
        MMDropdownItem<String>(
          value: '',
          enabled: onClose != null,
          labelTextStyle: WidgetStatePropertyAll(text),
          child: row(MMIcons.close, l.closeCurrentDocument, enabled: onClose != null),
        ),
      ],
    );
  }
}
