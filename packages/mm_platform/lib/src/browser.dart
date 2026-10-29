import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'browser_policy.dart';
import 'browser_scripts.dart';
import 'capabilities.dart';

export 'browser_policy.dart';

part 'browser_document.dart';

class BrowserCapture {
  const BrowserCapture({
    required this.navigationId,
    required this.url,
    required this.title,
    required this.capturedAt,
    required this.dom,
    required this.resources,
  });
  final int navigationId;
  final Uri url;
  final String title, dom;
  final DateTime capturedAt;
  final List<Uri> resources;
}

/// One live tab. Native data stores are app-private and persist independently
/// of this object's lifetime. No cookies or plugin objects cross this boundary.
class BrowserSession extends ChangeNotifier {
  BrowserSession(Uri initialUrl, {this.elapsed, this.onDataCleared}) : url = initialUrl {
    if (!BrowserPolicy.allowsNavigation(initialUrl)) throw ArgumentError.value(initialUrl);
    _channel.setMethodCallHandler(_event);
    _sessions.add(this);
  }
  static int _nextId = 0;
  static final _sessions = <BrowserSession>{};
  static const _manager = MethodChannel('marginmind/browser');
  final int id = ++_nextId;
  late final _channel = MethodChannel('marginmind/browser/$id');
  final _clock = Stopwatch()..start();
  final Duration Function()? elapsed;
  final VoidCallback? onDataCleared;
  Duration get _now => elapsed?.call() ?? _clock.elapsed;
  late BrowserReadiness _readiness = BrowserReadiness(_now);
  Timer? _timer;
  bool _attached = false, _disposed = false, _polling = false;
  bool _capturingDocument = false;
  bool _isLoading = true;
  bool _hasDocument = false;
  int navigationId = 0;
  int _nativeNavigationId = 0;
  Uri url;
  String title = '';
  String? lastErrorCode;
  BrowserLoadError loadError = BrowserLoadError.other;
  bool canGoBack = false, canGoForward = false, prompt = false;
  final _prompted = <BrowserPhase>{};
  ({Uri url, String title, BrowserReadiness readiness, String? signature, Set<BrowserPhase> prompted, bool prompt})?
  _retainedDocument;
  String? _signature;
  int _interactions = 0;
  BrowserPhase get phase => _readiness.phase;
  bool get canCapture => _hasDocument && (phase == BrowserPhase.ready || phase == BrowserPhase.slow);
  bool get loading => _isLoading;

