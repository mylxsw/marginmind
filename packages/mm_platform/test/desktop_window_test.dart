import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_platform/mm_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const nativeChrome = MethodChannel('macos_window_utils/window_manipulator');
  const manager = MethodChannel('window_manager');
  const screens = MethodChannel('dev.leanflutter.plugins/screen_retriever');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> chromeCalls;
  late List<MethodCall> windowCalls;
  var maximized = false;
  var fullScreen = false;

  setUp(() {
    fullScreen = false;
    chromeCalls = [];
    windowCalls = [];
    maximized = false;
    messenger.setMockMethodCallHandler(screens, (call) async {
      final display = {
        'id': 'primary',
        'size': {'width': 1600.0, 'height': 1000.0},
        'visiblePosition': {'dx': 0.0, 'dy': 0.0},
      };
      return switch (call.method) {
        'getPrimaryDisplay' => display,
        'getAllDisplays' => {
          'displays': [display],
        },
        'getCursorScreenPoint' => {'dx': 100.0, 'dy': 100.0},
        _ => null,
      };
    });
    messenger.setMockMethodCallHandler(nativeChrome, (call) async {
      chromeCalls.add(call);
      return true;
    });
    messenger.setMockMethodCallHandler(manager, (call) async {
      windowCalls.add(call);
      return switch (call.method) {
        'isMaximized' => maximized,
        'isFullScreen' => fullScreen,
        'isMinimized' => false,
        'getBounds' => {'x': 0.0, 'y': 0.0, 'width': 1280.0, 'height': 820.0},
        _ => null,
      };
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(nativeChrome, null);
    messenger.setMockMethodCallHandler(manager, null);
    messenger.setMockMethodCallHandler(screens, null);
  });

  test('macOS keeps the native toolbar and configures full-size content before showing', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(DesktopWindow.drawsWindowButtonsInContent, isTrue);
    await DesktopWindow.initialize(title: 'MarginMind', minimumSize: const Size(900, 600));
    // The ready-to-show callback also requests focus asynchronously.
    await Future<void>.delayed(Duration.zero);
    expect(chromeCalls.map((call) => call.method), [
      'initialize',
      'makeTitlebarTransparent',
      'enableFullSizeContentView',
      'hideTitle',
    ]);
    expect(windowCalls.first.method, 'ensureInitialized');
    expect(
      windowCalls.map((call) => call.method),
      containsAllInOrder(['setBounds', 'setMinimumSize', 'setTitle', 'show', 'focus']),
    );
    expect(windowCalls.firstWhere((call) => call.method == 'setTitle').arguments, {'title': 'MarginMind'});
  });

  for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
    test('$platform keeps its system title bar', () async {
      debugDefaultTargetPlatformOverride = platform;
      expect(DesktopWindow.isDesktop, isTrue);
      expect(DesktopWindow.drawsWindowButtonsInContent, isFalse);
      await DesktopWindow.initialize(title: 'MarginMind', minimumSize: const Size(900, 600));
      await Future<void>.delayed(Duration.zero);
      expect(chromeCalls, isEmpty);
      expect(windowCalls.map((call) => call.method), contains('show'));
    });
  }

  test('mobile does not invoke desktop APIs', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(DesktopWindow.isDesktop, isFalse);
    await DesktopWindow.initialize(title: 'MarginMind', minimumSize: const Size(900, 600));
    DesktopWindow.startDragging();
    await DesktopWindow.toggleZoom();
    expect(windowCalls, isEmpty);
    expect(chromeCalls, isEmpty);
  });

  test('empty chrome starts a native drag and toggles zoom in both directions', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    DesktopWindow.startDragging();
    await DesktopWindow.toggleZoom();
    expect(windowCalls.map((call) => call.method), ['startDragging', 'isMaximized', 'maximize']);
    windowCalls.clear();
    maximized = true;
    await DesktopWindow.toggleZoom();
    expect(windowCalls.map((call) => call.method), ['isMaximized', 'unmaximize']);
  });

  test('full screen follows the native events and the toggle goes the other way', () async {
    // Linux skips the macOS-only toolbar setup, which can run once per process.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    fullScreen = true;
    await DesktopWindow.initialize(title: 'MarginMind', minimumSize: const Size(900, 600));
    expect(DesktopWindow.fullScreen.value, isTrue, reason: 'read from the window at startup');

    Future<void> native(String event) => messenger.handlePlatformMessage(
      'window_manager',
      const StandardMethodCodec().encodeMethodCall(MethodCall('onEvent', {'eventName': event})),
      (_) {},
    );
    await native('leave-full-screen');
    expect(DesktopWindow.fullScreen.value, isFalse);
    await native('enter-full-screen');
    expect(DesktopWindow.fullScreen.value, isTrue);

    windowCalls.clear();
    await DesktopWindow.toggleFullScreen();
    expect(windowCalls.map((call) => call.method), ['isFullScreen', 'setFullScreen']);
    expect(windowCalls.last.arguments, {'isFullScreen': false});
    windowCalls.clear();
    fullScreen = false;
    await DesktopWindow.toggleFullScreen();
    expect(windowCalls.last.arguments, {'isFullScreen': true});

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    windowCalls.clear();
    await DesktopWindow.toggleFullScreen();
    expect(windowCalls, isEmpty);
    DesktopWindow.debugSetFullScreen(false);
    expect(DesktopWindow.fullScreen.value, isFalse);
  });
}
