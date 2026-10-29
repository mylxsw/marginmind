/// Errors are codes; the application localizes them.
enum BrowserUrlError { empty, invalid, scheme }

class BrowserUrlException implements Exception {
  const BrowserUrlException(this.code);
  final BrowserUrlError code;
}

abstract final class BrowserPolicy {
  static Uri normalize(String input) {
    var value = input.trim();
    if (value.isEmpty) throw const BrowserUrlException(BrowserUrlError.empty);
    // A host:port is an address, rather than a custom protocol.
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(value) || RegExp(r'^[^/:]+:\d+([/?#]|$)').hasMatch(value)) {
      value = 'https://$value';
    }
    final uri = Uri.tryParse(value);
    if (uri == null) throw const BrowserUrlException(BrowserUrlError.invalid);
    if (!{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
      throw const BrowserUrlException(BrowserUrlError.scheme);
    }
    if (!allowsNavigation(uri) ||
        (uri.hasPort && (uri.port < 1 || uri.port > 65535)) ||
        uri.host.startsWith('.') ||
        uri.host.contains('..') ||
        uri.userInfo.isNotEmpty ||
        RegExp(r'[\s\\\x00-\x1f]').hasMatch(value) ||
        (!uri.host.contains('.') && uri.host != 'localhost' && !uri.host.contains(':'))) {
      throw const BrowserUrlException(BrowserUrlError.invalid);
    }
    return uri;
  }

  static bool allowsNavigation(Uri uri, {bool download = false}) =>
      !download && {'http', 'https'}.contains(uri.scheme.toLowerCase()) && uri.host.isNotEmpty;
}

enum BrowserPhase { loading, ready, slow, failed }

/// Deterministic clock injected by the session. No timers or platform objects.
class BrowserReadiness {
  BrowserReadiness(this.started);
  final Duration started;
  Duration? loaded, lastActivity;
  BrowserPhase phase = BrowserPhase.loading;
  bool _stopped = false;
  void stop() {
    _stopped = true;
    phase = BrowserPhase.slow;
  }

  void activity(Duration now) => lastActivity = now;
  void finish(Duration now) {
    loaded = now;
    activity(now);
  }

  void fail() => phase = BrowserPhase.failed;

  BrowserPhase tick(Duration now) {
    if (phase == BrowserPhase.failed || _stopped) return phase;
    if (loaded != null && now - (lastActivity ?? loaded!) >= const Duration(milliseconds: 800)) {
      phase = BrowserPhase.ready;
    } else if (now - started >= const Duration(seconds: 15)) {
      phase = BrowserPhase.slow;
    } else {
      phase = BrowserPhase.loading;
    }
    return phase;
  }
}
