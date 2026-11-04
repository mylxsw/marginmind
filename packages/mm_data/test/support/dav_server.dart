import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/io_client.dart';
import 'package:mm_sync/mm_sync.dart';

/// A deliberately small DAV server over real loopback TLS sockets. It enforces
/// parent collections, authentication and conditional creation independently of
/// the client. It is a fault-injection fixture, not a vendor compatibility claim.
class DavServer {
  DavServer._(this.server) {
    server.listen((request) {
      late final Future<void> work;
      work = _serve(request)
          .catchError((Object error) {
            // The timeout/disconnection tests deliberately close response sockets.
            if (error is! SocketException && error is! HttpException) errors.add(error);
          })
          .whenComplete(() => _active.remove(work));
      _active.add(work);
    });
  }

  static const certificate = 'test/fixtures/dav_tls/certificate.pem';
  static const authorization = 'Basic dGVzdDpvbmx5'; // test:only, never a real account.
  final HttpServer server;
  final objects = <String, List<int>>{};
  final collections = <String>{};
  final requests = <({String method, String path})>[];
  final errors = <Object>[];
  final _active = <Future<void>>{};
  final _clients = <IOClient>[];
  final gates = <DavGate>[];
  Future<bool> Function(HttpRequest request, List<int> body)? intercept;
  bool absoluteHrefs = false;
  bool dropNextCommitReply = false;

  static Future<DavServer> start() async {
    final context = SecurityContext()
      ..useCertificateChain(certificate)
      ..usePrivateKey('test/fixtures/dav_tls/test-only-key.pem');
    return DavServer._(await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context));
  }

  Uri directory([String name = 'library space & 中文']) {
    final result = Uri(scheme: 'https', host: '127.0.0.1', port: server.port, path: '/$name/');
    collections.add(result.path);
    return result;
  }

  WebDavSyncTransport transport({
    String name = 'library space & 中文',
    String account = 'test',
    String credentials = authorization,
    Duration timeout = const Duration(seconds: 5),
    bool trust = true,
  }) {
    final context = SecurityContext(withTrustedRoots: false);
    if (trust) context.setTrustedCertificates(certificate);
    final client = IOClient(HttpClient(context: context)..findProxy = (_) => 'DIRECT');
    _clients.add(client);
    return WebDavSyncTransport(
      client: client,
      directory: directory(name),
      account: account,
      libraryId: 'lib',
      authorization: credentials,
      timeout: timeout,
    );
  }

  DavGate hold(bool Function(HttpRequest) matches) {
    final gate = DavGate(matches);
    gates.add(gate);
    return gate;
  }

  Future<void> _serve(HttpRequest request) async {
    final path = request.uri.path;
    requests.add((method: request.method, path: path));
    final body = await request.fold<List<int>>([], (bytes, chunk) => bytes..addAll(chunk));
    for (final gate in gates) {
      if (!gate.entered.isCompleted && gate.matches(request)) {
        gate.entered.complete();
        await gate.release.future;
      }
    }
    if (request.headers.value(HttpHeaders.authorizationHeader) != authorization) {
      request.response.headers.set(HttpHeaders.wwwAuthenticateHeader, 'Basic realm="test only"');
      await reply(request, 401);
      return;
    }
    if (await intercept?.call(request, body) == true) return;
    switch (request.method) {
      case 'MKCOL':
        final parent = path.substring(0, path.lastIndexOf('/', path.length - 2) + 1);
        final status = collections.contains(path)
            ? 405
            : !collections.contains(parent)
            ? 409
            : 201;
        if (status == 201) collections.add(path);
        await reply(request, status);
      case 'GET':
        final bytes = objects[path];
        await reply(request, bytes == null ? 404 : 200, bytes ?? []);
      case 'PUT':
        if (request.headers.value(HttpHeaders.ifNoneMatchHeader) != '*') {
          await reply(request, 428);
        } else if (objects.containsKey(path)) {
          await reply(request, 412);
        } else if (!collections.contains(path.substring(0, path.lastIndexOf('/') + 1))) {
          await reply(request, 409);
        } else {
          objects[path] = body;
          if (dropNextCommitReply && path.contains('/commits/')) {
            dropNextCommitReply = false;
            (await request.response.detachSocket(writeHeaders: false)).destroy();
          } else {
            await reply(request, 201);
          }
        }
      case 'PROPFIND':
        if (!collections.contains(path)) {
          await reply(request, 404);
          return;
        }
        if (request.headers.value('Depth') != '1' || !utf8.decode(body).contains('resourcetype')) {
          await reply(request, 400);
          return;
        }
        String response(String key, {bool collection = false}) {
          final href = absoluteHrefs ? '${request.requestedUri.origin}$key' : key;
          return '<D:response><D:href>${const HtmlEscape().convert(href)}</D:href>'
              '<D:propstat><D:prop><D:resourcetype>${collection ? '<D:collection/>' : ''}'
              '</D:resourcetype></D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>';
        }
        final children = objects.keys.where((p) => p.startsWith(path) && !p.substring(path.length).contains('/'));
        request.response.headers.contentType = ContentType('application', 'xml', charset: 'utf-8');
        await reply(
          request,
          207,
          utf8.encode(
            '<D:multistatus xmlns:D="DAV:">'
            '${response(path, collection: true)}${children.toList().reversed.map(response).join()}'
            '</D:multistatus>',
          ),
        );
      default:
        await reply(request, 405);
    }
  }

  static Future<void> reply(HttpRequest request, int status, [List<int> body = const []]) async {
    request.response.statusCode = status;
    request.response.add(body);
    await request.response.close();
  }

  Future<void> close() async {
    for (final gate in gates) {
      gate.open();
    }
    for (final client in _clients) {
      client.close();
    }
    await server.close(force: true);
    await Future.wait(_active.toList());
  }
}

class DavGate {
  DavGate(this.matches);
  final bool Function(HttpRequest) matches;
  final entered = Completer<void>(), release = Completer<void>();
  void open() {
    if (!release.isCompleted) release.complete();
  }
}
