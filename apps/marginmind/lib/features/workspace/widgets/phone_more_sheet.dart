import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../../../app/providers.dart';
import '../../../settings/app_settings.dart';
import '../../../shared/l10n.dart';
import '../../study_notes/note_setup_sheet.dart';
import '../../vocabulary/hint_controls.dart';
import '../../vocabulary/vocabulary_hints.dart';
import '../reader_margin.dart';
import '../workspace_controller.dart';
import '../workspace_pane_chrome_controller.dart';
import 'phone_reader_appearance_sheet.dart';

enum PhoneMoreSheetPage { more, appearance }

/// Floating Liquid Glass bottom sheet for "More" reader actions on phone
/// (prototype scenes 6 & 7).
class PhoneMoreSheet extends ConsumerStatefulWidget {
  const PhoneMoreSheet({
    super.key,
    required this.studySetId,
    this.paneChrome,
    this.workspaceContext,
    this.onOrganizeNotes,
    this.initialPage = PhoneMoreSheetPage.more,
    this.onClose,
  });

  final String studySetId;
  final WorkspacePaneChromeController? paneChrome;
  final BuildContext? workspaceContext;
  final VoidCallback? onOrganizeNotes;
  final PhoneMoreSheetPage initialPage;
  final VoidCallback? onClose;

  @override
  ConsumerState<PhoneMoreSheet> createState() => _PhoneMoreSheetState();
}

