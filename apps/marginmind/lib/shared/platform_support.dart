import 'package:flutter/foundation.dart';

// Local policy until the shared GUL-539 capability interface lands.
bool get supportsNativeMapExport => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
bool get supportsAssistant => !kIsWeb;
bool get supportsExternalCredentials => !kIsWeb;
