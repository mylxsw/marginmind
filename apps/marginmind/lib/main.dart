import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'features/assistant/assistant_network.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DesktopWindow.initialize(title: 'MarginMind', minimumSize: MMSizes.windowMinSize);
  // Android draws the app under clear status and navigation bars (see systemBarsStyle).
  if (Platform.isAndroid) await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await MMPdfEngine.initialize();
  final prefs = await SharedPreferences.getInstance();
  final support = await getApplicationSupportDirectory();
  final store = FileLibraryStore(Directory(p.join(support.path, 'Library')));
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        assistantWebCacheProvider.overrideWithValue(ResearchWebCache(support)),
        studySetRepositoryProvider.overrideWithValue(store),
        contentRepositoryProvider.overrideWithValue(store),
      ],
      child: const MarginMindApp(),
    ),
  );
}