class _PhoneMoreSheetState extends ConsumerState<PhoneMoreSheet> {
  late PhoneMoreSheetPage _page;
  bool _forward = true;

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage;
  }

  void _close() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  void _goToAppearance() {
    setState(() {
      _forward = true;
      _page = PhoneMoreSheetPage.appearance;
    });
  }

  void _goBackToMore() {
    setState(() {
      _forward = false;
      _page = PhoneMoreSheetPage.more;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;

    return Material(
      type: MaterialType.transparency,
      child: MMLiquidGlass(
        phoneStyle: MMPhoneGlass.thick,
        borderRadius: BorderRadius.circular(MMRadii.phoneSheet),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Grab handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 7, bottom: 4),
                width: 38,
                height: 5,
                decoration: BoxDecoration(
                  color: c.secondaryLabel.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            // Animated size and horizontal slide between More page and Appearance page
            AnimatedSize(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeOutCubic,
                transitionBuilder: (child, animation) {
                  final isAppearance = child.key == const ValueKey('phone-sheet-appearance');
                  final inOffset = _forward ? const Offset(1, 0) : const Offset(-1, 0);
                  final outOffset = _forward ? const Offset(-1, 0) : const Offset(1, 0);
                  final isIncoming = (isAppearance && _forward) || (!isAppearance && !_forward);
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: isIncoming ? inOffset : outOffset,
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  );
                },
                child: _page == PhoneMoreSheetPage.more
                    ? _buildMorePage(context, ref)
                    : KeyedSubtree(
                        key: const ValueKey('phone-sheet-appearance'),
                        child: PhoneReaderAppearanceSheet(
                          studySetId: widget.studySetId,
                          onBack: _goBackToMore,
                          onClose: _close,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMorePage(BuildContext context, WidgetRef ref) {
    final c = context.mmColors;
    final l = context.l10n;

    final studySet = ref.watch(studySetProvider(widget.studySetId));
    final workspaceController = ref.watch(workspaceProvider(widget.studySetId).notifier);
    final workspaceState = ref.watch(workspaceProvider(widget.studySetId));
    final docId = workspaceState.activeDocumentId;
    final docs = workspaceController.content.documents;
    final doc = docs.where((d) => d.id == docId).firstOrNull;
    final activeDocTitle = doc?.title.isNotEmpty == true ? doc!.title : (studySet?.title ?? '');

    final currentStyle = ref.watch(settingsProvider.select((s) => s.readerStyle));

    final marginCmd = widget.paneChrome?.reader?.commands['reader-margin'];
    final isMarginEnabled = marginCmd != null ? marginCmd.enabled : (doc?.capabilities().marginNotes == true);
    final marginState = ref.watch(readerMarginProvider(widget.studySetId));
    final isMarginOn = marginCmd != null
        ? marginCmd.selected
        : (docId != null && marginState.openDocuments.contains(docId));

    final vocabHints = ref.watch(vocabularyHintProvider);
    final isVocabOn = docId != null && vocabHints.modeFor(docId) != VocabularyHintMode.off;

    final docIndex = docId != null ? docs.indexWhere((d) => d.id == docId) : -1;
    final docNumberText = '${docIndex >= 0 ? docIndex + 1 : 1} / ${math.max(1, docs.length)}';
    final dueCount = studySet?.dueCount ?? 0;

    final navCmd = widget.paneChrome?.reader?.commands['reader-navigation'];
    final canNavigate =
        navCmd?.enabled ??
        (doc?.capabilities().outline == true ||
            doc?.capabilities().bookmarks == true ||
            doc?.capabilities().thumbnails == true ||
            doc?.capabilities().annotate == true);

    final settingsCmd = widget.paneChrome?.reader?.commands['reader-settings'];
    final supportsReadingSettings =
        (settingsCmd != null && settingsCmd.enabled) || doc?.capabilities().readingSettings == true;

    final cropCmd = widget.paneChrome?.reader?.commands['reader-crop'];
    final canCrop = cropCmd != null ? cropCmd.enabled : (doc?.capabilities().crop == true);

    final canUndo = workspaceState.canUndo;

    return Padding(
      key: const ValueKey('phone-sheet-more'),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: Document icon + Title + Undo button + Close button
          Row(
            children: [
              const _DocumentIcon(),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  activeDocTitle,
                  style: context.mmText.title3.copyWith(fontWeight: FontWeight.w600, fontSize: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: l.undo,
                child: Semantics(
                  button: true,
                  label: l.undo,
                  enabled: canUndo,
                  child: SizedBox.square(
                    dimension: 30,
                    child: Material(
                      color: c.fill,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: const ValueKey('phone-more-undo'),
                        onTap: canUndo
                            ? () {
                                _close();
                                ref.read(workspaceProvider(widget.studySetId).notifier).undo();
                              }
                            : null,
                        child: Center(
                          child: Icon(
                            MMIcons.undo,
                            size: 16,
                            color: canUndo ? c.label : c.secondaryLabel.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: l.phoneMoreClose,
                child: Semantics(
                  button: true,
                  label: l.phoneMoreClose,
                  child: SizedBox.square(
                    dimension: 30,
                    child: Material(
                      color: c.fill,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: const ValueKey('phone-more-close'),
                        onTap: _close,
                        child: Center(child: Icon(MMIcons.close, size: 16, color: c.secondaryLabel)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Three Tiles
          Row(
            children: [
              // Tile 1: Reading Appearance
              Expanded(
                child: _PhoneTile(
                  key: const ValueKey('phone-tile-appearance'),
                  selected: false,
                  label: l.readerAppearance,
                  onTap: _goToAppearance,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: currentStyle.paperColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.black.withValues(alpha: 0.18), width: 0.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Aa',
                      style: TextStyle(
                        fontFamily: MMReaderTypography.serif,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: currentStyle.inkColor,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Tile 2: Margin Notes
              Expanded(
                child: _PhoneTile(
                  key: const ValueKey('phone-tile-margin'),
                  selected: isMarginOn,
                  enabled: isMarginEnabled,
                  label: l.marginNotes,
                  onTap: isMarginEnabled
                      ? () {
                          if (marginCmd != null) {
                            marginCmd.invoke?.call();
                          } else if (docId != null) {
                            ref.read(readerMarginProvider(widget.studySetId).notifier).toggle(docId);
                          }
                        }
                      : null,
                  child: Icon(
                    MMIcons.captionsBubble,
                    size: 22,
                    color: isMarginOn
                        ? c.onAccent
                        : (isMarginEnabled ? c.label : c.secondaryLabel.withValues(alpha: 0.4)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Tile 3: Vocabulary Hints
              Expanded(
                child: _PhoneTile(
                  key: const ValueKey('phone-tile-vocab'),
                  selected: isVocabOn,
                  label: l.vocabularyHints,
                  onTap: () {
                    if (docId != null) {
                      toggleVocabularyHints(context, ref, docId);
                    }
                  },
                  child: Icon(MMIcons.vocabulary, size: 22, color: isVocabOn ? c.onAccent : c.label),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Group 1: Outline & Bookmarks, Switch Document, Reading Settings (if supported), Crop Margins
          Container(
            decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(14)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PhoneSheetRow(
                  key: const ValueKey('phone-row-outline'),
                  icon: MMIcons.readerNavigation,
                  title: l.phoneMoreOutlineAndBookmarks,
                  enabled: canNavigate,
                  hasChevron: canNavigate,
                  onTap: canNavigate
                      ? () {
                          _close();
                          if (navCmd != null && navCmd.enabled) {
                            navCmd.invoke?.call();
                          } else {
                            final caps = doc?.capabilities();
                            final mode = (caps?.outline == true)
                                ? ReaderPanelMode.outline
                                : (caps?.bookmarks == true)
                                ? ReaderPanelMode.bookmarks
                                : (caps?.thumbnails == true)
                                ? ReaderPanelMode.thumbnails
                                : ReaderPanelMode.annotations;
                            ref.read(workspaceProvider(widget.studySetId).notifier).showReaderPanel(mode);
                          }
                        }
                      : null,
                ),
                Container(margin: const EdgeInsets.only(left: 48), height: 0.5, color: c.separator),
                _PhoneSheetRow(
                  key: const ValueKey('phone-row-switch-document'),
                  icon: MMIcons.collections,
                  title: l.switchDocument,
                  value: docNumberText,
                  hasChevron: true,
                  onTap: () {
                    _close();
                    widget.paneChrome?.reader?.execute('reader-switch-document');
                  },
                ),
                if (supportsReadingSettings) ...[
                  Container(margin: const EdgeInsets.only(left: 48), height: 0.5, color: c.separator),
                  _PhoneSheetRow(
                    key: const ValueKey('phone-row-reading-settings'),
                    icon: MMIcons.readingSettings,
                    title: l.readingSettings,
                    hasChevron: false,
                    onTap: () {
                      _close();
                      widget.paneChrome?.reader?.execute('reader-settings');
                    },
                  ),
                ],
                Container(margin: const EdgeInsets.only(left: 48), height: 0.5, color: c.separator),
                _PhoneSheetRow(
                  key: const ValueKey('phone-row-crop'),
                  icon: MMIcons.crop,
                  title: l.cropMargins,
                  enabled: canCrop,
                  hasChevron: false,
                  onTap: canCrop
                      ? () {
                          _close();
                          widget.paneChrome?.reader?.execute('reader-crop');
                        }
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Group 2: Organize Notes, Review, Vocabulary
          Container(
            decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(14)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PhoneSheetRow(
                  key: const ValueKey('phone-row-organize-notes'),
                  icon: MMIcons.organizeNote,
                  title: l.organizeNotes,
                  hasChevron: true,
                  onTap: () {
                    _close();
                    if (widget.onOrganizeNotes != null) {
                      widget.onOrganizeNotes!();
                    } else {
                      showNoteSetupSheet(widget.workspaceContext ?? context, ref, widget.studySetId);
                    }
                  },
                ),
                Container(margin: const EdgeInsets.only(left: 48), height: 0.5, color: c.separator),
                _PhoneSheetRow(
                  key: const ValueKey('phone-row-review'),
                  icon: MMIcons.review,
                  title: l.review,
                  value: dueCount > 0 ? '$dueCount' : null,
                  hasChevron: true,
                  onTap: () {
                    _close();
                    ref.read(workspaceProvider(widget.studySetId).notifier).activateTab(WorkspaceTab.review);
                  },
                ),
                Container(margin: const EdgeInsets.only(left: 48), height: 0.5, color: c.separator),
                _PhoneSheetRow(
                  key: const ValueKey('phone-row-vocabulary'),
                  icon: MMIcons.vocabulary,
                  title: l.vocabularyTitle,
                  hasChevron: true,
                  onTap: () {
                    _close();
                    ref.read(workspaceProvider(widget.studySetId).notifier).activateTab(WorkspaceTab.vocabulary);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentIcon extends StatelessWidget {
  const _DocumentIcon();

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;

    return Container(
      width: 36,
      height: 46,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.separator, width: 0.5),
        boxShadow: c.cardShadow,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(height: 2, color: c.separator),
          Container(height: 2, color: c.separator),
          Container(height: 2, width: 14, color: c.separator),
          Container(height: 2, color: c.separator),
          Container(height: 2, width: 10, color: c.separator),
        ],
      ),
    );
  }
}

class _PhoneTile extends StatelessWidget {
  const _PhoneTile({
    super.key,
    required this.selected,
    this.enabled = true,
    required this.label,
    required this.child,
    required this.onTap,
  });

  final bool selected;
  final bool enabled;
  final String label;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;

    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          height: 84,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: selected ? c.accent : c.card, borderRadius: BorderRadius.circular(20)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              child,
              Text(
                label,
                style: context.mmText.footnote.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? c.onAccent : (enabled ? c.label : c.secondaryLabel.withValues(alpha: 0.4)),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhoneSheetRow extends StatelessWidget {
  const _PhoneSheetRow({
    super.key,
    required this.icon,
    required this.title,
    this.value,
    this.enabled = true,
    this.hasChevron = false,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? value;
  final bool enabled;
  final bool hasChevron;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final disabledColor = c.secondaryLabel.withValues(alpha: 0.4);

    return Semantics(
      button: true,
      enabled: enabled,
      label: value != null ? '$title $value' : title,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 46),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: Center(child: Icon(icon, size: 18, color: enabled ? c.accent : disabledColor)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: context.mmText.body.copyWith(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w500,
                    color: enabled ? c.label : disabledColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (value != null) ...[
                Text(
                  value!,
                  style: context.mmText.body.copyWith(fontSize: 14, color: enabled ? c.secondaryLabel : disabledColor),
                ),
                if (hasChevron) const SizedBox(width: 4),
              ],
              if (hasChevron) Icon(MMIcons.chevronRight, size: 14, color: enabled ? c.secondaryLabel : disabledColor),
            ],
          ),
        ),
      ),
    );
  }
}

/// Presents the [PhoneMoreSheet] in a light-scrim bottom dialog route.
Future<void> showPhoneMoreSheet(
  BuildContext context, {
  required String studySetId,
  WorkspacePaneChromeController? paneChrome,
  BuildContext? workspaceContext,
  VoidCallback? onOrganizeNotes,
  PhoneMoreSheetPage initialPage = PhoneMoreSheetPage.more,
  VoidCallback? onOpened,
  VoidCallback? onClosed,
}) async {
  onOpened?.call();
  try {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: MMThemeContext(context).mmColors.lightScrim,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      transitionDuration: const Duration(milliseconds: 320),
      transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
          child: child,
        );
      },
      pageBuilder: (dialogContext, _, _) => Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            MMSizes.phoneSheetPadding,
            0,
            MMSizes.phoneSheetPadding,
            math.max(MMSizes.phoneSheetPadding, MediaQuery.paddingOf(dialogContext).bottom),
          ),
          child: PhoneMoreSheet(
            studySetId: studySetId,
            paneChrome: paneChrome,
            workspaceContext: workspaceContext ?? context,
            onOrganizeNotes: onOrganizeNotes,
            initialPage: initialPage,
            onClose: () => Navigator.of(dialogContext).pop(),
          ),
        ),
      ),
    );
  } finally {
    onClosed?.call();
  }
}
