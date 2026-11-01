import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../foundation/adaptive.dart';
import '../foundation/appearance.dart';
import '../theme/mm_theme.dart';
import '../tokens/metrics.dart';
import '../tokens/motion.dart';
import 'bottom_sheet.dart';
import 'dialog_scope.dart';

/// Presents a compact modal form centered in the window.
/// Esc cancels; clicking outside does nothing (sheets are modal to the
/// window). A compact window shows it as a bottom sheet.
Future<T?> showMMSheet<T>({required BuildContext context, required WidgetBuilder builder, double width = 420}) {
  if (MMSizeClass.of(context) == MMSizeClass.compact) return showMMBottomSheet<T>(context: context, builder: builder);
  final c = context.mmColors;
  final capturedThemes = InheritedTheme.capture(from: context, to: Navigator.of(context, rootNavigator: true).context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: false,
    barrierColor: c.scrim,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration: MMAppearance.duration(context, MMMotion.standard),
    pageBuilder: (context, _, _) => capturedThemes.wrap(
      SafeArea(
        child: Align(
          alignment: Alignment.center,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 24 + MediaQuery.viewInsetsOf(context).bottom),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width),
              child: CallbackShortcuts(
                bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop()},
                child: FocusScope(autofocus: true, child: Builder(builder: builder)),
              ),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: MMMotion.layoutCurve);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, -0.04), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Presents a window-level dialog centered over a 22% black scrim, such as
/// Settings. Esc closes; clicking the scrim does nothing. Fades in with a
/// slight scale (fade only when motion is reduced). A compact window shows
/// it as a bottom sheet.
Future<T?> showMMDialog<T>({required BuildContext context, required WidgetBuilder builder}) {
  if (MMSizeClass.of(context) == MMSizeClass.compact) return showMMBottomSheet<T>(context: context, builder: builder);
  final reduceMotion = MMAppearance.reduceMotionOf(context);
  final capturedThemes = InheritedTheme.capture(from: context, to: Navigator.of(context, rootNavigator: true).context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: false,
    barrierColor: mmDialogScrim,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration: MMAppearance.duration(context, MMMotion.standard),
    pageBuilder: (context, _, _) => capturedThemes.wrap(
      SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: context.mmTouchPlatform ? MediaQuery.viewInsetsOf(context).bottom : 0),
          child: Center(
            child: CallbackShortcuts(
              bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop()},
              child: FocusScope(autofocus: true, child: Builder(builder: builder)),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: MMMotion.layoutCurve);
      return FadeTransition(
        opacity: curved,
        child: reduceMotion ? child : ScaleTransition(scale: Tween(begin: .98, end: 1.0).animate(curved), child: child),
      );
    },
  );
}

/// The scrim behind [showMMDialog].
const mmDialogScrim = Color(0x38000000);

/// Content frame for [showMMSheet]: title, body, right-aligned actions.
class MMSheet extends StatelessWidget {
  const MMSheet({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.titleTrailing,
    this.titleLeading,
    this.titleStyle,
    this.icon,
    this.subtitle,
    this.footer,
  });

  final String title;
  final Widget child;
  final Widget? titleTrailing;
  final Widget? titleLeading;
  final TextStyle? titleStyle;

  /// Shown in a 30pt accent tile before the title.
  final IconData? icon;

  /// One line under the title, such as the document a sheet acts on.
  final String? subtitle;

  /// Left of the actions, for a short fact about the result.
  final Widget? footer;

  /// Usually a secondary "Cancel" followed by the primary default action.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final bottomSheet = MMBottomSheet.contains(context);
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (titleLeading != null) ...[titleLeading!, const SizedBox(width: 12)],
            if (icon != null) ...[
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: c.accentTint, borderRadius: BorderRadius.circular(MMRadii.row)),
                child: Icon(icon, size: 16, color: c.accent),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: titleStyle ?? context.mmText.title3.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.mmText.footnote.copyWith(color: c.secondaryLabel),
                    ),
                ],
              ),
            ),
            ?titleTrailing,
          ],
        ),
        const SizedBox(height: 20),
        // Keep actions visible when the window or keyboard limits the height.
        Flexible(child: SingleChildScrollView(child: child)),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.only(top: 16),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.hairline, width: .5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (footer != null) ...[Expanded(child: footer!), const SizedBox(width: 12)],
                Expanded(
                  flex: 2,
                  child: Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: actions),
                ),
              ],
            ),
          ),
        ],
      ],
    );
    if (bottomSheet) {
      return Material(
        type: MaterialType.transparency,
        child: MMDialogScope(
          child: Padding(padding: const EdgeInsets.fromLTRB(22, 4, 22, 18), child: column),
        ),
      );
    }
    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.hairline, width: 0.5),
          boxShadow: c.sheetShadow,
        ),
        child: MMDialogScope(child: column),
      ),
    );
  }
}
