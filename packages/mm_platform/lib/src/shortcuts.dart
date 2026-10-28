import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Builds a shortcut with the platform's primary modifier: ⌘ on macOS,
/// Ctrl elsewhere. Write shortcuts once in macOS terms and let this adapt.
SingleActivator primaryShortcut(LogicalKeyboardKey key, {bool shift = false, bool alt = false, bool control = false}) {
  final mac = defaultTargetPlatform == TargetPlatform.macOS;
  return SingleActivator(key, meta: mac, control: !mac || control, shift: shift, alt: alt);
}

/// Human-readable form of a shortcut for tooltips: "⌘1", "⇧⌘L", "Ctrl+1".
String describeShortcut(SingleActivator activator) {
  final mac = defaultTargetPlatform == TargetPlatform.macOS;
  final key = switch (activator.trigger) {
    LogicalKeyboardKey.comma => ',',
    LogicalKeyboardKey.backspace => mac ? '⌫' : 'Backspace',
    LogicalKeyboardKey.enter => '↩',
    LogicalKeyboardKey.escape => 'Esc',
    LogicalKeyboardKey.period => '.',
    LogicalKeyboardKey.space => 'Space',
    final k => k.keyLabel.toUpperCase(),
  };
  if (mac) {
    return '${activator.control ? '⌃' : ''}${activator.alt ? '⌥' : ''}${activator.shift ? '⇧' : ''}${activator.meta ? '⌘' : ''}$key';
  }
  return [if (activator.control) 'Ctrl', if (activator.alt) 'Alt', if (activator.shift) 'Shift', key].join('+');
}

/// Keep browser navigation, find and save chords in the browser. Commands
/// remain available from the app's toolbar and menus.
bool browserOwnsShortcut(SingleActivator shortcut, {bool isWeb = kIsWeb}) =>
    isWeb &&
    (shortcut.control || shortcut.meta) &&
    !shortcut.alt &&
    const [
      LogicalKeyboardKey.keyF,
      LogicalKeyboardKey.keyS,
      LogicalKeyboardKey.keyW,
      LogicalKeyboardKey.keyN,
      LogicalKeyboardKey.keyO,
      LogicalKeyboardKey.keyL,
      LogicalKeyboardKey.keyR,
      LogicalKeyboardKey.keyD,
    ].contains(shortcut.trigger);
