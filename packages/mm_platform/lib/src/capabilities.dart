import 'package:flutter/foundation.dart';

/// Native implementations shipped by the app, independent of input device or
/// window size. Web must never inherit its host operating system's channels.
class MMPlatformCapabilities {
  const MMPlatformCapabilities(this.platform, {this.web = false});
  final TargetPlatform platform;
  final bool web;
  static MMPlatformCapabilities get current => MMPlatformCapabilities(defaultTargetPlatform, web: kIsWeb);
  bool get mobile => !web && (platform == TargetPlatform.iOS || platform == TargetPlatform.android);
  bool get _mac => !web && platform == TargetPlatform.macOS;
  bool get assistant => !web;
  bool get externalCredentials => !web;
  bool get secretStore => _mac || mobile;
  bool get externalLink => _mac || mobile;
  bool get articleParser => _mac;
  bool get pdfOcr => _mac;
  bool get mapExport => _mac;
  bool get nativeMapClipboard => _mac;
  bool get shareFile => mobile;
  bool get desktopDrop =>
      !web && {TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux}.contains(platform);
}
