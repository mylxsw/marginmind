import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/providers.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final testNow = DateTime(2026, 10, 25, 12);

/// Pumps the whole app at a desktop window size with fixed time and
/// in-memory storage.
Future<void> pumpApp(WidgetTester tester, {Map<String, Object> prefs = const {}, List<StudySet>? sets}) async {
  tester.view.physicalSize = const Size(1280, 820);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(prefs);
  final instance = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(instance),
        clockProvider.overrideWithValue(() => testNow),
        if (sets != null)
          studySetRepositoryProvider.overrideWithValue(
            InMemoryStudySetRepository(sets: sets, folders: DemoLibrary.folders, clock: () => testNow),
          ),
      ],
      child: const MarginMindApp(),
    ),
  );
  await tester.pumpAndSettle();
}

/// Double-clicks [finder] (Finder-style "open").
Future<void> doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Lets HUD timers run out so tests end without pending timers.
Future<void> settleHud(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}
