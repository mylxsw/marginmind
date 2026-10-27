import 'package:flutter/material.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_research/mm_research.dart';

import '../../../shared/l10n.dart';
import '../research_intents.dart';
import '../research_origin.dart';

String intentLabel(AppLocalizations l, ResearchIntent intent) => switch (intent) {
  ResearchIntent.explain => l.researchIntentExplain,
  ResearchIntent.interpret => l.researchIntentInterpret,
  ResearchIntent.verify => l.researchIntentVerify,
  ResearchIntent.video => l.researchIntentVideo,
  ResearchIntent.paper => l.researchIntentPaper,
  ResearchIntent.deep => l.researchIntentDeep,
  ResearchIntent.translate => l.researchIntentTranslate,
};

IconData intentIcon(ResearchIntent intent) => switch (intent) {
  ResearchIntent.explain => MMIcons.explain,
  ResearchIntent.interpret => MMIcons.interpret,
  ResearchIntent.verify => MMIcons.verify,
  ResearchIntent.video => MMIcons.video,
  ResearchIntent.paper => MMIcons.paper,
  ResearchIntent.deep => MMIcons.research,
  ResearchIntent.translate => MMIcons.translate,
};

String kindLabel(AppLocalizations l, ResearchSourceKind kind) => switch (kind) {
  ResearchSourceKind.web => l.researchKindWeb,
  ResearchSourceKind.paper => l.researchKindPaper,
  ResearchSourceKind.video => l.researchKindVideo,
  ResearchSourceKind.image => l.researchKindImage,
};

IconData kindIcon(ResearchSourceKind kind) => switch (kind) {
  ResearchSourceKind.web => MMIcons.web,
  ResearchSourceKind.paper => MMIcons.paper,
  ResearchSourceKind.video => MMIcons.video,
  ResearchSourceKind.image => MMIcons.image,
};

/// A source's kind as stored (`web`, `paper`, `video`, `image`).
ResearchSourceKind sourceKind(String kind) =>
    ResearchSourceKind.values.where((k) => k.name == kind).firstOrNull ?? ResearchSourceKind.web;

String methodLabel(AppLocalizations l, ResearchMethod method) => switch (method) {
  ResearchMethod.search => l.researchMethodSearch,
  ResearchMethod.offline => l.researchMethodOffline,
  ResearchMethod.web => l.researchMethodWeb,
};

IconData methodIcon(ResearchMethod method) => switch (method) {
  ResearchMethod.search => MMIcons.search,
  ResearchMethod.offline => MMIcons.ai,
  ResearchMethod.web => MMIcons.web,
};

String contextLabel(AppLocalizations l, ResearchContextKind kind) => switch (kind) {
  ResearchContextKind.selection => l.researchContextSelection,
  ResearchContextKind.before => l.researchContextBefore,
  ResearchContextKind.after => l.researchContextAfter,
  ResearchContextKind.chapter => l.researchContextChapter,
  ResearchContextKind.node => l.researchContextNode,
  ResearchContextKind.path => l.researchContextPath,
  ResearchContextKind.children => l.researchContextChildren,
};

/// A source's reading state as shown, with its fixed color (null: neutral).
(String, Color?) readState(BuildContext context, String state) {
  final l = context.l10n;
  final c = context.mmColors;
  return switch (ResearchReadState.values.where((s) => s.name == state).firstOrNull) {
    ResearchReadState.snippet => (l.researchReadSnippet, null),
    ResearchReadState.abstractOnly => (l.researchReadAbstract, c.caution),
    ResearchReadState.fullText => (l.researchReadFullText, c.positive),
    ResearchReadState.transcript => (l.researchReadTranscript, c.positive),
    ResearchReadState.failed => (l.researchReadFailed, c.critical),
    ResearchReadState.noTranscript => (l.researchReadNoTranscript, c.caution),
    ResearchReadState.unread || null => (l.researchReadUnread, null),
  };
}

/// Why a request failed, from the engine's stable code.
String researchError(AppLocalizations l, String? code) => switch (code) {
  'timeout' => l.researchErrorTimeout,
  'authentication' => l.researchErrorAuthentication,
  'rateLimited' => l.researchErrorRateLimited,
  'budget' => l.researchErrorBudget,
  'refusal' => l.researchErrorRefusal,
  'unsupported' || 'client_tool' => l.researchErrorUnsupported,
  'invalidRequest' || 'missing_snapshot' || 'invalid_paragraph' => l.researchErrorInvalid,
  'protocol' || 'truncated' || 'incomplete_stream' => l.researchErrorProtocol,
  'unavailable' || 'secret_store' => l.researchErrorUnavailable,
  _ => l.somethingWentWrong,
};

/// Why a page could not be read, from the extractor's code.
String readError(AppLocalizations l, String? code) => switch (code) {
  'login_required' => l.researchReadLogin,
  'timeout' => l.researchReadTimeout,
  'unparseable' => l.researchReadUnparseable,
  'unsafeUrl' => l.researchReadUnsafe,
  'unsupported_content' => l.researchReadUnsupported,
  'unsupported_encoding' => l.researchReadEncoding,
  _ => l.researchReadUnavailable,
};

/// A small caption above a field.
class ResearchFieldLabel extends StatelessWidget {
  const ResearchFieldLabel(this.label, {super.key, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: MMSpacing.xs + 2),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: context.mmText.subheadline.copyWith(color: context.mmColors.secondaryLabel)),
        ),
        ?trailing,
      ],
    ),
  );
}

/// One choice of a group: a round mark, a label and an optional detail line.
class ResearchRadio extends StatelessWidget {
  const ResearchRadio({
    super.key,
    required this.selected,
    required this.label,
    required this.onTap,
    this.detail,
    this.badge,
  });