  static Future<void> clearData() async {
    // WebView2's profile API requires an initialized controller, even when
    // clearing persisted data before the first page of this launch.
    BrowserSession? temporary;
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows && !_sessions.any((s) => s._attached)) {
        temporary = BrowserSession(Uri.parse('https://localhost'));
        await _manager.invokeMethod<void>('create', {'id': temporary.id});
      }
      await _manager.invokeMethod<void>('clearData');
    } catch (_) {
      temporary?.dispose();
      rethrow;
    }
    for (final session in _sessions.toList()) {
      session.onDataCleared?.call();
      session.dispose();
    }
  }

  Future<void> attach() async {
    if (_disposed || _attached) return;
    _attached = true;
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) => _poll());
    await navigate(url);
  }

  Future<void> navigate(Uri next) async {
    if (!BrowserPolicy.allowsNavigation(next)) throw ArgumentError.value(next);
    if (_attached) {
      await _command('navigate', {'url': next.toString()});
    } else {
      url = next;
    }
  }

  Future<void> back() => _command('back');
  Future<void> forward() => _command('forward');
  Future<void> reload() => _command('reload');
  Future<void> stop() async {
    final generation = navigationId;
    await _command('stop');
    if (!_disposed && generation == navigationId && phase != BrowserPhase.failed) {
      _readiness.stop();
      _isLoading = false;
      prompt = false;
      notifyListeners();
    }
  }

  void dismissPrompt() {
    prompt = false;
    notifyListeners();
  }

  Future<void> _command(String method, [Map<String, Object?>? args]) async {
    if (_disposed) return;
    if ({'navigate', 'back', 'forward', 'reload'}.contains(method)) {
      _invalidate();
      if (method == 'navigate') url = Uri.parse(args!['url']! as String);
      notifyListeners();
    }
    final generation = navigationId;
    try {
      await _channel.invokeMethod<void>(method, args).timeout(const Duration(seconds: 15));
    } catch (error) {
      if (!_disposed && generation == navigationId) {
        _fail(error is TimeoutException ? BrowserLoadError.timeout : BrowserLoadError.other);
      }
    }
  }

  void _invalidate() {
    if (phase == BrowserPhase.failed) _retainedDocument = null;
    // A provisional navigation may turn out to be a download. Keep the last
    // displayed document until the new one loads. A late download callback
    // may follow an engine's cancellation error for that same navigation.
    if (_hasDocument && !_isLoading && phase != BrowserPhase.failed) {
      _retainedDocument = (
        url: url,
        title: title,
        readiness: _readiness,
        signature: _signature,
        prompted: Set.of(_prompted),
        prompt: prompt,
      );
    }
    navigationId++;
    _isLoading = true;
    _hasDocument = false;
    _readiness = BrowserReadiness(_now);
    _signature = null;
    _prompted.clear();
    prompt = false;
    title = '';
    loadError = BrowserLoadError.other;
    lastErrorCode = null;
  }

  void _fail([BrowserLoadError error = BrowserLoadError.other]) {
    loadError = error;
    _readiness.fail();
    _isLoading = false;
    prompt = false;
    notifyListeners();
  }

  void _updatePrompt() {
    if (canCapture && _prompted.add(phase)) prompt = true;
  }

  Future<void> _event(MethodCall call) async {
    if (_disposed || call.method != 'event') return;
    final data = Map<String, dynamic>.from(call.arguments as Map);
    final nativeId = (data['navigationId'] as num?)?.toInt() ?? _nativeNavigationId;
    if (nativeId < _nativeNavigationId) return;
    if (data['kind'] == 'start') {
      _nativeNavigationId = nativeId;
      _invalidate();
    }
    if (data['kind'] == 'loaded') {
      if (phase == BrowserPhase.failed) return;
      _retainedDocument = null;
      _hasDocument = true;
      _isLoading = false;
      _readiness.finish(_now);
    }
    if (data['kind'] == 'failed') {
      _fail(BrowserLoadError.values.firstWhere((e) => e.name == data['error'], orElse: () => BrowserLoadError.other));
      return;
    }
    if (data['kind'] == 'download') {
      final retained = _retainedDocument;
      if (retained != null) {
        url = retained.url;
        title = retained.title;
        _readiness = retained.readiness;
        _signature = retained.signature;
        _prompted
          ..clear()
          ..addAll(retained.prompted);
        prompt = retained.prompt;
        _hasDocument = true;
        _isLoading = false;
        loadError = BrowserLoadError.other;
        _retainedDocument = null;
        notifyListeners();
      } else if (!_hasDocument || _isLoading) {
        _fail();
      }
      return;
    }
    final next = Uri.tryParse(data['url'] as String? ?? '');
    if (next != null && BrowserPolicy.allowsNavigation(next)) url = next;
    canGoBack = data['back'] == true;
    canGoForward = data['forward'] == true;
    notifyListeners();
  }

  Future<void> _poll() async {
    if (_disposed || _polling || !_attached) return;
    _polling = true;
    final generation = navigationId;
    final previous = (phase, url, title, prompt);
    try {
      final raw = await _channel
          .invokeMethod<String>('evaluate', {'script': browserProbeScript})
          .timeout(const Duration(seconds: 2));
      if (_disposed || generation != navigationId) return;
      if (raw != null) {
        final value = _decode(raw);
        final next = Uri.tryParse(value['url'] as String? ?? '');
        if (next == null || !BrowserPolicy.allowsNavigation(next) || (_isLoading && next != url)) {
          // Provisional loads can still expose about:blank or the old page.
          _readiness.tick(_now);
          if (previous != (phase, url, title, prompt)) notifyListeners();
          return;
        }
        _hasDocument = true;
        if (next != url) {
          // SPA navigation invalidates captures and restarts the heuristic.
          navigationId++;
          _readiness = BrowserReadiness(_now);
          _prompted.clear();
          prompt = false;
          url = next;
        }
        final interactions = (value['interactions'] as num?)?.toInt() ?? 0;
        if (interactions != _interactions && prompt) prompt = false;
        _interactions = interactions;
        title = value['title'] as String? ?? '';
        final signature = '${value['dom']}:${value['network']}';
        if (_signature != signature) {
          _signature = signature;
          _readiness.activity(_now);
        }
        if (!_isLoading && value['complete'] == true && _readiness.loaded == null) _readiness.finish(_now);
      }
      _readiness.tick(_now);
      _updatePrompt();
      if (previous != (phase, url, title, prompt)) notifyListeners();
    } catch (error) {
      lastErrorCode = error is PlatformException ? error.code : 'invalid_observation';
      // A provisional document may disappear while polling; navigation events
      // own load errors. The deadline still advances if JS is unavailable.
      if (!_disposed && generation == navigationId) {
        _readiness.tick(_now);
        _updatePrompt();
        if (previous != (phase, url, title, prompt)) notifyListeners();
      }
    } finally {
      _polling = false;
    }
  }

  /// Serializes the currently displayed DOM, never re-fetches its URL.
  Future<BrowserCapture> capture({required int navigationId}) async {
    if (_disposed || navigationId != this.navigationId || !canCapture) throw StateError('stale_navigation');
    final raw = await _channel
        .invokeMethod<String>('evaluate', {'script': browserCaptureScript})
        .timeout(const Duration(seconds: 15));
    if (_disposed || navigationId != this.navigationId || raw == null) throw StateError('stale_navigation');
    if (raw.length > 16 * 1024 * 1024) throw StateError('capture_too_large');
    final data = _decode(raw);
    final capturedUrl = Uri.parse(data['url'] as String);
    if (capturedUrl != url) throw StateError('stale_navigation');
    return BrowserCapture(
      navigationId: navigationId,
      url: capturedUrl,
      title: data['title'] as String,
      capturedAt: DateTime.now().toUtc(),
      dom: data['dom'] as String,
      resources: List.unmodifiable((data['resources'] as List).cast<String>().map(Uri.parse)),
    );
  }

  static Map<String, dynamic> _decode(String raw) {
    final decoded = jsonDecode(raw);
    return (decoded is String ? jsonDecode(decoded) : decoded) as Map<String, dynamic>;
  }

  bool get disposed => _disposed;
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _clock.stop();
    _sessions.remove(this);
    unawaited(_channel.invokeMethod<void>('dispose').catchError((Object _) {}));
    _channel.setMethodCallHandler(null);
    notifyListeners();
    super.dispose();
  }
}

