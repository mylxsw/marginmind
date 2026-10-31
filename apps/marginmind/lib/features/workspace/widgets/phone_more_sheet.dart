import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../../../app/navigation.dart';
import '../../../app/providers.dart';
import '../../../settings/app_settings.dart';
import '../../../shared/l10n.dart';
import '../../study_notes/note_setup_sheet.dart';
import '../../vocabulary/hint_controls.dart';
import '../../vocabulary/vocabulary_hints.dart';
import '../phone_reader_controls_controller.dart';
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
    this.phoneControls,
    this.initialPage = PhoneMoreSheetPage.more,
    this.onClose,
  });

  final String studySetId;
  final WorkspacePaneChromeController? paneChrome;
  final PhoneReaderControlsController? phoneControls;
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

    final marginState = ref.watch(readerMarginProvider(widget.studySetId));
    final isMarginOn = docId != null && marginState.openDocuments.contains(docId);

    final vocabHints = ref.watch(vocabularyHintProvider);
    final isVocabOn = docId != null && vocabHints.modeFor(docId) != VocabularyHintMode.off;

    final docIndex = docId != null ? docs.indexWhere((d) => d.id == docId) : -1;
    final docNumberText = '${docIndex >= 0 ? docIndex + 1 : 1} / ${math.max(1, docs.length)}';
    final dueCount = studySet?.dueCount ?? 0;

    return Padding(
      key: const ValueKey('phone-sheet-more'),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: Document icon + Title + Close button
          Row(
            children: [
              Container(
                width: 32,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(5),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 4, offset: const Offset(0, 1)),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Container(height: 2, color: const Color(0xFFD1D1D6)),
                    Container(height: 2, color: const Color(0xFFD1D1D6)),
                    Container(height: 2, width: 14, color: const Color(0xFFD1D1D6)),
                    Container(height: 2, color: const Color(0xFFD1D1D6)),
                    Container(height: 2, width: 10, color: const Color(0xFFD1D1D6)),
                  ],
                ),
              ),
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
              SizedBox.square(
                dimension: 36,
                child: Material(
                  color: c.card,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: const ValueKey('phone-more-close'),
                    onTap: _close,
                    child: Icon(MMIcons.close, size: 16, color: c.secondaryLabel),
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
                  label: l.marginNotes,
                  onTap: () {
                    if (docId != null) {
                      ref.read(readerMarginProvider(widget.studySetId).notifier).toggle(docId);
                    }
                  },
                  child: Icon(MMIcons.captionsBubble, size: 22, color: isMarginOn ? Colors.white : c.label),
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
                  child: Icon(MMIcons.vocabulary, size: 22, color: isVocabOn ? Colors.white : c.label),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Group 1: Outline & Bookmarks, Switch Document, Crop Margins
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
                  hasChevron: true,
                  onTap: () {
                    _close();
                    ref.read(workspaceProvider(widget.studySetId).notifier).showReaderPanel(ReaderPanelMode.outline);
                  },
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
                    if (docs.length > 1 && docId != null) {
                      final nextIndex = (docs.indexWhere((d) => d.id == docId) + 1) % docs.length;
                      ref.read(workspaceProvider(widget.studySetId).notifier).openDocument(docs[nextIndex].id);
                    } else {
                      widget.paneChrome?.reader?.execute('reader-switch-document');
                    }
                  },
                ),
                Container(margin: const EdgeInsets.only(left: 48), height: 0.5, color: c.separator),
                _PhoneSheetRow(
                  key: const ValueKey('phone-row-crop'),
                  icon: MMIcons.crop,
                  title: l.cropMargins,
                  hasChevron: false,
                  onTap: () {
                    _close();
                    widget.paneChrome?.reader?.execute('reader-crop');
                  },
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
                    showNoteSetupSheet(context, ref, widget.studySetId);
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
                    ref.read(navigationProvider.notifier).startReview(widget.studySetId);
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
                    ref.read(navigationProvider.notifier).showVocabulary(studySetId: widget.studySetId);
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

class _PhoneTile extends StatelessWidget {
  const _PhoneTile({super.key, required this.selected, required this.label, required this.child, required this.onTap});

  final bool selected;
  final String label;
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
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
                  color: selected ? Colors.white : c.label,
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
    this.hasChevron = false,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? value;
  final bool hasChevron;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;

    return Semantics(
      button: true,
      label: value != null ? '$title $value' : title,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 46),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: Center(child: Icon(icon, size: 18, color: c.accent)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: context.mmText.body.copyWith(fontSize: 15.5, fontWeight: FontWeight.w500, color: c.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (value != null) ...[
                Text(value!, style: context.mmText.body.copyWith(fontSize: 14, color: c.secondaryLabel)),
                if (hasChevron) const SizedBox(width: 4),
              ],
              if (hasChevron) Icon(MMIcons.chevronRight, size: 14, color: c.secondaryLabel),
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
  PhoneReaderControlsController? phoneControls,
  PhoneMoreSheetPage initialPage = PhoneMoreSheetPage.more,
  VoidCallback? onOpened,
  VoidCallback? onClosed,
}) async {
  onOpened?.call();
  try {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: const Color(0x14000000), // 8% alpha black - "遮罩要很淡，让页面效果可见"
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      transitionDuration: const Duration(milliseconds: 320),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
          child: child,
        );
      },
      pageBuilder: (context, _, _) => Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            MMSizes.phoneSheetPadding,
            0,
            MMSizes.phoneSheetPadding,
            math.max(MMSizes.phoneSheetPadding, MediaQuery.paddingOf(context).bottom),
          ),
          child: PhoneMoreSheet(
            studySetId: studySetId,
            paneChrome: paneChrome,
            phoneControls: phoneControls,
            initialPage: initialPage,
            onClose: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  } finally {
    onClosed?.call();
  }
}
