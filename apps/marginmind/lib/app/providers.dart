import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Composition root for outer-layer services. `main()` overrides the ones
/// that need async setup; tests override the rest.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Override sharedPreferencesProvider in main()'),
);

final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The library. Until mm_data (SQLite) lands this is an in-memory store
/// seeded with the demo study sets from the design canvas.
final studySetRepositoryProvider = Provider<StudySetRepository>((ref) {
  final now = ref.watch(clockProvider);
  final repo = InMemoryStudySetRepository(sets: DemoLibrary.studySets(now()), folders: DemoLibrary.folders, clock: now);
  ref.onDispose(repo.dispose);
  return repo;
});

final studySetsProvider = StreamProvider<List<StudySet>>((ref) => ref.watch(studySetRepositoryProvider).watchAll());

final foldersProvider = StreamProvider<List<Folder>>((ref) => ref.watch(studySetRepositoryProvider).watchFolders());

final systemAppearanceSourceProvider = Provider<SystemAppearanceSource>((ref) {
  final source = SystemAppearanceSource();
  ref.onDispose(source.dispose);
  return source;
});
