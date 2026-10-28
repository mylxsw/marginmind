import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../foundation/adaptive.dart';
import '../foundation/appearance.dart';
import '../theme/mm_theme.dart';
import '../tokens/metrics.dart';
import '../tokens/motion.dart';
import 'bottom_sheet.dart';

/// Presents a macOS-style sheet that drops from below the toolbar.
/// Esc cancels; clicking outside does nothing (sheets are modal to the
/// window). A compact window shows it as a bottom sheet.
Future<T?> showMMSheet<T>({required BuildContext context, required WidgetBuilder builder, double width = 460}) {
  if (MMSizeClass.of(context) == MMSizeClass.compact) return showMMBottomSheet<T>(context: context, builder: builder);
  final c = context.mmColors;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: false,
    barrierColor: c.scrim,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration: MMAppearance.duration(context, MMMotion.standard),
    pageBuilder: (context, _, _) => SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: MMSizes.toolbarHeight + 8, left: 16, right: 16),
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
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: false,
    barrierColor: mmDialogScrim,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration: MMAppearance.duration(context, MMMotion.standard),
    pageBuilder: (context, _, _) => SafeArea(
      child: Center(
        child: CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop()},
          child: FocusScope(autofocus: true, child: Builder(builder: builder)),
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
  const MMSheet({super.key, required this.title, required this.child, this.actions = const []});

  final String title;
  final Widget child;

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
        Semantics(
          header: true,
          child: Text(title, style: context.mmText.title3.copyWith(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 18),
        // A bottom sheet can be shorter than its content: the body scrolls.
        if (bottomSheet) Flexible(child: SingleChildScrollView(child: child)) else child,
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(width: 10), actions[i]],
            ],
          ),
        ],
      ],
    );
    if (bottomSheet) {
      return Material(
        type: MaterialType.transparency,
        child: Padding(padding: const EdgeInsets.fromLTRB(22, 4, 22, 18), child: column),
      );
    }
    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(MMRadii.sheet),
          border: Border.all(color: c.hairline, width: 0.5),
          boxShadow: c.sheetShadow,
        ),
        child: column,
      ),
    );
  }
}
