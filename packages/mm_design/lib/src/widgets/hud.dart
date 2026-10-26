import 'dart:async';

import 'package:flutter/material.dart';

import '../foundation/appearance.dart';
import '../icons/mm_icons.dart';
import '../theme/mm_theme.dart';
import '../tokens/motion.dart';
import 'glass.dart';

/// Hosts the HUD capsule shown at the bottom of the window. Put it above the
/// Navigator (e.g. in `MaterialApp.builder`) and call [MMHud.show]. [bottom] is
/// the capsule's distance from the window's bottom edge; raise it to clear
/// controls docked there.
class MMHudHost extends StatefulWidget {
  const MMHudHost({super.key, required this.child, this.bottom = defaultBottom});

  static const double defaultBottom = 22;

  final Widget child;
  final double bottom;

  @override
  State<MMHudHost> createState() => MMHudState();
}

/// Non-interactive, non-focus-stealing confirmation capsule. Destructive
/// actions rely on Undo (⌘Z) instead of a button in the HUD.
abstract final class MMHud {
  static void show(BuildContext context, String message, {IconData icon = MMIcons.success}) {
    context.findAncestorStateOfType<MMHudState>()?.show(message, icon: icon);
  }
}

class MMHudState extends State<MMHudHost> {
  String? _message;
  IconData _icon = MMIcons.success;
  bool _visible = false;
  Timer? _timer;

  void show(String message, {IconData icon = MMIcons.success}) {
    _timer?.cancel();
    setState(() {
      _message = message;
      _icon = icon;
      _visible = true;
    });
    _timer = Timer(MMMotion.hud, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 0,
          right: 0,
          bottom: widget.bottom,
          child: IgnorePointer(
            // Above the Navigator there is no Material: give text a style.
            child: Material(
              type: MaterialType.transparency,
              child: Center(
                child: AnimatedOpacity(
                  duration: MMAppearance.duration(context, MMMotion.standard),
                  opacity: _visible ? 1 : 0,
                  child: _message == null
                      ? const SizedBox.shrink()
                      : Semantics(
                          liveRegion: true,
                          child: MMGlass(
                            borderRadius: BorderRadius.circular(20),
                            padding: const EdgeInsets.fromLTRB(12, 9, 16, 9),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_icon, size: 15, color: c.label),
                                const SizedBox(width: 8),
                                Text(_message!, style: context.mmText.headline.copyWith(fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
