import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:mm_core/mm_core.dart';

import 'commit.dart';
import 'device_reading.dart';

const syncResourceChunkSize = 4 * 1024 * 1024;
const syncResourceFileLimit = 1024 * 1024 * 1024;
String _parent(String path) => path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';
final _hash = RegExp(r'^[a-f0-9]{64}$');

/// Chunk boundaries are fixed by protocol; the whole-file hash prevents a
/// malicious manifest from reordering individually valid chunks.
class SyncResourceFile {
  SyncResourceFile({required this.hash, required this.length, required Iterable<String> chunks})
    : chunks = List.unmodifiable(chunks) {
    if (!_hash.hasMatch(hash) ||
        length < 0 ||
        length > syncResourceFileLimit ||
        this.chunks.length != (length / syncResourceChunkSize).ceil() ||
        this.chunks.any((h) => !_hash.hasMatch(h)) ||
        (length == 0 && hash != sha256.convert(const <int>[]).toString())) {
      throw const FormatException('Invalid resource descriptor');
    }
  }
  final String hash;
  final int length;
  final List<String> chunks;
  int chunkLength(int index) {
    RangeError.checkValidIndex(index, chunks);
    return math.min(syncResourceChunkSize, length - index * syncResourceChunkSize);
  }

  Map<String, Object?> toJson() => {'sha256': hash, 'length': length, 'chunks': chunks};
  factory SyncResourceFile.fromJson(Map<String, Object?> json) {
    if (json.keys.toSet().difference({'sha256', 'length', 'chunks'}).isNotEmpty) {
      throw const FormatException('Unsupported resource descriptor');
    }
    return SyncResourceFile(
      hash: json['sha256'] as String,
      length: json['length'] as int,
      chunks: (json['chunks'] as List).cast<String>(),
    );
  }
}

/// A content-derived capability to read package files. Neither a received path
/// nor a directory listing is permission to scan private repository data.
class SyncResourceGroup {
  SyncResourceGroup(this.key, Iterable<String> roots, {this.bookBase, this.webBase}) : roots = Set.unmodifiable(roots);
  final String key;
  final Set<String> roots;
  final String? bookBase, webBase;
  bool permits(String path) =>
      validSyncResourcePath(path) &&
      (roots.contains(path) ||
          (bookBase != null &&
              path.startsWith('$bookBase/') &&
              RegExp(r'^(chapters/[a-f0-9]{64}\.json|resources/[a-f0-9]{64}\.[a-z0-9]{1,8})$')
                  .hasMatch(path.substring(bookBase!.length + 1))) ||
          (webBase != null &&
              path.startsWith('$webBase/') &&
              RegExp(r'^(resources\.json|snapshot\.html|resources/[a-zA-Z0-9_-]+\.(png|jpg|gif|webp|svg))$')
                  .hasMatch(path.substring(webBase!.length + 1))));
}

bool validSyncResourcePath(String path) =>
    path.length <= 1024 &&
    RegExp(r'^(documents|books|web|images|research/snapshots)/[a-zA-Z0-9_./-]+$').hasMatch(path) &&
    !path.endsWith('.tmp') &&
    !path.split('/').any((p) => p.isEmpty || p == '.' || p == '..');

List<SyncResourceGroup> syncResourceGroups(StudySetContent content) => [
  for (final doc in content.documents)
    SyncResourceGroup(
      'document/${doc.id}/${readingDocumentVersion(doc)}',
      [
        doc.fileName,
        ?doc.sourceFileName,
        ?doc.contentManifest,
        ?doc.origin?.snapshotFile,
        if (doc.origin?.snapshotFile case final snapshot?) '${_parent(snapshot)}/resources.json',
      ],
      bookBase: doc.contentManifest == null ? null : _parent(doc.contentManifest!),
      webBase: doc.origin?.snapshotFile == null ? null : _parent(doc.origin!.snapshotFile!),
    ),
  for (final card in content.cards)
    if (card.imageFileName case final path?) SyncResourceGroup('image/${card.id}/${syncDigest(path)}', [path]),
  for (final source in content.researchSources)
    for (final version in source.versions)
      SyncResourceGroup('research/${source.id}/${syncDigest(version.snapshotFile)}', [version.snapshotFile]),
];

