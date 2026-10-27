import 'dart:io';

import 'package:mm_core/mm_core.dart';
import 'package:mm_research/mm_research.dart';
import 'package:test/test.dart';

void main() {
  final endpoint = Uri.parse('http://search.lan:8080/search');
  final unsafe = throwsA(isA<ResearchFailure>().having((e) => e.kind, 'kind', ResearchFailureKind.unsafeUrl));

  test('private service exception permits only the configured origin and local address ranges', () async {
    for (final value in [
      '127.0.0.1',
      '10.1.2.3',
      '172.16.0.1',
      '192.168.1.2',
      '169.254.1.2',
      '::1',
      'fd00::1',
      'fe80::1',
    ]) {
      final address = InternetAddress(value);
      final policy = UrlPolicy(privateEndpoint: endpoint, lookup: (_) async => [address]);
      expect(await policy.validate(endpoint.resolve('/other?q=1')), [address]);
      for (final other in [
        'https://search.lan:8080/search',
        'http://other.lan:8080/search',
        'http://search.lan:8081/search',
      ]) {
        await expectLater(policy.validate(Uri.parse(other)), unsafe);
      }
      await expectLater(UrlPolicy(lookup: (_) async => [address]).validate(endpoint), unsafe);
      // Ollama's existing path-scoped loopback exception never enables LAN access.
      if (!address.isLoopback) {
        await expectLater(
          UrlPolicy(localEndpoint: endpoint, lookup: (_) async => [address]).validate(endpoint),
          unsafe,
        );
      }
    }
  });

  test('private origin still rejects unspecified, multicast, fake-IP and mixed unsafe DNS', () async {
    for (final value in ['0.0.0.0', '224.0.0.1', '198.18.0.1', 'ff02::1', '::']) {
      await expectLater(
        UrlPolicy(
          privateEndpoint: endpoint,
          lookup: (_) async => [InternetAddress('192.168.1.2'), InternetAddress(value)],
        ).validate(endpoint),
        unsafe,
      );
    }
    await expectLater(UrlPolicy(privateEndpoint: endpoint, lookup: (_) async => []).validate(endpoint), unsafe);
    expect(
      await UrlPolicy(privateEndpoint: endpoint, lookup: (_) async => [InternetAddress('8.8.8.8')]).validate(endpoint),
      hasLength(1),
    );
  });
}
