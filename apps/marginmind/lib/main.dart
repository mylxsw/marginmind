import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:mm_research/mm_research.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'features/research/research_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DesktopWindow.initialize(title: 'MarginMind', minimumSize: MMSizes.windowMinSize);
  await MMPdfEngine.initialize();
  final prefs = await SharedPreferences.getInstance();
  final support = await getApplicationSupportDirectory();
  final store = FileLibraryStore(Directory(p.join(support.path, 'Library')));
  // Complete recovery before any provider can submit a new request.
  final recovery = ResearchRecovery(store, () async => (await store.watchAll().first).map((s) => s.id).toList());
  try {
    await recovery.ready;
  } catch (_) {
    // Keep non-research work available; the failed barrier remains visible to
    // research providers and still prevents every new request.
    debugPrint('Research recovery failed; research requests remain disabled.');
  }
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        researchRecoveryProvider.overrideWithValue(recovery),
        researchCacheProvider.overrideWithValue(ResearchWebCache(support)),
        studySetRepositoryProvider.overrideWithValue(store),
        contentRepositoryProvider.overrideWithValue(store),
      ],
      child: const MarginMindApp(),
    ),
  );
}