/// Optional field on a shared set. Old content remains readable but has no
/// verified resources until a device owning the files publishes this field.
class SyncResources {
  SyncResources(Map<String, Map<String, SyncResourceFile>> groups)
    : groups = Map.unmodifiable(groups.map((k, v) => MapEntry(k, Map<String, SyncResourceFile>.unmodifiable(v))));
  final Map<String, Map<String, SyncResourceFile>> groups;
  Map<String, Object?> toJson() => {
    'version': 1,
    'groups': {
      for (final group in groups.entries)
        group.key: {for (final file in group.value.entries) file.key: file.value.toJson()},
    },
  };
  factory SyncResources.fromJson(Map<String, Object?> value) {
    if (value['version'] != 1 || value.keys.any((k) => !{'version', 'groups'}.contains(k))) {
      throw const FormatException('Unsupported resource manifest');
    }
    value = (value['groups'] as Map).cast<String, Object?>();
    if (value.length > 10000) throw const FormatException('Too many resource groups');
    var count = 0;
    final groups = <String, Map<String, SyncResourceFile>>{};
    for (final entry in value.entries) {
      final files = (entry.value as Map).cast<String, Object?>();
      count += files.length;
      if (count > 10000) throw const FormatException('Too many resource files');
      groups[entry.key] = {
        for (final file in files.entries)
          file.key: SyncResourceFile.fromJson((file.value as Map).cast<String, Object?>()),
      };
    }
    return SyncResources(groups);
  }
  void validate(StudySetContent content) {
    SyncResources.fromJson(toJson()); // Apply the same count limits before local publication.
    final allowed = {for (final group in syncResourceGroups(content)) group.key: group};
    final paths = <String, Map<String, Object?>>{};
    for (final group in groups.entries) {
      final capability = allowed[group.key];
      if (capability == null ||
          !group.value.keys.toSet().containsAll(capability.roots) ||
          group.value.keys.any((p) => !capability.permits(p))) {
        throw const FormatException('Resource outside referenced content');
      }
      for (final file in group.value.entries) {
        if (paths.containsKey(file.key) && !contentValueEquals(paths[file.key], file.value.toJson())) {
          throw const FormatException('Ambiguous resource path');
        }
        paths[file.key] = file.value.toJson();
      }
    }
  }

  SyncResources retain(StudySetContent content) {
    final keys = syncResourceGroups(content).map((g) => g.key).toSet();
    return SyncResources({
      for (final e in groups.entries)
        if (keys.contains(e.key)) e.key: e.value,
    });
  }
}

/// References are interpreted only for the two recognized package manifests.
/// Their declared digests must agree with the transferred bytes as well.
Map<String, String> syncResourceDependencies(SyncResourceGroup group, String path, Map<String, Object?> data) {
  final result = <String, String>{};
  void add(String path, String hash) {
    if (!group.permits(path) || !_hash.hasMatch(hash) || (result[path] != null && result[path] != hash)) {
      throw const FormatException('Invalid resource dependency');
    }
    result[path] = hash;
  }

  if (path == '${group.webBase}/resources.json') {
    for (final entry in (data['resources'] as Map).entries) {
      add('${group.webBase}/${entry.key}', entry.value as String);
    }
    add('${group.webBase}/snapshot.html', data['snapshotSha256'] as String);
  } else if (path == '${group.bookBase}/manifest.json') {
    for (final section in ['spine', 'resources']) {
      for (final item in (data[section] as List? ?? const [])) {
        add((item as Map)['path'] as String, item['sha256'] as String);
      }
    }
  } else {
    throw const FormatException('Unknown resource manifest');
  }
  return result;
}
