import 'dart:convert';

import 'library_io.dart' if (dart.library.js_interop) 'library_browser_io.dart';

import 'package:path/path.dart' as p;
import 'package:mm_sync/mm_sync.dart';

/// Opt-in durable source for a sync-managed aggregate. Immutable commits are
/// written before any materialized view is published. Acknowledging transport
/// delivery never deletes history needed as a three-way merge base.
///
/// This store does not automatically upload anything or discover credentials.
/// All methods serialize on one instance; native callers must have one owner.
class FileSyncJournal {
  FileSyncJournal(this.root, {required this.libraryId, required this.scope});
  final Directory root;
  final String libraryId, scope;
  Future<void> _queue = Future.value();

  Directory get _directory => Directory(p.join(root.path, '.foliarc-sync', legacySyncDigest([libraryId, scope])));
  File _commitFile(String id) => File(p.join(_directory.path, '$id.json'));
  File get _acks => File(p.join(_directory.path, 'delivered.json'));

  Future<T> _serial<T>(Future<T> Function() run) {
    final next = _queue.then((_) => run());
    _queue = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<List<SyncCommit>> load() => _serial(_load);

  Future<List<SyncCommit>> _load() async {
    if (!await _directory.exists()) return const [];
    final commits = <SyncCommit>[];
    await for (final entry in _directory.list(followLinks: false)) {
      if (entry is! File || !RegExp(r'^[0-9a-f]{64}\.json$').hasMatch(p.basename(entry.path))) continue;
      final c = SyncCommit.fromJson((jsonDecode(await entry.readAsString()) as Map).cast());
      if (c.libraryId != libraryId || c.scope != scope || p.basename(entry.path) != '${c.id}.json') {
        throw const FormatException('Journal identity mismatch');
      }
      commits.add(c);
    }
    SyncGraph(commits);
    commits.sort((a, b) => a.id.compareTo(b.id));
    return List.unmodifiable(commits);
  }

  /// Retrying the exact commit is idempotent. A forked device sequence or a
  /// missing parent fails before writing. Unfinished .tmp files are ignored.
  Future<void> append(SyncCommit commit) => _serial(() async {
    if (commit.libraryId != libraryId || commit.scope != scope) throw const FormatException('Wrong journal');
    final all = await _load();
    if (all.any((c) => c.id == commit.id)) return;
    SyncGraph([...all, commit]);
    final own = all.where((c) => c.deviceId == commit.deviceId).toList();
    if (own.isNotEmpty) {
      own.sort((a, b) => b.sequence.compareTo(a.sequence));
      final graph = SyncGraph([...all, commit]);
      if (commit.sequence <= own.first.sequence || !graph.ancestors(commit.id).contains(own.first.id)) {
        throw const FormatException('Local device history must be monotonic');
      }
    }
    await _atomic(_commitFile(commit.id), jsonEncode(commit.toJson()));
  });

  /// An acknowledgement is only allowed after the transport confirms remote
  /// durability (not merely after staging a file in an iCloud container).
  Future<void> acknowledge(Iterable<String> ids) => _serial(() async {
    final requested = ids.toSet();
    final known = (await _load()).map((c) => c.id).toSet();
    if (!known.containsAll(requested)) throw const FormatException('Cannot acknowledge an unknown commit');
    final acked = await _readAcks()
      ..addAll(requested);
    await _atomic(_acks, jsonEncode({'version': 1, 'ids': acked.toList()..sort()}));
  });

  Future<List<SyncCommit>> pending() => _serial(() async {
    final commits = await _load(), acked = await _readAcks();
    return List.unmodifiable(commits.where((c) => !acked.contains(c.id)));
  });

  Future<Set<String>> _readAcks() async {
    if (!await _acks.exists()) return {};
    final json = jsonDecode(await _acks.readAsString()) as Map;
    if (json['version'] != 1 || json['ids'] is! List) throw const FormatException('Invalid journal acknowledgements');
    return (json['ids'] as List).cast<String>().toSet();
  }

  static Future<void> _atomic(File file, String text) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    try {
      await temp.writeAsBytes(utf8.encode(text), flush: true);
      await temp.rename(file.path);
    } catch (_) {
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {
        /* Preserve original failure. */
      }
      rethrow;
    }
  }
}
