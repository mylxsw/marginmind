import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Keeps the mobile status bar preference across app activation and route changes.
class MobileStatusBar extends StatefulWidget {
  const MobileStatusBar({super.key, required this.enabled, required this.visible, required this.child});

  final bool enabled, visible;
  final Widget child;
  static const androidChannel = MethodChannel('marginmind/system_ui');

  @override
  State<MobileStatusBar> createState() => _MobileStatusBarState();
}

class _MobileStatusBarState extends State<MobileStatusBar> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _apply();
  }

  @override
  void didUpdateWidget(MobileStatusBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible || oldWidget.enabled != widget.enabled) _apply();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _apply();
  }

  Future<void> _apply() async {
    if (!widget.enabled || kIsWeb) return;
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.iOS:
          await SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.manual,
            overlays: [if (widget.visible) SystemUiOverlay.top, SystemUiOverlay.bottom],
          );
        case TargetPlatform.android:
          // Flutter's manual mode is ignored with target SDK 36; control only
          // the status bar through Android's window insets API instead.
          await MobileStatusBar.androidChannel.invokeMethod<void>('setStatusBarVisible', widget.visible);
        default:
          break;
      }
    } catch (error) {
      FlutterError.reportError(FlutterErrorDetails(exception: error, library: 'mobile status bar'));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
