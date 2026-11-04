import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'commit.dart';
import 'network_error_stub.dart' if (dart.library.io) 'network_error_io.dart';
import 'transport.dart';

/// WebDAV immutable object store. The configured directory must already exist.
/// Auth is captured per instance; redirects never receive these credentials.
class WebDavSyncTransport implements SyncObjectTransport {
  WebDavSyncTransport({
    required this.client,
    required Uri directory,
    required String account,
    required String libraryId,
    // Keep a named public credential input without exposing it on the adapter.
    required this._authorization,
    this.timeout = const Duration(seconds: 30),
  }) : directory = _directory(directory),
       target = SyncTarget(
         service: 'webdav',
         account: account,
         location: _directory(directory).toString(),
         libraryId: libraryId,
       );
  final http.Client client;
  final Uri directory;
  final String _authorization;
  final Duration timeout;
  @override
  final SyncTarget target;
  static Uri _directory(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.pathSegments.any((s) => s == '.' || s == '..' || s.contains('\\') || s.contains('/'))) {
      throw ArgumentError('WebDAV requires an HTTPS directory without embedded credentials');
    }
    return uri.replace(path: uri.path.endsWith('/') ? uri.path : '${uri.path}/');
  }

  Uri get _root => directory.resolve('foliarc-v2/${syncDigest(target.libraryId)}/');
  Future<(int, List<int>)> _request(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    List<int>? bytes,
  }) async {
    final abort = Completer<void>();
    try {
      final request = http.AbortableRequest(method, uri, abortTrigger: abort.future)..followRedirects = false;
      request.headers.addAll({'Authorization': _authorization, ...headers});
      if (bytes != null) request.bodyBytes = bytes;
      return await (() async {
        final response = await client.send(request);
        final body = <int>[];
        await for (final chunk in response.stream) {
          if (body.length + chunk.length > syncObjectLimit) {
            throw const SyncTransportException(SyncTransportProblem.tooLarge);
          }
          body.addAll(chunk);
        }
        switch (response.statusCode) {
          case 401:
            throw const SyncTransportException(SyncTransportProblem.authentication);
          case 403:
            throw const SyncTransportException(SyncTransportProblem.permission);
          case 507:
            throw const SyncTransportException(SyncTransportProblem.quota);
          case 429:
            throw const SyncTransportException(SyncTransportProblem.throttled);
        }
        if (response.statusCode >= 500 || response.statusCode == 423) {
          throw const SyncTransportException(SyncTransportProblem.unavailable);
        }
        if (response.statusCode >= 300 && response.statusCode < 400) {
          throw const SyncTransportException(SyncTransportProblem.invalidResponse);
        }
        return (response.statusCode, body);
      })().timeout(timeout);
    } on SyncTransportException {
      rethrow;
    } on TimeoutException {
      throw const SyncTransportException(SyncTransportProblem.unavailable);
    } on http.ClientException {
      throw const SyncTransportException(SyncTransportProblem.unavailable);
    } catch (error) {
      // IOClient does not wrap TLS handshake failures. Keep the same bounded,
      // credential-free failure contract for socket/stream errors as for HTTP
      // client errors, without importing dart:io into browser builds.
      if (isNativeNetworkError(error)) {
        throw const SyncTransportException(SyncTransportProblem.unavailable);
      }
      rethrow;
    } finally {
      // IOClient/BrowserClient cancel a timed-out request instead of leaving it
      // running with captured credentials after this operation has failed.
      if (!abort.isCompleted) abort.complete();
    }
  }

  @override
  Future<void> prepare() async {
    for (final uri in [directory.resolve('foliarc-v2/'), _root, _root.resolve('commits/'), _root.resolve('blobs/')]) {
      final r = await _request('MKCOL', uri);
      if (r.$1 != 201 && r.$1 != 405) throw const SyncTransportException(SyncTransportProblem.invalidResponse);
    }
  }

  @override
  Future<List<int>?> read(String key) async {
    checkSyncObjectKey(key);
    final r = await _request('GET', _root.resolve(key));
    if (r.$1 == 404) return null;
    if (r.$1 != 200) throw const SyncTransportException(SyncTransportProblem.invalidResponse);
    checkSyncObjectData(key, r.$2);
    return r.$2;
  }

  @override
  Future<SyncDelivery> create(String key, List<int> value) async {
    checkSyncObjectKey(key);
    checkSyncObjectData(key, value);
    final bytes = List<int>.unmodifiable(value);
    final existing = await read(key);
    if (existing != null) {
      if (!sameSyncStoredObject(key, existing, bytes)) {
        throw const SyncTransportException(SyncTransportProblem.collision);
      }
      return SyncDelivery.confirmed;
    }
    final r = await _request(
      'PUT',
      _root.resolve(key),
      headers: {
        'If-None-Match': '*',
        'Content-Type': key.startsWith('blobs/') ? 'application/octet-stream' : 'application/json',
      },
      bytes: bytes,
    );
    if (![200, 201, 204, 412].contains(r.$1)) throw const SyncTransportException(SyncTransportProblem.invalidResponse);
    final stored = await read(key);
    if (stored == null || !sameSyncStoredObject(key, stored, bytes)) {
      throw const SyncTransportException(SyncTransportProblem.collision);
    }
    return SyncDelivery.confirmed;
  }

  @override
  Future<List<String>> listCommits() async {
    final folder = _root.resolve('commits/');
    final r = await _request(
      'PROPFIND',
      folder,
      headers: {'Depth': '1', 'Content-Type': 'application/xml'},
      bytes: utf8.encode(
        '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/></d:prop></d:propfind>',
      ),
    );
    if (r.$1 != 207) throw const SyncTransportException(SyncTransportProblem.invalidResponse);
    try {
      final text = utf8.decode(r.$2);
      if (text.contains('<!DOCTYPE')) throw const FormatException('DTD');
      final doc = XmlDocument.parse(text);
      if (doc.rootElement.name.local != 'multistatus' || doc.rootElement.namespaceUri != 'DAV:') {
        throw const FormatException('DAV');
      }
      final ids = <String>{};
      final prefix = folder.pathSegments.toList()..removeLast(); // Directory's trailing slash.
      for (final response in doc.rootElement.findElements('response', namespaceUri: 'DAV:')) {
        final href = response.getElement('href', namespaceUri: 'DAV:')?.innerText;
        if (href == null) throw const FormatException('Missing href');
        final reference = Uri.parse(href);
        if (reference.pathSegments.any((s) => s == '.' || s == '..' || s.contains('/') || s.contains('\\'))) {
          throw const FormatException('Invalid href path');
        }
        final uri = folder.resolveUri(reference);
        final segments = uri.pathSegments;
        if (uri.origin != folder.origin ||
            uri.userInfo.isNotEmpty ||
            uri.hasQuery ||
            uri.hasFragment ||
            segments.length <= prefix.length ||
            Iterable<int>.generate(prefix.length).any((i) => segments[i] != prefix[i])) {
          throw const FormatException('Foreign href');
        }
        // DAV servers may percent-encode characters (e.g. '&') that Dart leaves
        // literal. Compare decoded segments, never decoded whole paths: an
        // encoded slash must not turn into a directory boundary.
        if (segments.length != prefix.length + 1) continue;
        final relative = segments.last;
        if (relative.isEmpty) continue;
        if (!RegExp(r'^[a-f0-9]{64}\.json$').hasMatch(relative)) continue;
        final statuses = response.findAllElements('status', namespaceUri: 'DAV:').map((e) => e.innerText.split(' '));
        if (!statuses.any((s) => s.length >= 2 && s[1] == '200')) throw const FormatException('Unavailable child');
        ids.add(relative.substring(0, 64));
        if (ids.length > 100000) throw const SyncTransportException(SyncTransportProblem.tooLarge);
      }
      return ids.toList()..sort();
    } on SyncTransportException {
      rethrow;
    } catch (_) {
      throw const SyncTransportException(SyncTransportProblem.invalidResponse);
    }
  }
}
