import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:mm_core/mm_core.dart';
import 'package:path/path.dart' as p;

/// One live execution owner per workflow, across containers, isolates and
/// processes. A prepared nonempty directory is published by atomic rename.
/// Unlike advisory FileLock, ownership also excludes isolates in one process.
/// No timeout can steal a slow or paused paid request from a live process.
class MapTaskLease {
  MapTaskLease._(this.directory, this.token);
  final Directory directory;
  final String token;

  static Future<void> _noLink(String path) async {
    if (await FileSystemEntity.type(path, followLinks: false) == FileSystemEntityType.link) {
      throw const FileSystemException('Map ownership refuses symbolic links');
    }
  }

  static Future<MapTaskLease> acquire(String journalDirectory, String id) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id)) throw const FormatException('Invalid map session');
    final owners = Directory(p.join(journalDirectory, 'owners'));
    await _noLink(owners.path);
    await owners.create();
    final target = Directory(p.join(owners.path, id));
    await _noLink(target.path);
    final prepared = await owners.createTemp('.claim-');
    final random = Random.secure();
    final token = '.claim-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    try {
      await File(p.join(prepared.path, '$token.json')).writeAsString(jsonEncode({'pid': pid}), flush: true);
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          await prepared.rename(target.path);
          return MapTaskLease._(target, token);
        } on FileSystemException {
          if (!await target.exists()) {
            if (attempt == 2) rethrow;
            continue; // The owner may have just released the destination.
          }
        }
        final List<FileSystemEntity> entries;
        try {
          entries = await target.list(followLinks: false).toList();
        } on FileSystemException {
          if (!await target.exists()) continue;
          rethrow;
        }
        if (entries.isEmpty) {
          // A process can exit between deleting its owner file and the empty
          // directory. Nonrecursive delete cannot remove a newly claimed owner.
          try {
            await target.delete();
          } on FileSystemException {
            /* Lost race. */
          }
          continue;
        }
        if (entries.length != 1 || entries.single is! File) throw const ConfigurationFailure('mapTaskActive');
        final owner = entries.single as File;
        final name = p.basename(owner.path);
        if (!RegExp(r'^\.claim-[a-zA-Z0-9]+\.json$').hasMatch(name)) {
          throw const ConfigurationFailure('mapTaskActive');
        }
        final Map data;
        try {
          data = jsonDecode(await owner.readAsString()) as Map;
        } on FileSystemException {
          if (!await owner.exists()) continue;
          rethrow;
        }
        final ownerPid = data['pid'];
        if (ownerPid is! int || ownerPid <= 0 || await _isAlive(ownerPid)) {
          throw const ConfigurationFailure('mapTaskActive');
        }
        // Reclaim only the immutable, dead owner's exact token. Another
        // claimant may already have replaced the directory; never delete its
        // owner file or recursively remove the directory (ABA protection).
        try {
          await owner.delete();
        } on FileSystemException {
          throw const ConfigurationFailure('mapTaskActive');
        }
        try {
          await target.delete();
        } on FileSystemException {
          /* New owner won. */
        }
      }
      throw const ConfigurationFailure('mapTaskActive');
    } finally {
      if (await prepared.exists()) await prepared.delete(recursive: true);
    }
  }

  static Future<bool> _isAlive(int ownerPid) async {
    if (ownerPid == pid) return true;
    try {
      if (Platform.isWindows) {
        final result = await Process.run('tasklist', ['/FI', 'PID eq $ownerPid', '/FO', 'CSV', '/NH']);
        if (result.exitCode != 0) return true;
        return const LineSplitter().convert(result.stdout.toString()).any((line) {
          final fields = line.split(',');
          return fields.length > 1 && fields[1].replaceAll('"', '').trim() == '$ownerPid';
        });
      }
      // Signal 0 only probes existence/permission; it sends no signal. Unknown
      // or permission-denied liveness fails closed, including PID reuse.
      final result = await Process.run('/bin/kill', ['-0', '$ownerPid'], environment: {'LC_ALL': 'C'});
      return result.exitCode == 0 || !result.stderr.toString().contains('No such process');
    } on ProcessException {
      return true;
    }
  }

  Future<void> release() async {
    final owner = File(p.join(directory.path, '$token.json'));
    await _noLink(directory.path);
    await _noLink(owner.path);
    await owner.delete();
    try {
      await directory.delete();
    } on FileSystemException {
      /* Never delete a replacement owner. */
    }
  }
}
