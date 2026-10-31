import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../../../settings/app_settings.dart';
import '../../../shared/l10n.dart';

/// Secondary bottom panel for reader appearance on phone (prototype scene 7).
class PhoneReaderAppearanceSheet extends ConsumerWidget {
  const PhoneReaderAppearanceSheet({super.key, required this.studySetId, this.onBack, required this.onClose});

  final String studySetId;
  final VoidCallback? onBack;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mmColors;
    final l = context.l10n;
    final currentStyle = ref.watch(settingsProvider.select((s) => s.readerStyle));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with back and close buttons
          Row(
            children: [
              SizedBox.square(
                dimension: 36,
                child: Material(
                  color: c.card,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: const ValueKey('phone-appearance-back'),
                    onTap: onBack,
                    child: Icon(MMIcons.chevronLeft, size: 18, color: c.secondaryLabel),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  l.readerAppearance,
                  textAlign: TextAlign.center,
                  style: context.mmText.title3.copyWith(fontWeight: FontWeight.w600, fontSize: 16),
                ),
              ),
              SizedBox.square(
                dimension: 36,
                child: Material(
                  color: c.card,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: const ValueKey('phone-appearance-close'),
                    onTap: onClose,
                    child: Icon(MMIcons.close, size: 16, color: c.secondaryLabel),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 4 Paper Look Cards
          Row(
            children: [
              for (final (style, label) in [
                (MMReaderStyle.white, l.readerStyleWhite),
                (MMReaderStyle.paper, l.readerStylePaper),
                (MMReaderStyle.green, l.readerStyleGreen),
                (MMReaderStyle.dark, l.readerStyleDark),
              ]) ...[
                if (style != MMReaderStyle.white) const SizedBox(width: 10),
                Expanded(
                  child: _PhoneLookCard(
                    style: style,
                    label: label,
                    selected: currentStyle == style,
                    onTap: () => ref.read(settingsProvider.notifier).setReaderStyle(style),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _PhoneLookCard extends StatelessWidget {
  const _PhoneLookCard({required this.style, required this.label, required this.selected, required this.onTap});

  final MMReaderStyle style;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final accent = c.accent;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        key: ValueKey('phone-reader-style-${style.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 3 / 4,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: style.paperColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected ? accent : Colors.black.withValues(alpha: 0.14),
                    width: selected ? 2.5 : 0.5,
                  ),
                  boxShadow: selected
                      ? [BoxShadow(color: accent.withValues(alpha: 0.3), blurRadius: 6, spreadRadius: 1)]
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Aa',
                      style: TextStyle(
                        fontFamily: MMReaderTypography.serif,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: style.inkColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 36,
                      height: 2,
                      decoration: BoxDecoration(
                        color: style.inkColor.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      width: 28,
                      height: 2,
                      decoration: BoxDecoration(
                        color: style.inkColor.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: context.mmText.footnote.copyWith(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? c.label : c.secondaryLabel,
              ),
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? accent : Colors.transparent,
                border: Border.all(color: selected ? accent : c.secondaryLabel.withValues(alpha: 0.5), width: 1.5),
              ),
              child: selected ? const Icon(MMIcons.check, size: 12, color: Colors.white) : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