/// Native rendering stays behind mm_platform. Windows uses a child HWND and
/// receives physical client bounds; hidden tabs explicitly hide that HWND.
class MMBrowserView extends StatefulWidget {
  const MMBrowserView({super.key, required this.session, this.visible = true});
  final BrowserSession session;
  final bool visible;
  @override
  State<MMBrowserView> createState() => _MMBrowserViewState();
}

class _MMBrowserViewState extends State<MMBrowserView> {
  Timer? _bounds;
  @override
  void initState() {
    super.initState();
    if (defaultTargetPlatform == TargetPlatform.windows) {
      _createWindows();
    }
  }

  Future<void> _createWindows() async {
    try {
      await const MethodChannel('marginmind/browser').invokeMethod<void>('create', {'id': widget.session.id});
      if (!mounted || widget.session.disposed) {
        await MethodChannel('marginmind/browser/${widget.session.id}').invokeMethod<void>('dispose');
        return;
      }
      await widget.session.attach();
      _bounds = Timer.periodic(const Duration(milliseconds: 100), (_) => _position());
      _position();
    } catch (_) {
      if (mounted) {
        widget.session._fail();
      }
    }
  }

  void _position() {
    if (!mounted || widget.session.disposed) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final offset = box.localToGlobal(Offset.zero), ratio = View.of(context).devicePixelRatio;
    unawaited(
      MethodChannel('marginmind/browser/${widget.session.id}')
          .invokeMethod<void>('bounds', {
            'x': offset.dx * ratio,
            'y': offset.dy * ratio,
            'width': box.size.width * ratio,
            'height': box.size.height * ratio,
            'visible': widget.visible && (ModalRoute.of(context)?.isCurrent ?? true),
          })
          .catchError((Object _) {}),
    );
  }

  @override
  void dispose() {
    _bounds?.cancel();
    if (defaultTargetPlatform == TargetPlatform.windows) {
      unawaited(
        MethodChannel('marginmind/browser/${widget.session.id}')
            .invokeMethod<void>('bounds', {'x': 0.0, 'y': 0.0, 'width': 0.0, 'height': 0.0, 'visible': false})
            .catchError((Object _) {}),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!MMPlatformCapabilities.current.webBrowser) return const SizedBox.shrink();
    final params = {'id': widget.session.id};
    return switch (defaultTargetPlatform) {
      TargetPlatform.macOS => AppKitView(
        viewType: 'marginmind/browser',
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (_) => widget.session.attach(),
      ),
      TargetPlatform.iOS => UiKitView(
        viewType: 'marginmind/browser',
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (_) => widget.session.attach(),
      ),
      TargetPlatform.android => AndroidView(
        viewType: 'marginmind/browser',
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (_) => widget.session.attach(),
      ),
      _ => const SizedBox.expand(),
    };
  }
}
