import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mm_core/mm_core.dart';
import 'package:path/path.dart' as p;

import 'format_migration.dart';

/// Stores the library on disk:
///
/// ```
/// <root>/library.json                       folders
/// <root>/sets/<id>.mmset/studyset.json      metadata + content
/// <root>/sets/<id>.mmset/documents/<sha1>.pdf
/// ```
///
/// Each study set is a self-contained folder ("package") that can be copied
/// or backed up as a whole. Writes go to a temp file and are renamed into
/// place, and writes to one set are serialized. A SQLite store (drift) can
/// replace this behind the same ports once data grows.
class FileLibraryStore
    implements StudySetRepository, StudySetContentRepository, ResearchSessionRepository, ResearchSnapshotRepository {
  FileLibraryStore(this.root, {DateTime Function()? clock, String Function()? idGenerator})
    : _clock = clock ?? DateTime.now,
      _newId = idGenerator ?? newId;

  final Directory root;
  final DateTime Function() _clock;
  final String Function() _newId;

  final Map<String, _SetRecord> _sets = {};
  List<Folder> _folders = [];
  bool _loaded = false;
  Future<void>? _loading;
  final Map<String, Object> _packageLoadErrors = {};

  /// Failures from the last library scan, keyed by package path. Failed
  /// packages are skipped; callers may surface these diagnostics separately.
  Map<String, Object> get packageLoadErrors => Map.unmodifiable(_packageLoadErrors);
  final _researchSessionSyncErrors = <String, Object>{};

  /// A session is a projection of canonical note ids. Its failure must not
  /// turn a committed content edit into a failed (and unrecorded) undo step.
  Map<String, Object> get researchSessionSyncErrors => Map.unmodifiable(_researchSessionSyncErrors);
  final _libraryChanges = StreamController<void>.broadcast();
  final _contentChanges = StreamController<String>.broadcast();
  final Map<String, Future<void>> _writeQueue = {};

  Directory get _setsDir => Directory(p.join(root.path, 'sets'));
  File get _libraryFile => File(p.join(root.path, 'library.json'));
  String _packagePath(String id) => p.join(_setsDir.path, '$id.mmset');

  Future<void> _ensureLoaded() => _loading ??= _load().catchError((Object error, StackTrace stack) {
    // Root/library failures must not poison subsequent operations forever.
    _loading = null;
    Error.throwWithStackTrace(error, stack);
  });

  Future<void> _load() async {
    final sets = <String, _SetRecord>{};
    var folders = <Folder>[];
    _packageLoadErrors.clear();
    await _setsDir.create(recursive: true);
    if (await _libraryFile.exists()) {
      final json = jsonDecode(await _libraryFile.readAsString()) as Map<String, Object?>;
      folders = [
        for (final f in (json['folders'] as List?) ?? const [])
          Folder(id: (f as Map)['id'] as String, name: f['name'] as String),
      ];
    }
    await for (final entry in _setsDir.list()) {
      if (entry is! Directory || !entry.path.endsWith('.mmset')) continue;
      final file = File(p.join(entry.path, 'studyset.json'));
      try {
        if (!await file.exists()) continue;
        final original = await file.readAsBytes();
        final json = jsonDecode(utf8.decode(original)) as Map<String, Object?>;
        final migrated = migrateStudySet(json);
        // Decode before touching disk so invalid input cannot replace the source.
        final record = _SetRecord.fromJson(migrated);
        if (json['format'] != currentStudySetFormat) {
          final backup = File('${file.path}.format-${json['format']}.bak');
          if (!await backup.exists()) {
            await _atomicWrite(backup, original);
          } else if (!_sameBytes(await backup.readAsBytes(), original)) {
            throw FileSystemException('Migration backup differs from source', backup.path);
          }
          await _atomicWrite(file, utf8.encode(const JsonEncoder.withIndent('  ').convert(migrated)));
        }
        sets[record.id] = record;
      } on FormatException catch (error) {
        _packageLoadErrors[entry.path] = error;
      } on TypeError catch (error) {
        _packageLoadErrors[entry.path] = FormatException('Invalid study set data: $error');
      } on ArgumentError catch (error) {
        _packageLoadErrors[entry.path] = FormatException('Invalid study set data: $error');
      } on FileSystemException catch (error) {
        // Backup conflicts and package IO failures affect only this package.
        // Do not repair or overwrite its source/backup on the error path.
        _packageLoadErrors[entry.path] = error;
      }
    }
    _sets
      ..clear()
      ..addAll(sets);
    _folders = folders;
    _loaded = true;
  }

  // ---- StudySetRepository ------------------------------------------------

  @override
  Stream<List<StudySet>> watchAll() => _watch(_libraryChanges.stream, () => _summaries());

  @override
  Stream<List<Folder>> watchFolders() => _watch(_libraryChanges.stream, () => List.unmodifiable(_folders));

  List<StudySet> _summaries() => [for (final r in _sets.values) r.summary(_clock())];

  @override
  Future<StudySet> create(NewStudySet input) async {
    await _ensureLoaded();
    final now = _clock();
    final record = _SetRecord(
      id: _newId(),
      title: input.title.trim(),
      colorIndex: input.colorIndex,
      folderId: input.folderId,
      starred: false,
      createdAt: now,
      lastOpenedAt: now,
      content: StudySetContent.empty,
    );
    _sets[record.id] = record;
    await Directory(p.join(_packagePath(record.id), 'documents')).create(recursive: true);
    await _persist(record.id);
    _libraryChanges.add(null);
    return record.summary(now);
  }

  @override
  Future<void> setStarred(String id, {required bool starred}) => _updateMeta(id, (r) => r.copyWith(starred: starred));

  @override
  Future<void> markOpened(String id) => _updateMeta(id, (r) => r.copyWith(lastOpenedAt: _clock()));

  @override
  Future<void> rename(String id, String title) => _updateMeta(id, (r) => r.copyWith(title: title.trim()));

  @override
  Future<void> setColor(String id, int colorIndex) => _updateMeta(id, (r) => r.copyWith(colorIndex: colorIndex));

  @override
  Future<void> delete(String id) async {
    await _ensureLoaded();
    _require(id);
    _sets.remove(id);
    _libraryChanges.add(null);
    _contentChanges.add(id);
    // Let a pending write finish first so it cannot recreate the folder.
    await (_writeQueue.remove(id) ?? Future<void>.value());
    final dir = Directory(_packagePath(id));
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<void> _updateMeta(String id, _SetRecord Function(_SetRecord) change) async {
    await _ensureLoaded();
    final record = _require(id);
    _sets[id] = change(record);
    await _persist(id);
    _libraryChanges.add(null);
  }

  // ---- StudySetContentRepository -----------------------------------------

  @override
  Future<StudySetContent> load(String studySetId) async {
    await _ensureLoaded();
    return _require(studySetId).content;
  }

  @override
  Stream<StudySetContent> watch(String studySetId) => _watch(
    _contentChanges.stream.where((id) => id == studySetId),
    () => _sets[studySetId]?.content ?? StudySetContent.empty,
  );

  @override
  Future<StudySetContent> update(String studySetId, StudySetContent Function(StudySetContent) change) async {
    await _ensureLoaded();
    final record = _require(studySetId);
    final next = change(record.content);
    _sets[studySetId] = record.copyWith(content: next);
    _contentChanges.add(studySetId);
    _libraryChanges.add(null);
    await _persist(studySetId, syncSessions: !identical(record.content.researchNotes, next.researchNotes));
    return next;
  }

  @override
  Future<String> importFile(String studySetId, String sourcePath) async {
    await _ensureLoaded();
    _require(studySetId);
    final source = File(sourcePath);
    final digest = sha1.convert(await source.readAsBytes()).toString();
    final ext = p.extension(sourcePath).toLowerCase();
    final fileName = p.join('documents', '$digest${ext.isEmpty ? '.pdf' : ext}');
    final target = File(p.join(_packagePath(studySetId), fileName));
    if (!await target.exists()) {
      await target.parent.create(recursive: true);
      await source.copy(target.path);
    }
    return fileName;
  }

  @override
  Future<String> importImage(String studySetId, String sourcePath) async {
    await _ensureLoaded();
    _require(studySetId);
    return importImageBytes(studySetId, await File(sourcePath).readAsBytes());
  }

  @override
  Future<String> importImageBytes(String studySetId, List<int> bytes) async {
    await _ensureLoaded();
    _require(studySetId);
    final String extension;
    if (bytes.length >= 8 && _sameBytes(bytes.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10])) {
      extension = 'png';
    } else if (bytes.length >= 3 && bytes[0] == 255 && bytes[1] == 216 && bytes[2] == 255) {
      extension = 'jpg';
    } else {
      throw const FormatException('Expected PNG or JPEG image');
    }
    final name = 'images/${sha256.convert(bytes)}.$extension';
    final target = File(p.join(_packagePath(studySetId), name));
    // Use the same per-set queue as JSON writes, including concurrent imports.
    await _queueWrite(studySetId, () async {
      if (!await target.exists()) await _atomicWrite(target, bytes);
    });
    return name;
  }

  static void _safeResearchId(String id) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) throw ArgumentError.value(id, 'sessionId');
  }

  static void _safeSnapshot(String name) {
    if (!RegExp(r'^research/snapshots/[0-9a-f]{64}\.md$').hasMatch(name)) {
      throw ArgumentError.value(name, 'snapshotFile');
    }
  }

  Future<void> _queueWrite(String id, Future<void> Function() action) {
    final next = (_writeQueue[id] ?? Future<void>.value()).then((_) => action());
    // Each caller observes its own error; later writes can still retry.
    _writeQueue[id] = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  @override
  Future<String> writeResearchSnapshot(String studySetId, String markdown) async {
    await _ensureLoaded();
    _require(studySetId);
    final bytes = utf8.encode(markdown);
    final name = 'research/snapshots/${sha256.convert(bytes)}.md';
    final file = File(resolveFile(studySetId, name));
    await _queueWrite(studySetId, () async {
      _require(studySetId);
      if (await file.exists()) {
        if (!_sameBytes(await file.readAsBytes(), bytes)) {
          throw FileSystemException('Snapshot hash conflict', file.path);
        }
      } else {
        await _atomicWrite(file, bytes);
      }
    });
    return name;
  }

  @override
  Future<String> readResearchSnapshot(String studySetId, String fileName) async {
    await _ensureLoaded();
    _require(studySetId);
    _safeSnapshot(fileName);
    final bytes = await File(resolveFile(studySetId, fileName)).readAsBytes();
    if ('research/snapshots/${sha256.convert(bytes)}.md' != fileName) {
      throw const FormatException('Snapshot hash mismatch');
    }
    return utf8.decode(bytes);
  }

  @override
  Future<void> saveResearchSession(String studySetId, ResearchSession session) async {
    await _ensureLoaded();
    _require(studySetId);
    _safeResearchId(session.id);
    await _queueWrite(studySetId, () async {
      final current = session.reconcile(_require(studySetId).content);
      await _atomicWrite(
        File(resolveFile(studySetId, 'research/sessions/${session.id}.json')),
        utf8.encode(jsonEncode(current.toJson())),
      );
    });
  }

  @override
  Future<ResearchSession?> loadResearchSession(String studySetId, String sessionId) async {
    await _ensureLoaded();
    _require(studySetId);
    _safeResearchId(sessionId);
    await (_writeQueue[studySetId] ?? Future<void>.value());
    final file = File(resolveFile(studySetId, 'research/sessions/$sessionId.json'));
    if (!await file.exists()) return null;
    final session = ResearchSession.fromJson((jsonDecode(await file.readAsString()) as Map).cast());
    if (session.id != sessionId) throw const FormatException('Session id mismatch');
    return session.reconcile(_require(studySetId).content);
  }

  Future<void> _syncResearchSessions(String id, StudySetContent content) async {
    final dir = Directory(resolveFile(id, 'research/sessions'));
    try {
      if (!await dir.exists()) return;
      await for (final file in dir.list()) {
        if (file is! File || !file.path.endsWith('.json')) continue;
        try {
          final session = ResearchSession.fromJson((jsonDecode(await file.readAsString()) as Map).cast());
          final updated = session.reconcile(content);
          if (jsonEncode(session.savedNoteIds) != jsonEncode(updated.savedNoteIds)) {
            await _atomicWrite(file, utf8.encode(jsonEncode(updated.toJson())));
          }
          _researchSessionSyncErrors.remove(file.path);
        } catch (error) {
          _researchSessionSyncErrors[file.path] = error;
        }
      }
      _researchSessionSyncErrors.remove(dir.path);
    } on FileSystemException catch (error) {
      _researchSessionSyncErrors[dir.path] = error;
    }
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static Future<void> _atomicWrite(File file, List<int> bytes) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
  }

  @override
  String resolveFile(String studySetId, String fileName) => p.join(_packagePath(studySetId), fileName);

  // ---- internals -----------------------------------------------------------

  _SetRecord _require(String id) => _sets[id] ?? (throw StateError('Unknown study set: $id'));

  Stream<T> _watch<T>(Stream<Object?> changes, T Function() snapshot) {
    StreamSubscription<Object?>? sub;
    late final StreamController<T> out;
    out = StreamController<T>(
      onListen: () async {
        try {
          await _ensureLoaded();
          if (out.isClosed) return;
          out.add(snapshot());
          sub = changes.listen((_) => out.add(snapshot()));
        } catch (error, stack) {
          if (!out.isClosed) out.addError(error, stack);
        }
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  /// Serializes writes per set; each write stores the latest in-memory state.
  Future<void> _persist(String id, {bool syncSessions = false}) {
    return _queueWrite(id, () async {
      final record = _sets[id];
      if (record == null) return;
      final dir = Directory(_packagePath(id));
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, 'studyset.json'));
      await _atomicWrite(file, utf8.encode(const JsonEncoder.withIndent('  ').convert(record.toJson())));
      if (syncSessions) await _syncResearchSessions(id, record.content);
    });
  }

  /// Waits for pending writes (used by tests and on shutdown).
  Future<void> flush() => Future.wait(_writeQueue.values);

  bool get isLoaded => _loaded;

  Future<void> dispose() async {
    await flush();
    await _libraryChanges.close();
    await _contentChanges.close();
  }
}

class _SetRecord {
  const _SetRecord({
    required this.id,
    required this.title,
    required this.colorIndex,
    required this.folderId,
    required this.starred,
    required this.createdAt,
    required this.lastOpenedAt,
    required this.content,
  });

  final String id;
  final String title;
  final int colorIndex;
  final String? folderId;
  final bool starred;
  final DateTime createdAt;
  final DateTime lastOpenedAt;
  final StudySetContent content;

  _SetRecord copyWith({
    String? title,
    int? colorIndex,
    bool? starred,
    DateTime? lastOpenedAt,
    StudySetContent? content,
  }) => _SetRecord(
    id: id,
    title: title ?? this.title,
    colorIndex: colorIndex ?? this.colorIndex,
    folderId: folderId,
    starred: starred ?? this.starred,
    createdAt: createdAt,
    lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    content: content ?? this.content,
  );

  StudySet summary(DateTime now) {
    final last = content.lastRead;
    final totalPages = content.documents.fold<int>(0, (s, d) => s + d.pageCount);
    final readPages = content.documents.fold<int>(0, (s, d) => s + d.lastPage);
    return StudySet(
      id: id,
      title: title,
      colorIndex: colorIndex,
      folderId: folderId,
      starred: starred,
      documentCount: content.documents.length,
      cardCount: content.cardCount,
      dueCount: content.dueCount(now),
      reviewLogCount: content.reviewLogs.length,
      readPages: content.documents.isEmpty ? 0 : readPages,
      totalPages: totalPages,
      lastPosition: last == null ? null : ReadingPosition(documentTitle: last.title, page: last.lastPage),
      createdAt: createdAt,
      lastOpenedAt: lastOpenedAt,
    );
  }

  Map<String, Object?> toJson() => {
    'format': currentStudySetFormat,
    'id': id,
    'title': title,
    'colorIndex': colorIndex,
    if (folderId != null) 'folderId': folderId,
    'starred': starred,
    'createdAt': createdAt.toIso8601String(),
    'lastOpenedAt': lastOpenedAt.toIso8601String(),
    'content': content.toJson(),
  };

  factory _SetRecord.fromJson(Map<String, Object?> j) => _SetRecord(
    id: j['id'] as String,
    title: j['title'] as String,
    colorIndex: j['colorIndex'] as int,
    folderId: j['folderId'] as String?,
    starred: (j['starred'] as bool?) ?? false,
    createdAt: DateTime.parse(j['createdAt'] as String),
    lastOpenedAt: DateTime.parse(j['lastOpenedAt'] as String),
    content: StudySetEditor.initializeMemory(StudySetContent.fromJson(((j['content'] as Map?) ?? const {}).cast())),
  );
}
