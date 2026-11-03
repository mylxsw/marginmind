import 'dart:async';

import 'package:flutter/services.dart';
import 'package:mm_core/mm_core.dart';

import 'browser_policy.dart';
import 'capabilities.dart';
import 'document_files.dart';

/// Native receivers publish a manifest only after copying all attachments.
/// Reading the inbox never removes it: acknowledgement follows user dismissal
/// or the completed import, so a cold start cannot lose temporary file access.
class MMIncomingShareBatch {
  const MMIncomingShareBatch({required this.id, this.files = const [], this.url, this.title, this.error});

  final String id;
  final List<MMDocumentFile> files;
  final Uri? url;
  final String? title;
  final String? error;

  factory MMIncomingShareBatch.fromMap(Map<Object?, Object?> map) {
    final id = map['id'];
    if (id is! String || !RegExp(r'^[a-zA-Z0-9-]{1,80}$').hasMatch(id)) {
      throw const FormatException('Invalid share id');
    }
    final files = <MMDocumentFile>[];
    for (final raw in (map['files'] as List? ?? const [])) {
      final file = raw as Map;
      final name = file['name'] as String;
      final path = file['path'] as String;
      if (name.isEmpty ||
          RegExp(r'[/\\\x00-\x1f]').hasMatch(name) ||
          DocumentFormat.fromFileName(name) == DocumentFormat.unknown ||
          !path.startsWith('/') ||
          path.contains('\u0000')) {
        throw const FormatException('Invalid shared document');
      }
      files.add((path: path, name: name));
    }
    final url = map['url'] == null ? null : BrowserPolicy.normalize(map['url'] as String);
    final error = map['error'] as String?;
    if (files.length > 20 || (files.isEmpty && url == null && error == null)) {
      throw const FormatException('Empty or oversized share');
    }
    return MMIncomingShareBatch(
      id: id,
      files: List.unmodifiable(files),
      url: url,
      title: map['title'] as String?,
      error: error,
    );
  }
}

/// Explicit HTTP(S) links only; sharing prose must not turn it into a hostname.
/// Used by clipboard actions as well as the native receiver contract tests.
Uri? incomingShareUrl(String text) {
  final bounded = text.length > 65536 ? text.substring(0, 65536) : text;
  for (final match in RegExp(r'''https?://[^\s<>"\u0000-\u001f]+''', caseSensitive: false).allMatches(bounded)) {
    var candidate = match.group(0)!.replaceFirst(RegExp(r'[.,;!?，。；！？]+$'), '');
    for (final (open, close) in const [('(', ')'), ('[', ']'), ('{', '}'), ('（', '）'), ('【', '】'), ('《', '》')]) {
      var excess = close.allMatches(candidate).length - open.allMatches(candidate).length;
      var end = candidate.length;
      while (excess > 0 && end > 0 && candidate[end - 1] == close) {
        end--;
        excess--;
      }
      candidate = candidate.substring(0, end);
    }
    try {
      return BrowserPolicy.normalize(candidate);
    } on BrowserUrlException {
      // A later link in the same share may still be valid.
    }
  }
  return null;
}

abstract interface class MMIncomingShareSource {
  Stream<void> get changes;
  Future<List<MMIncomingShareBatch>> pending();
  Future<void> complete(String id);
  void dispose();
}

class MMIncomingShares implements MMIncomingShareSource {
  MMIncomingShares({bool? supported}) : _supported = supported ?? MMPlatformCapabilities.current.mobile {
    if (_supported) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'changed' && !_changes.isClosed) _changes.add(null);
        if (call.method == 'failed' && !_changes.isClosed) {
          _changes.addError(PlatformException(code: 'incoming_unavailable'));
        }
      });
    }
  }

  static const _channel = MethodChannel('marginmind/incoming_share');
  final bool _supported;
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<List<MMIncomingShareBatch>> pending() async {
    if (!_supported) return const [];
    List<Object?> entries;
    try {
      entries = await _channel.invokeListMethod<Object?>('pending') ?? const [];
    } on MissingPluginException {
      return const [];
    }
    final batches = <MMIncomingShareBatch>[];
    for (final entry in entries) {
      if (entry is! Map) continue;
      final id = entry['id'];
      if (id is! String || !RegExp(r'^[a-zA-Z0-9-]{1,80}$').hasMatch(id)) continue;
      try {
        batches.add(MMIncomingShareBatch.fromMap(entry.cast<Object?, Object?>()));
      } catch (_) {
        // One damaged manifest must not block subsequent valid shares.
        batches.add(MMIncomingShareBatch(id: id, error: 'unsupported'));
      }
    }
    return batches;
  }

  @override
  Future<void> complete(String id) async {
    if (_supported) await _channel.invokeMethod<void>('complete', {'id': id});
  }

  @override
  void dispose() {
    if (_supported) _channel.setMethodCallHandler(null);
    unawaited(_changes.close());
  }
}
