import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/voice/voice_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mm_core/mm_core.dart';

import 'assistant_support.dart' show FakeSecrets, UnreadableAfterWriteSecrets;

class LockedSecrets extends FakeSecrets {
  @override
  Future<void> write(String name, String value) async => throw StateError('Keychain locked');
}

void main() {
  test('switching providers preserves each configuration and stores only keys in Keychain', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secrets = FakeSecrets();
    final scope = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        assistantSecretsProvider.overrideWithValue(secrets),
      ],
    );
    addTearDown(scope.dispose);
    await scope
        .read(voiceSettingsProvider.notifier)
        .save(const VoiceSettings(provider: VoiceProvider.doubao, appId: 'appid'), 'doubao-secret');
    await scope
        .read(voiceSettingsProvider.notifier)
        .save(const VoiceSettings(provider: VoiceProvider.aliyun, model: 'fun-asr-realtime'), 'aliyun-secret');
    final saved = scope.read(voiceSettingsProvider);
    expect(saved.provider, VoiceProvider.aliyun);
    expect(saved.appId, 'appid');
    expect(saved.model, 'fun-asr-realtime');
    expect(await voiceKey(secrets, saved), 'aliyun-secret');
    expect(secrets.values[VoiceSettings.account(VoiceProvider.doubao)], 'doubao-secret');
    expect(prefs.getKeys().where((k) => '${prefs.get(k)}'.contains('secret')), isEmpty);
    await scope.read(voiceSettingsProvider.notifier).save(const VoiceSettings(), '');
    expect(scope.read(voiceSettingsProvider).provider, VoiceProvider.none);
    expect(scope.read(voiceSettingsProvider).model, 'fun-asr-realtime');
  });

  test('failed Keychain writes do not enable an unconfigured service', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final scope = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        assistantSecretsProvider.overrideWithValue(LockedSecrets()),
      ],
    );
    addTearDown(scope.dispose);
    await expectLater(
      scope.read(voiceSettingsProvider.notifier).save(const VoiceSettings(provider: VoiceProvider.aliyun), 'key'),
      throwsStateError,
    );
    expect(scope.read(voiceSettingsProvider).provider, VoiceProvider.none);
    expect(prefs.getString('voice.provider'), null);
  });

  test('a successful write with an unreadable key does not enable voice input', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final scope = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        assistantSecretsProvider.overrideWithValue(UnreadableAfterWriteSecrets()),
      ],
    );
    addTearDown(scope.dispose);
    await expectLater(
      scope.read(voiceSettingsProvider.notifier).save(const VoiceSettings(provider: VoiceProvider.aliyun), 'key'),
      throwsA(isA<ResearchFailure>()),
    );
    expect(scope.read(voiceSettingsProvider).provider, VoiceProvider.none);
    expect(prefs.getString('voice.provider'), isNull);
  });

  test('rejects plaintext endpoints, unsupported models and incorrect Doubao version', () {
    expect(const VoiceSettings(provider: VoiceProvider.aliyun, endpoint: 'ws://example.com').valid, false);
    expect(const VoiceSettings(provider: VoiceProvider.aliyun, model: 'qwen3-asr-flash-realtime').valid, false);
    expect(
      const VoiceSettings(provider: VoiceProvider.doubao, appId: 'app', resourceId: 'volc.bigasr.sauc.duration').valid,
      false,
    );
  });
}
