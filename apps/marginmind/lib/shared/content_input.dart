import 'package:mm_core/mm_core.dart';

/// Opens an input only after in-flight repository writes have settled. Reading
/// through the repository avoids using a widget snapshot from the previous frame.
class ContentInput<T> {
  const ContentInput({
    required this.repository,
    required this.studySetId,
    required this.paths,
    required this.read,
    this.relatedPaths,
  });

  bool get requiresProtection => repository is ContentEditRepository;

  final StudySetContentRepository repository;
  final String studySetId;
  final List<List<String>> paths;
  final T? Function(StudySetContent) read;
  final List<List<String>> Function(StudySetContent)? relatedPaths;

  Future<ContentInputSession<T>> open() async {
    final leases = <ContentEditLease>[];
    try {
      if (repository case final ContentEditRepository editing) {
        final lease = editing.protectContent(studySetId, paths);
        leases.add(lease);
        await lease.ready;
        // A source reference may itself have changed in the in-flight write.
        // Protect the latest referenced entity before reading its text.
        if (relatedPaths case final related?) {
          final paths = related(await repository.load(studySetId));
          if (paths.isNotEmpty) {
            final dependencies = editing.protectContent(studySetId, paths);
            leases.add(dependencies);
            await dependencies.ready;
          }
        }
      }
      final value = read(await repository.load(studySetId));
      if (value == null) throw StateError('The edited content no longer exists');
      return ContentInputSession(value, leases);
    } catch (_) {
      for (final lease in leases) {
        await lease.release();
      }
      rethrow;
    }
  }
}

/// Protection survives widget disposal until an outstanding save finishes.
/// A failed save leaves a mounted editor protected so the user can retry.
class ContentInputSession<T> {
  ContentInputSession(this.value, this._leases);
  final T value;
  final List<ContentEditLease> _leases;
  Future<void>? _saving;
  Future<void>? _closing;

  Future<void> save(Future<void> Function() write) {
    if (_closing != null) throw StateError('Input is closed');
    if (_saving != null) throw StateError('Input is already saving');
    // Register the write before invoking code that might dispose its editor.
    final result = Future<void>.microtask(write);
    _saving = result;
    return result.whenComplete(() => _saving = null);
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    try {
      await _saving;
    } catch (_) {
      // The save caller owns the error. Disposal must still release protection.
    }
    for (final lease in _leases) {
      await lease.release();
    }
  }
}
