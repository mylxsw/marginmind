import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/storage.dart';
import 'app/providers.dart';
import 'features/assistant/assistant_network.dart';
import 'settings/app_icon.dart';
import 'settings/sync_settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MMNativePresentation.initialize();
  await DesktopWindow.initialize(title: 'Foliarc', minimumSize: MMSizes.windowMinSize);
  // Android draws the app under clear status and navigation bars (see systemBarsStyle).
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  await MMPdfEngine.initialize();
  final prefs = await SharedPreferences.getInstance();
  try {
    await const AppIconService().initialize(prefs);
  } catch (error) {
    // A failed Dock restore must not prevent access to the user's library.
    debugPrint('Could not restore the app icon: $error');
  }
  final storage = await openStorage();
  final store = storage.store;
  final sync = SyncSettingsController(
    store,
    storage.vocabulary,
    secrets: const KeychainSecretStore(),
    canActivate: !kIsWeb && MMPlatformCapabilities.current.secretStore,
    canStoreSecrets: MMPlatformCapabilities.current.secretStore,
  );
  await sync.initialize();
  // Foreground-only consent ends when the app loses focus or resumes. The
  // adapter checks the current Apple account again inside each native IO.
  AppLifecycleListener(onInactive: sync.pause, onResume: sync.pause);
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        syncSettingsControllerProvider.overrideWithValue(sync),
        assistantWebCacheProvider.overrideWithValue(storage.cache),
        studySetRepositoryProvider.overrideWithValue(store),
        contentRepositoryProvider.overrideWithValue(store),
        vocabularyRepositoryProvider.overrideWithValue(storage.vocabulary),
      ],
      child: const MarginMindApp(),
    ),
  );
}
