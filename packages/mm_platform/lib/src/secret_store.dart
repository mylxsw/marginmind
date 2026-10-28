import 'package:flutter/services.dart';
import 'package:mm_core/mm_core.dart';

class KeychainSecretStore implements SecretStore {
  const KeychainSecretStore({this._channel = const MethodChannel('marginmind/secret_store')});
  final MethodChannel _channel;
  Future<T?> _call<T>(String method, String account, [String? value]) async {
    if (account.isEmpty || account.length > 256) throw const ResearchFailure(ResearchFailureKind.invalidRequest);
    try {
      return await _channel.invokeMethod<T>(method, {'account': account, 'value': ?value});
    } on PlatformException catch (error) {
      if (error.code == 'keychain_auth_required') {
        throw const ResearchFailure(ResearchFailureKind.authentication, 'secret_store');
      }
      throw const ResearchFailure(ResearchFailureKind.unavailable, 'secret_store');
    } on MissingPluginException {
      throw const ResearchFailure(ResearchFailureKind.unsupported, 'secret_store');
    }
  }

  @override
  Future<String?> read(String account) => _call<String>('read', account);
  @override
  Future<void> write(String account, String value) => _call<void>('write', account, value);
  @override
  Future<void> delete(String account) => _call<void>('delete', account);
}
