import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Composition root for outer-layer services. `main()` provides the real
/// implementations (files on disk); tests override them with in-memory ones.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Override sharedPreferencesProvider in main()'),
);

final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Library index (one row per study set).
final studySetRepositoryProvider = Provider<StudySetRepository>(
  (ref) => throw UnimplementedError('Override studySetRepositoryProvider in main()'),
);

/// Contents of each study set (documents, highlights, cards, map).
final contentRepositoryProvider = Provider<StudySetContentRepository>(
  (ref) => throw UnimplementedError('Override contentRepositoryProvider in main()'),
);

/// Applies edits to study set content; ids and timestamps come from here.
final editorProvider = Provider<StudySetEditor>((ref) => StudySetEditor(newId: newId, now: ref.watch(clockProvider)));

final studySetsProvider = StreamProvider<List<StudySet>>((ref) => ref.watch(studySetRepositoryProvider).watchAll());

final foldersProvider = StreamProvider<List<Folder>>((ref) => ref.watch(studySetRepositoryProvider).watchFolders());

final contentProvider = StreamProvider.family<StudySetContent, String>(
  (ref, id) => ref.watch(contentRepositoryProvider).watch(id),
);

final systemAppearanceSourceProvider = Provider<SystemAppearanceSource>((ref) {
  final source = SystemAppearanceSource();
  ref.onDispose(source.dispose);
  return source;
});

/// One study set's library row (title, color…), or null while loading.
final studySetProvider = Provider.family<StudySet?, String>(
  (ref, id) => ref.watch(studySetsProvider).value?.where((s) => s.id == id).firstOrNull,
);

/// Whether research has a usable UI. Its commands and the research panel are
/// registered already, but stay out of menus, toolbars and shortcuts until
/// the research flow is wired in.
final researchAvailableProvider = Provider<bool>((ref) => false);

/// Whether the source pane renders PDFs. Widget tests turn this off
/// because they have no real files and no PDFium.
final pdfRenderingEnabledProvider = Provider<bool>((ref) => true);

/// Talks to the PDF view of a study set's source pane, so menus, the reader
/// sidebar and the find bar can drive it without owning it.
final readerPdfProvider = Provider.family<MMPdfViewController, String>((ref, studySetId) {
  final controller = MMPdfViewController();
  ref.onDispose(controller.dispose);
  return controller;
});
