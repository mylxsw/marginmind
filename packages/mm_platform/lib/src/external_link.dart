import 'package:flutter/services.dart';

/// Opens web pages in the user's browser. Only http(s) addresses leave the
/// app; anything else (file:, javascript:, custom schemes) is refused here and
/// again natively.
class ExternalLinks {
  const ExternalLinks([this._channel = const MethodChannel('marginmind/external_link')]);

  final MethodChannel _channel;

  /// Whether [url] may be opened: an absolute http(s) address with a host.
  static bool canOpen(Uri url) => (url.scheme == 'http' || url.scheme == 'https') && url.host.isNotEmpty;

  /// True when the browser took the address.
  Future<bool> open(Uri url) async {
    if (!canOpen(url)) return false;
    try {
      return await _channel.invokeMethod<bool>('open', {'url': url.toString()}) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
