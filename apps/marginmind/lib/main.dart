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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DesktopWindow.initialize(title: 'MarginMind', minimumSize: MMSizes.windowMinSize);
  // Android draws the app under clear status and navigation bars (see systemBarsStyle).
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  await MMPdfEngine.initialize();
  final prefs = await SharedPreferences.getInstance();
  final storage = await openStorage();
  final store = storage.store;
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        assistantWebCacheProvider.overrideWithValue(storage.cache),
        studySetRepositoryProvider.overrideWithValue(store),
        contentRepositoryProvider.overrideWithValue(store),
      ],
      child: const MarginMindApp(),
    ),
  );
}
