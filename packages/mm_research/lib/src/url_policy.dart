import 'dart:io';

import 'package:mm_core/mm_core.dart';

typedef AddressLookup = Future<List<InternetAddress>> Function(String host);

/// Web URLs and provider credentials never share the localhost exception.
class UrlPolicy {
  UrlPolicy({AddressLookup? lookup, this.localEndpoint, this.providerEndpoint})
    : lookup = lookup ?? InternetAddress.lookup;
  final AddressLookup lookup;
  final Uri? localEndpoint;

  /// Only an explicitly configured HTTPS provider may use a proxy fake-IP.
  /// Web/source URLs never receive this exception. TLS still verifies the host.
  final Uri? providerEndpoint;

  static bool publicAddress(InternetAddress address) {
    final b = address.rawAddress;
    if (b.length == 4) {
      return !(b[0] == 0 ||
          b[0] == 10 ||
          b[0] == 127 ||
          b[0] >= 224 ||
          (b[0] == 100 && b[1] >= 64 && b[1] <= 127) ||
          (b[0] == 169 && b[1] == 254) ||
          (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
          (b[0] == 192 && (b[1] == 168 || b[1] == 0 || (b[1] == 0 && b[2] == 2))) ||
          (b[0] == 198 && (b[1] == 18 || b[1] == 19 || b[1] == 51)) ||
          (b[0] == 203 && b[1] == 0 && b[2] == 113));
    }
    // Only global unicast; reject mapped IPv4, NAT64, ULA, link-local,
    // multicast, documentation, Teredo and 6to4 transition ranges.
    return b[0] >= 0x20 &&
        b[0] <= 0x3f &&
        !(b[0] == 0x20 && b[1] == 0x01 && (b[2] < 2 || (b[2] == 0x0d && b[3] == 0xb8))) &&
        !(b[0] == 0x20 && b[1] == 0x02);
  }

  static void syntax(Uri url) {
    if (!['http', 'https'].contains(url.scheme) ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        url.hasFragment ||
        url.host.contains('%')) {
      throw const ResearchFailure(ResearchFailureKind.unsafeUrl);
    }
  }

  Future<List<InternetAddress>> validate(Uri url) async {
    syntax(url);
    final host = url.host.replaceAll('[', '').replaceAll(']', '');
    final parsed = InternetAddress.tryParse(host);
    final addresses = parsed == null ? await lookup(host) : [parsed];
    final local = localEndpoint;
    final allowLoopback = local != null && url.origin == local.origin && url.path == local.path;
    final allowFake = providerEndpoint == url && url.scheme == 'https' && parsed == null;
    bool fake(InternetAddress a) =>
        a.rawAddress.length == 4 && a.rawAddress[0] == 198 && (a.rawAddress[1] == 18 || a.rawAddress[1] == 19);
    if (addresses.isEmpty ||
        addresses.any((a) => !publicAddress(a) && !(allowLoopback && a.isLoopback) && !(allowFake && fake(a)))) {
      throw const ResearchFailure(ResearchFailureKind.unsafeUrl);
    }
    return addresses;
  }

  HttpClient createClient({SecurityContext? context}) {
    final client = HttpClient(context: context)..findProxy = (_) => 'DIRECT';
    // Connect to the vetted numeric address, retaining the URI host for TLS/SNI.
    // This closes the DNS check/connect rebinding window.
    client.connectionFactory = (url, proxyHost, proxyPort) async {
      final addresses = await validate(url);
      final connection = await Socket.startConnect(addresses.first, url.port);
      if (url.scheme == 'http') return connection;
      Socket? connected;
      var cancelled = false;
      final secure = connection.socket.then((socket) async {
        connected = socket;
        if (cancelled) {
          socket.destroy();
          throw const SocketException('Connection cancelled');
        }
        try {
          final tls = await SecureSocket.secure(socket, host: url.host, context: context);
          connected = tls;
          if (cancelled) {
            tls.destroy();
            throw const SocketException('Connection cancelled');
          }
          return tls;
        } catch (_) {
          socket.destroy();
          rethrow;
        }
      });
      return ConnectionTask.fromSocket(secure, () {
        cancelled = true;
        connection.cancel();
        connected?.destroy();
      });
    };
    return client;
  }
}
