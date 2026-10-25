import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mm_core/mm_core.dart';
import 'package:path/path.dart' as p;

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
class FileLibraryStore implements StudySetRepository, StudySetContentRepository {
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
  final _libraryChanges = StreamController<void>.broadcast();
  final _contentChanges = StreamController<String>.broadcast();
  final Map<String, Future<void>> _writeQueue = {};

  Directory get _setsDir => Directory(p.join(root.path, 'sets'));
  File get _libraryFile => File(p.join(root.path, 'library.json'));
  String _packagePath(String id) => p.join(_setsDir.path, '$id.mmset');

  Future<void> _ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    await _setsDir.create(recursive: true);
    if (await _libraryFile.exists()) {
      final json = jsonDecode(await _libraryFile.readAsString()) as Map<String, Object?>;
      _folders = [
        for (final f in (json['folders'] as List?) ?? const [])
          Folder(id: (f as Map)['id'] as String, name: f['name'] as String),
      ];
    }
    await for (final entry in _setsDir.list()) {
      if (entry is! Directory || !entry.path.endsWith('.mmset')) continue;
      final file = File(p.join(entry.path, 'studyset.json'));
      if (!await file.exists()) continue;
      try {
        final record = _SetRecord.fromJson(jsonDecode(await file.readAsString()) as Map<String, Object?>);
        _sets[record.id] = record;
      } on FormatException {
        // A damaged package is skipped rather than taking the library down.
        continue;
      }
    }
    _loaded = true;
  }

  // ---- StudySetRepository ------------------------------------------------

  @override
  Stream<List<StudySet>> watchAll() => _watch(_libraryChanges.stream, () => _summaries());

  @override
  Stream<List<Folder>> watchFolders() => _watch(_libraryChanges.stream, () => List.unmodifiable(_folders));

  List<StudySet> _summaries() => [for (final r in _sets.values) r.summary()];

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
    return record.summary();
  }

  @override
  Future<void> setStarred(String id, {required bool starred}) => _updateMeta(id, (r) => r.copyWith(starred: starred));

  @override
  Future<void> markOpened(String id) => _updateMeta(id, (r) => r.copyWith(lastOpenedAt: _clock()));

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
    await _persist(studySetId);
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
  String resolveFile(String studySetId, String fileName) => p.join(_packagePath(studySetId), fileName);

  // ---- internals -----------------------------------------------------------

  _SetRecord _require(String id) => _sets[id] ?? (throw StateError('Unknown study set: $id'));

  Stream<T> _watch<T>(Stream<Object?> changes, T Function() snapshot) {
    StreamSubscription<Object?>? sub;
    late final StreamController<T> out;
    out = StreamController<T>(
      onListen: () async {
        await _ensureLoaded();
        if (out.isClosed) return;
        out.add(snapshot());
        sub = changes.listen((_) => out.add(snapshot()));
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  /// Serializes writes per set; each write stores the latest in-memory state.
  Future<void> _persist(String id) {
    final previous = _writeQueue[id] ?? Future<void>.value();
    final next = previous.then((_) async {
      final record = _sets[id];
      if (record == null) return;
      final dir = Directory(_packagePath(id));
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, 'studyset.json'));
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(record.toJson()), flush: true);
      await tmp.rename(file.path);
    });
    _writeQueue[id] = next;
    return next;
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

  _SetRecord copyWith({bool? starred, DateTime? lastOpenedAt, StudySetContent? content}) => _SetRecord(
    id: id,
    title: title,
    colorIndex: colorIndex,
    folderId: folderId,
    starred: starred ?? this.starred,
    createdAt: createdAt,
    lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    content: content ?? this.content,
  );

  StudySet summary() {
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
      readPages: content.documents.isEmpty ? 0 : readPages,
      totalPages: totalPages,
      lastPosition: last == null ? null : ReadingPosition(documentTitle: last.title, page: last.lastPage),
      createdAt: createdAt,
      lastOpenedAt: lastOpenedAt,
    );
  }

  Map<String, Object?> toJson() => {
    'format': 1,
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
    content: StudySetContent.fromJson(((j['content'] as Map?) ?? const {}).cast()),
  );
}
