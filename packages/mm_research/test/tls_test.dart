import 'dart:convert';
import 'dart:io';

import 'package:mm_research/mm_research.dart';
import 'package:test/test.dart';

void main() {
  test('pinned HTTPS socket performs TLS and validates the original hostname', () async {
    final temp = await Directory.systemTemp.createTemp('mm-tls-test-');
    addTearDown(() => temp.delete(recursive: true));
    final certificate = '${temp.path}/certificate.pem';
    // Fresh short-lived self-signed certificate, no OS trust-store mutation.
    final generated = await Process.run('openssl', [
      'req',
      '-x509',
      '-key',
      'test/fixtures/tls-key.pem',
      '-out',
      certificate,
      '-days',
      '2',
      '-subj',
      '/CN=research.test',
      '-addext',
      'subjectAltName=DNS:research.test',
      '-addext',
      'basicConstraints=critical,CA:FALSE',
      '-addext',
      'keyUsage=critical,digitalSignature,keyEncipherment',
      '-addext',
      'extendedKeyUsage=serverAuth',
    ]);
    expect(generated.exitCode, 0, reason: '${generated.stderr}');
    final serverContext = SecurityContext()
      ..useCertificateChain(certificate)
      ..usePrivateKey('test/fixtures/tls-key.pem');
    final trust = SecurityContext(withTrustedRoots: false)..setTrustedCertificates(certificate);
    final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverContext);
    final requests = <String>[];
    final subscription = server.listen((request) {
      requests.add(request.headers.host!);
      request.response.write('TLS OK');
      request.response.close();
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });
    for (final hostname in ['research.test', 'wrong.test']) {
      final endpoint = Uri.parse('https://$hostname:${server.port}/');
      final client = UrlPolicy(
        localEndpoint: endpoint,
        lookup: (host) async {
          expect(host, hostname);
          return [InternetAddress.loopbackIPv4];
        },
      ).createClient(context: trust);
      try {
        if (hostname == 'research.test') {
          final response = await (await client.getUrl(endpoint)).close();
          expect(response.statusCode, 200);
          expect(await response.transform(utf8.decoder).join(), 'TLS OK');
          expect(requests, ['research.test']);
        } else {
          await expectLater(client.getUrl(endpoint), throwsA(isA<HandshakeException>()));
          expect(requests, ['research.test']);
        }
      } finally {
        client.close(force: true);
      }
    }
  });
}
