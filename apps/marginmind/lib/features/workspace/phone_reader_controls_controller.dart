import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:mm_design/mm_design.dart';

enum PhoneReaderSlot { page, orb, tools, scrub }

/// One bottom slot per workspace. Tool/color state stays in WorkspaceState.
class PhoneReaderControlsController extends ChangeNotifier {
  PhoneReaderControlsController({bool initiallyDockedRight = true, this.onDockChanged})
    : _dockRight = initiallyDockedRight;
  final ValueChanged<bool>? onDockChanged;
  PhoneReaderSlot _slot = PhoneReaderSlot.page;
  PhoneReaderSlot _returnSlot = PhoneReaderSlot.page;
  PhoneReaderSlot get slot => _slot;
  bool _dockRight;
  bool get dockRight => _dockRight;
  bool get interacting => _slot == PhoneReaderSlot.tools || _slot == PhoneReaderSlot.scrub || _drawing;
  bool _drawing = false, _scrubbing = false;
  Object? _document;
  Timer? _timer;

  void _set(PhoneReaderSlot value) {
    _timer?.cancel();
    if (_slot == value) return;
    _slot = value;
    notifyListeners();
  }

  void reset(Object? document) {
    if (_document == document) return;
    final releaseDrawing = _drawing && _slot == PhoneReaderSlot.page;
    _document = document;
    _drawing = _scrubbing = false;
    _set(PhoneReaderSlot.page);
    if (releaseDrawing) notifyListeners();
  }

  void openTools() => _set(PhoneReaderSlot.tools);
  void collapseTools() {
    if (_slot == PhoneReaderSlot.tools) _set(PhoneReaderSlot.orb);
  }

  void selectTool({required bool selection}) {
    openTools();
    if (selection) _schedule(MMMotion.phoneSelectionCollapse);
  }

  void colorChanged() => _timer?.cancel();

  void annotationCompleted(Object document) {
    if (_document == document && _slot == PhoneReaderSlot.tools && !_drawing) {
      _schedule(MMMotion.phoneAnnotationCollapse);
    }
  }

  void _schedule(Duration duration) {
    _timer?.cancel();
    _timer = Timer(duration, collapseTools);
  }

  void openScrub() {
    if (_slot == PhoneReaderSlot.scrub) return;
    _returnSlot = _slot == PhoneReaderSlot.page ? PhoneReaderSlot.page : PhoneReaderSlot.orb;
    _set(PhoneReaderSlot.scrub);
  }

  void closeScrub() {
    _scrubbing = false;
    if (_slot == PhoneReaderSlot.scrub) _set(_returnSlot);
  }

  void setScrubbing(bool value) => _scrubbing = value;

  void setDrawing(bool value) {
    if (_drawing == value) return;
    _drawing = value;
    if (value) _timer?.cancel();
    notifyListeners();
  }

  void onReadingScroll() {
    if (_drawing || _scrubbing) return;
    collapseTools();
    closeScrub();
  }

  void onBodyTap() {
    collapseTools();
    closeScrub();
  }

  void exitTools() {
    final releaseDrawing = _drawing && _slot == PhoneReaderSlot.page;
    _drawing = _scrubbing = false;
    _set(PhoneReaderSlot.page);
    if (releaseDrawing) notifyListeners();
  }

  void dock({required bool right}) {
    if (_dockRight == right) return;
    _dockRight = right;
    onDockChanged?.call(right);
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

bool usePhoneReaderControls(BuildContext context) =>
    MMInput.of(context).phone && MMSizeClass.of(context) == MMSizeClass.compact;

class PhoneReaderControlsScope extends InheritedNotifier<PhoneReaderControlsController> {
  const PhoneReaderControlsScope({
    super.key,
    required PhoneReaderControlsController controller,
    required super.child,
    this.safeBottom = 0,
  }) : super(notifier: controller);

  /// Captured above the workspace SafeArea so the bottom gap uses max, not sum.
  final double safeBottom;
  static double safeBottomOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PhoneReaderControlsScope>()?.safeBottom ?? 0;

  static PhoneReaderControlsController? maybeOf(BuildContext context) => usePhoneReaderControls(context)
      ? context.dependOnInheritedWidgetOfExactType<PhoneReaderControlsScope>()?.notifier
      : null;
  @override
  bool updateShouldNotify(PhoneReaderControlsScope oldWidget) =>
      super.updateShouldNotify(oldWidget) || oldWidget.safeBottom != safeBottom;
}
