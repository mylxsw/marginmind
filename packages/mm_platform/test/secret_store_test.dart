import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_platform/mm_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('marginmind/secret_store');
  const store = KeychainSecretStore();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test('isolates accounts, overwrites, deletes and returns missing as null', () async {
    final values = <String, String>{};
    messenger.setMockMethodCallHandler(channel, (call) async {
      final account = call.arguments['account'] as String;
      switch (call.method) {
        case 'write':
          values[account] = call.arguments['value'] as String;
        case 'delete':
          values.remove(account);
        case 'read':
          return values[account];
      }
      return null;
    });
    expect(await store.read('claude'), isNull);
    await store.write('claude', 'secret');
    await store.write('openai', 'other');
    await store.write('claude', 'updated');
    expect(await store.read('claude'), 'updated');
    await store.delete('claude');
    expect(await store.read('claude'), isNull);
    expect(await store.read('openai'), 'other');
  });
  test('validates account and never leaks platform error details', () async {
    await expectLater(store.read(''), throwsA(isA<ResearchFailure>()));
    messenger.setMockMethodCallHandler(channel, (_) => throw PlatformException(code: 'oops', message: 'SECRET'));
    try {
      await store.write('a', 'SECRET');
      fail('expected error');
    } catch (e) {
      expect(e.toString(), isNot(contains('SECRET')));
    }
    messenger.setMockMethodCallHandler(channel, null);
    await expectLater(store.read('a'), throwsA(isA<ResearchFailure>()));
  });
}
