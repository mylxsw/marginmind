import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

/// Registers publisher fonts under document-specific aliases supplied by the
/// reader. Callers retain their fallback family if loading fails.
abstract final class MMBookFonts {
  static final _registry = BookFontRegistry((family, bytes) async {
    final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  });

  static Future<void> load(String family, Uint8List bytes) => _registry.load(family, bytes);
}

/// The engine retains registered fonts for the process lifetime. Deduplicate
/// both completed and concurrent loads across short-lived chapter sessions.
class BookFontRegistry {
  BookFontRegistry(this.register);
  final Future<void> Function(String, Uint8List) register;
  final _loads = <(String, String), Future<void>>{};

  Future<void> load(String family, Uint8List bytes) {
    if (family.trim().isEmpty || bytes.isEmpty || bytes.length > 16 * 1024 * 1024) {
      return Future.error(ArgumentError('Invalid book font'));
    }
    final key = (family, sha256.convert(bytes).toString());
    return _loads.putIfAbsent(key, () {
      final owned = Uint8List.fromList(bytes);
      return Future<void>(() async {
        try {
          await register(family, owned);
        } catch (_) {
          _loads.remove(key);
          rethrow;
        }
      });
    });
  }
}