  final bool selected;
  final String label;
  final String? detail;
  final String? badge;

  /// Null disables the choice.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: MMInteractive(
        onTap: onTap,
        selected: selected,
        semanticLabel: label,
        builder: (context, s) => Opacity(
          opacity: s.enabled ? 1 : 0.45,
          child: Container(
            margin: const EdgeInsets.only(bottom: MMSpacing.xs),
            padding: const EdgeInsets.symmetric(horizontal: MMSpacing.m, vertical: MMSpacing.s),
            decoration: BoxDecoration(
              color: selected ? c.researchTint : (s.hovered ? c.hover : null),
              borderRadius: BorderRadius.circular(MMRadii.field),
              border: Border.all(color: selected ? c.research : c.separator),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 1),
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: selected ? c.research : c.line, width: selected ? 4.5 : 1),
                    color: c.card,
                  ),
                ),
                const SizedBox(width: MMSpacing.s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(child: Text(label, style: t.headline)),
                          if (badge != null) ...[
                            const SizedBox(width: MMSpacing.xs),
                            MMPill(badge!, color: c.research),
                          ],
                        ],
                      ),
                      if (detail != null) ...[
                        const SizedBox(height: MMSpacing.xxs),
                        Text(
                          detail!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.footnote.copyWith(color: c.secondaryLabel),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A capsule chip: a keyword (with a remove button) or a toggle.
class ResearchChip extends StatelessWidget {
  const ResearchChip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
    this.onRemove,
    this.removeTooltip = '',
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final String removeTooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final fg = selected ? c.onAccent : c.label;
    final chip = Container(
      height: 24,
      padding: EdgeInsets.only(left: MMSpacing.s + 2, right: onRemove == null ? MMSpacing.s + 2 : MMSpacing.xxs),
      decoration: BoxDecoration(color: selected ? c.label : c.quaternaryFill, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 11, color: fg), const SizedBox(width: MMSpacing.xs)],
          Text(
            label,
            style: t.callout.copyWith(color: fg, fontWeight: FontWeight.w400),
          ),
          if (onRemove != null)
            MMIconButton(icon: MMIcons.close, tooltip: removeTooltip, size: 20, iconSize: 9, onPressed: onRemove),
        ],
      ),
    );
    if (onTap == null) return chip;
    return MMInteractive(onTap: onTap, selected: selected, semanticLabel: label, builder: (context, s) => chip);
  }
}

/// Search only / Ask AI / Web research. Methods needing an unavailable
/// service are shown but disabled.
class ResearchMethodPicker extends StatelessWidget {
  const ResearchMethodPicker({
    super.key,
    required this.value,
    required this.ai,
    required this.web,
    required this.onChanged,
  });

  final ResearchMethod value;
  final bool ai;
  final bool web;
  final ValueChanged<ResearchMethod> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.mmColors;
    final t = context.mmText;
    return Container(
      height: MMSizes.segmented,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: c.quaternaryFill, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          for (final m in ResearchMethod.values)
            Expanded(
              child: MMInteractive(
                key: ValueKey('method-${m.name}'),
                selected: m == value,
                enabled: switch (m) {
                  ResearchMethod.search => true,
                  ResearchMethod.offline => ai,
                  ResearchMethod.web => web,
                },
                semanticLabel: methodLabel(l, m),
                onTap: () => onChanged(m),
                builder: (context, s) => Opacity(
                  opacity: s.enabled ? 1 : 0.4,
                  child: AnimatedContainer(
                    duration: MMMotion.quick,
                    height: MMSizes.segmented - 4,
                    padding: const EdgeInsets.symmetric(horizontal: MMSpacing.s),
                    decoration: BoxDecoration(
                      color: m == value ? c.card : (s.hovered ? c.hover : Colors.transparent),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: m == value
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 2,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(methodIcon(m), size: 11, color: m == value ? c.research : c.icon),
                        const SizedBox(width: MMSpacing.xs),
                        Flexible(
                          child: Text(
                            methodLabel(l, m),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.callout.copyWith(fontWeight: m == value ? FontWeight.w600 : FontWeight.w400),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A one-line notice with an optional link-like action.
class ResearchNotice extends StatelessWidget {
  const ResearchNotice({
    super.key,
    required this.text,
    this.icon = MMIcons.info,
    this.action,
    this.onAction,
    this.color,
  });

  final String text;
  final IconData icon;
  final String? action;
  final VoidCallback? onAction;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final t = context.mmText;
    final tint = color ?? c.caution;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: MMSpacing.s + 2, vertical: MMSpacing.s - 2),
      decoration: BoxDecoration(color: tint.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(MMRadii.field)),
      child: Row(
        children: [
          Icon(icon, size: 12, color: tint),
          const SizedBox(width: MMSpacing.s),
          Expanded(
            child: Text(text, style: t.footnote.copyWith(color: c.label)),
          ),
          if (action != null)
            MMInteractive(
              onTap: onAction,
              semanticLabel: action,
              builder: (context, s) => Text(
                action!,
                style: t.footnote.copyWith(
                  color: c.research,
                  fontWeight: FontWeight.w600,
                  decoration: s.hovered ? TextDecoration.underline : null,
                  decorationColor: c.research,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A citation number; clicking opens the source at the cited passage.
class CiteBadge extends StatelessWidget {
  const CiteBadge({super.key, required this.number, required this.title, this.onTap});

  final int number;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return MMInteractive(
      onTap: onTap,
      tooltip: title,
      semanticLabel: '[$number] $title',
      builder: (context, s) => Container(
        margin: const EdgeInsets.only(left: 3),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: s.hovered ? c.research : c.researchTint,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '$number',
          style: context.mmText.footnote.copyWith(color: s.hovered ? c.onAccent : c.research, height: 15 / 11),
        ),
      ),
    );
  }
}
