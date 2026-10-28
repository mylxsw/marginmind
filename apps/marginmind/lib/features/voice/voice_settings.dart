import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';

import '../../app/providers.dart';
import '../assistant/assistant_settings.dart';

enum VoiceProvider { none, doubao, aliyun }

class VoiceSettings {
  const VoiceSettings({
    this.provider = VoiceProvider.none,
    this.appId = '',
    this.doubaoApiKey = false,
    this.resourceId = 'volc.seedasr.sauc.duration',
    this.model = 'paraformer-realtime-v2',
    this.endpoint = 'wss://dashscope.aliyuncs.com/api-ws/v1/inference',
  });

  final VoiceProvider provider;
  final String appId, resourceId, model, endpoint;
  final bool doubaoApiKey;

  static String account(VoiceProvider provider) => 'voice.${provider.name}.key';

  bool get valid {
    final uri = Uri.tryParse(endpoint);
    return switch (provider) {
      VoiceProvider.none => true,
      VoiceProvider.doubao =>
        (doubaoApiKey || appId.trim().isNotEmpty) &&
            const ['volc.seedasr.sauc.duration', 'volc.seedasr.sauc.concurrent'].contains(resourceId),
      VoiceProvider.aliyun =>
        const ['paraformer-realtime-v2', 'fun-asr-realtime'].contains(model) &&
            uri != null &&
            uri.scheme == 'wss' &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty,
    };
  }
}

final voiceSettingsProvider = NotifierProvider<VoiceSettingsController, VoiceSettings>(VoiceSettingsController.new);

class VoiceSettingsController extends Notifier<VoiceSettings> {
  @override
  VoiceSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return VoiceSettings(
      provider:
          VoiceProvider.values.where((v) => v.name == prefs.getString('voice.provider')).firstOrNull ??
          VoiceProvider.none,
      appId: prefs.getString('voice.doubao.appId') ?? '',
      doubaoApiKey: prefs.getBool('voice.doubao.apiKey') ?? false,
      resourceId: prefs.getString('voice.doubao.resourceId') ?? 'volc.seedasr.sauc.duration',
      model: prefs.getString('voice.aliyun.model') ?? 'paraformer-realtime-v2',
      endpoint: prefs.getString('voice.aliyun.endpoint') ?? 'wss://dashscope.aliyuncs.com/api-ws/v1/inference',
    );
  }

  /// Write credentials before publishing the selected service. Failed Keychain
  /// writes must never leave an apparently configured service in the composer.
  Future<void> save(VoiceSettings value, String key) async {
    if (!value.valid || (value.provider != VoiceProvider.none && key.trim().isEmpty)) {
      throw const FormatException('voice configuration');
    }
    if (value.provider != VoiceProvider.none) {
      await ref.read(assistantSecretsProvider).writeVerified(VoiceSettings.account(value.provider), key.trim());
    }
    final prefs = ref.read(sharedPreferencesProvider);
    if (value.provider == VoiceProvider.doubao) {
      await prefs.setString('voice.doubao.appId', value.appId.trim());
      await prefs.setBool('voice.doubao.apiKey', value.doubaoApiKey);
      await prefs.setString('voice.doubao.resourceId', value.resourceId);
    }
    if (value.provider == VoiceProvider.aliyun) {
      await prefs.setString('voice.aliyun.model', value.model);
      await prefs.setString('voice.aliyun.endpoint', value.endpoint.trim());
    }
    await prefs.setString('voice.provider', value.provider.name);
    ref.invalidateSelf();
  }
}

Future<String> voiceKey(SecretStore secrets, VoiceSettings settings) async =>
    (await secrets.read(VoiceSettings.account(settings.provider)))?.trim() ?? '';
