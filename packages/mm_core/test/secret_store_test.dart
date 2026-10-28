import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

class Secrets implements SecretStore {
  String? value;
  bool unreadable = false;
  bool wrongValue = false;
  @override
  Future<void> write(String account, String value) async => this.value = value;
  @override
  Future<String?> read(String account) async {
    if (unreadable) throw const ResearchFailure(ResearchFailureKind.authentication, 'secret_store');
    return wrongValue ? 'stale' : value;
  }

  @override
  Future<void> delete(String account) async => value = null;
}

void main() {
  test('verified writes reject unreadable or stale values and permit retry', () async {
    final store = Secrets()..unreadable = true;
    await expectLater(store.writeVerified('account', 'test-key'), throwsA(isA<ResearchFailure>()));
    store
      ..unreadable = false
      ..wrongValue = true;
    await expectLater(store.writeVerified('account', 'test-key'), throwsA(isA<ResearchFailure>()));
    store.wrongValue = false;
    await store.writeVerified('account', 'test-key');
    expect(await store.read('account'), 'test-key');
  });
}
