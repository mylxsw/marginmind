import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../tokens/metrics.dart';

/// Width class of the space a layout has, from its logical size rather than
/// the device: an iPad in Split View is as compact as a phone.
enum MMSizeClass {
  /// Narrower than 600: one pane at a time.
  compact,

  /// 600 to 1179 wide, or taller than wide: source above map.
  medium,

  /// At least 1180 wide and landscape: the desktop layout.
  regular;

  static const double compactMaxWidth = 600;
  static const double regularMinWidth = 1180;

  static MMSizeClass fromSize(Size size) {
    if (size.width < compactMaxWidth) return compact;
    if (size.width >= regularMinWidth && size.width >= size.height) return regular;
    return medium;
  }

  /// The class for [size] in [context]'s window: pointer-only desktops keep
  /// [regular] at every size their windows take, so their narrow-window
  /// rules stay as they are.
  static MMSizeClass resolve(BuildContext context, Size size) =>
      MMInput.of(context).touchPlatform ? fromSize(size) : regular;

  /// The class of [context]'s window inside its safe area.
  static MMSizeClass of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final safe = MediaQuery.paddingOf(context);
    return resolve(context, Size(size.width - safe.horizontal, size.height - safe.vertical));
  }
}

/// Which device and input drive the window. [touchPlatform] is fixed per
/// device (phones and tablets) and decides layout, [phone] marks a handheld
/// whose screen is compact in both orientations. [touchInput] follows the
/// last pointer on any device, so a touchscreen laptop gets touch menus and
/// always-visible controls; [touch] is the same on a touch platform only and
/// sizes controls, so a trackpad on an iPad gets pointer-sized ones.
@immutable
class MMInputState {
  const MMInputState({this.touchPlatform = false, this.phone = false, this.touch = false, bool? touchInput})
    : touchInput = touchInput ?? touch;

  static const pointer = MMInputState();

  final bool touchPlatform;
  final bool phone;

  /// Tablet chrome stays finger-sized even while using an attached trackpad.
  bool get tablet => touchPlatform && !phone;
  final bool touch;
  final bool touchInput;

  @override
  bool operator ==(Object other) =>
      other is MMInputState &&
      other.touchPlatform == touchPlatform &&
      other.phone == phone &&
      other.touch == touch &&
      other.touchInput == touchInput;

  @override
  int get hashCode => Object.hash(touchPlatform, phone, touch, touchInput);
}

/// Provides [MMInputState] below it: the one source of touch decisions.
class MMInput extends StatefulWidget {
  const MMInput({super.key, required this.touchPlatform, this.phone = false, required this.child});

  final bool touchPlatform;

  /// Only meaningful with [touchPlatform].
  final bool phone;
  final Widget child;

  /// Without an [MMInput] above, the window is a pointer-only desktop.
  /// Reads the live input: a long press can open a menu in the same frame
  /// as the pointer-down that made the input touch.
  static MMInputState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_MMInputScope>()?.owner.current ?? MMInputState.pointer;

  /// Whether controls in [context] need finger-sized hit areas.
  static bool touchOf(BuildContext context) => of(context).touch;

  /// Whether the last pointer was a finger or pen, on any device: menus
  /// open as touch menus and hover-only controls stay visible.
  static bool touchInputOf(BuildContext context) => of(context).touchInput;

  @override
  State<MMInput> createState() => _MMInputState();
}

class _MMInputState extends State<MMInput> {
  late bool _touch = widget.touchPlatform;

  @override
  void didUpdateWidget(MMInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.touchPlatform != widget.touchPlatform) _touch = widget.touchPlatform;
  }

  void _follow(PointerEvent event) {
    final touch = switch (event.kind) {
      PointerDeviceKind.mouse || PointerDeviceKind.trackpad => false,
      PointerDeviceKind.touch || PointerDeviceKind.stylus || PointerDeviceKind.invertedStylus => true,
      PointerDeviceKind.unknown => _touch,
    };
    if (touch != _touch) setState(() => _touch = touch);
  }

  MMInputState get current {
    final platform = widget.touchPlatform;
    return MMInputState(
      touchPlatform: platform,
      phone: platform && widget.phone,
      touch: platform && _touch,
      touchInput: _touch,
    );
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _follow,
    onPointerHover: _follow,
    onPointerPanZoomStart: _follow,
    child: _MMInputScope(
      owner: this,
      state: current,
      child: widget.touchPlatform && !widget.phone
          ? Theme(
              data: Theme.of(context)
                  .copyWith(visualDensity: VisualDensity.standard, materialTapTargetSize: MaterialTapTargetSize.padded),
              child: widget.child,
            )
          : widget.child,
    ),
  );
}

class _MMInputScope extends InheritedWidget {
  const _MMInputScope({required this.owner, required this.state, required super.child});

  final _MMInputState owner;
  final MMInputState state;

  @override
  bool updateShouldNotify(_MMInputScope oldWidget) => oldWidget.state != state;
}

/// Control sizes that grow to the 44 pt touch target under touch input.
extension MMAdaptiveSizes on BuildContext {
  bool get mmTouch => MMInput.touchOf(this);

  bool get mmTablet => MMInput.of(this).tablet;

  Size get mmToolbarButton => MMThumbDockScope.of(this)
      ? MMSizes.thumbDockButton
      : mmTouch || mmTablet
      ? const Size.square(MMSizes.touchTarget)
      : MMSizes.toolbarButton;

  /// Same compact outer inset for grouped, floating and custom toolbars.
  EdgeInsets get mmToolbarPadding => EdgeInsets.all(mmTablet ? MMToolbarSpacing.inset : 3);

  double get mmSidebarRow => mmTouch || mmTablet ? MMSizes.touchTarget : MMSizes.sidebarRow;

  /// Side of an [MMIconButton] in a toolbar.
  double get mmToolbarIcon => mmTouch || mmTablet ? MMSizes.touchTarget : 28;

  double get mmDividerHit => mmTouch || mmTablet ? MMSizes.touchTarget : MMSizes.dividerHitWidth;
}

/// Gives the phone's workspace dock its own touch metrics.
class MMThumbDockScope extends InheritedWidget {
  const MMThumbDockScope({super.key, required super.child});
  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<MMThumbDockScope>() != null;
  @override
  bool updateShouldNotify(MMThumbDockScope oldWidget) => false;
}
