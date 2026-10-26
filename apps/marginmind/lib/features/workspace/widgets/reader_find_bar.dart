import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../../app/app_commands.dart';
import '../../../shared/l10n.dart';

/// Find-in-document bar floating over the PDF: search field, hit count and
/// previous / next. Every hit is highlighted by the viewer; Enter and ⇧Enter
/// step through them, Esc closes the bar.
class ReaderFindBar extends StatefulWidget {
  const ReaderFindBar({super.key, required this.pdf, required this.focusTick, required this.onClose});

  final MMPdfViewController pdf;

  /// Changes whenever the user asks for the bar again: the field takes
  /// focus and selects its text.
  final int focusTick;
  final VoidCallback onClose;

  @override
  State<ReaderFindBar> createState() => _ReaderFindBarState();
}

class _ReaderFindBarState extends State<ReaderFindBar> {
  final _text = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusField();
  }

  @override
  void didUpdateWidget(ReaderFindBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusTick != widget.focusTick) _focusField();
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _focusField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      _text.selection = TextSelection(baseOffset: 0, extentOffset: _text.text.length);
    });
  }

  void _step({required bool backwards}) {
    if (backwards) {
      widget.pdf.previousMatch();
    } else {
      widget.pdf.nextMatch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    return MMGlass(
      borderRadius: BorderRadius.circular(MMRadii.card),
      padding: const EdgeInsets.all(MMSpacing.xs),
      child: SizedBox(
        width: 380,
        child: ListenableBuilder(
          listenable: widget.pdf,
          builder: (context, _) {
            final pdf = widget.pdf;
            final hasQuery = pdf.searchQuery.isNotEmpty;
            final count = pdf.matchCount;
            final status = !hasQuery || (count == 0 && pdf.isSearching)
                ? null
                : count == 0
                ? l.noResults
                : l.matchOf((pdf.matchIndex ?? 0) + 1, count);
            return Row(
              children: [
                Expanded(
                  child: MMSearchField(
                    placeholder: l.findInDocument,
                    controller: _text,
                    focusNode: _focus,
                    onChanged: pdf.search,
                    onSubmitted: (_) {
                      _step(backwards: HardwareKeyboard.instance.isShiftPressed);
                      _focusField();
                    },
                    onEscape: widget.onClose,
                  ),
                ),
                if (status != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: MMSpacing.s),
                    child: Text(
                      status,
                      style: t.footnote.copyWith(
                        color: c.secondaryLabel,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                MMIconButton(
                  icon: MMIcons.chevronUp,
                  tooltip: AppShortcuts.tip(l.findPrevious, AppShortcuts.findPrevious),
                  size: 26,
                  iconSize: 12,
                  onPressed: count > 0 ? () => _step(backwards: true) : null,
                ),
                MMIconButton(
                  icon: MMIcons.chevronDown,
                  tooltip: AppShortcuts.tip(l.findNext, AppShortcuts.findNext),
                  size: 26,
                  iconSize: 12,
                  onPressed: count > 0 ? () => _step(backwards: false) : null,
                ),
                MMIconButton(icon: MMIcons.close, tooltip: l.done, size: 26, iconSize: 11, onPressed: widget.onClose),
              ],
            );
          },
        ),
      ),
    );
  }
}
