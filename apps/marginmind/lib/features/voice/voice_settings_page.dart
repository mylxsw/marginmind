import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';

import '../../settings/settings_window.dart' show SettingsPage;
import '../../shared/l10n.dart';
import '../assistant/assistant_settings.dart';
import 'voice_session.dart';
import 'voice_settings.dart';

typedef VoiceConnectionTest = Future<void> Function(VoiceSettings settings, String key);
final voiceConnectionTestProvider = Provider<VoiceConnectionTest>(
  (ref) => (settings, key) async {
    Object? failure;
    final session = RealtimeVoiceSession(settings, key, (_) {}, (error) => failure = error);
    try {
      await session.start();
      session.addAudio(Uint8List(3200)); // Silence only; testing never opens the microphone.
      await session.finish();
      if (failure != null) throw failure!;
    } finally {
      await session.cancel();
    }
  },
);

class VoiceSettingsPage extends ConsumerStatefulWidget {
  const VoiceSettingsPage({super.key});
  @override
  ConsumerState<VoiceSettingsPage> createState() => _VoiceSettingsPageState();
}

class _VoiceSettingsPageState extends ConsumerState<VoiceSettingsPage> {
  final _appId = TextEditingController(), _key = TextEditingController(), _endpoint = TextEditingController();
  late VoiceProvider _provider;
  late bool _apiKey;
  late String _resource, _model;
  bool _busy = false, _loading = false;
  String? _status;
  bool _failed = false;
  int _load = 0;

  @override
  void initState() {
    super.initState();
    final s = ref.read(voiceSettingsProvider);
    _provider = s.provider;
    _apiKey = s.doubaoApiKey;
    _resource = s.resourceId;
    _model = s.model;
    _appId.text = s.appId;
    _endpoint.text = s.endpoint;
    unawaited(_loadKey());
  }

  @override
  void dispose() {
    _appId.dispose();
    _key.dispose();
    _endpoint.dispose();
    super.dispose();
  }

  Future<void> _loadKey() async {
    final load = ++_load;
    _key.clear();
    if (_provider == VoiceProvider.none) return;
    _loading = true;
    try {
      final key = await ref.read(assistantSecretsProvider).read(VoiceSettings.account(_provider));
      if (!mounted || load != _load) return;
      _key.text = key ?? '';
    } catch (_) {
      if (mounted && load == _load) {
        _status = context.l10n.voiceKeyError;
        _failed = true;
      }
    } finally {
      if (mounted && load == _load) setState(() => _loading = false);
    }
  }

  VoiceSettings get _draft => VoiceSettings(
    provider: _provider,
    appId: _appId.text.trim(),
    doubaoApiKey: _apiKey,
    resourceId: _resource,
    model: _model,
    endpoint: _endpoint.text.trim(),
  );

  void _changed([String? _]) => setState(() => _status = null);

  Future<void> _perform({bool test = false}) async {
    final l = context.l10n;
    final settings = _draft, key = _key.text.trim();
    if (!settings.valid || (settings.provider != VoiceProvider.none && key.isEmpty)) {
      setState(() {
        _status = l.voiceConfigurationError;
        _failed = true;
      });
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      if (test) {
        await ref.read(voiceConnectionTestProvider)(settings, key);
      } else {
        await ref.read(voiceSettingsProvider.notifier).save(settings, key);
      }
      if (mounted) {
        setState(() {
          _failed = false;
          _status = test ? l.voiceTestPassed : l.voiceSaved;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _status = test ? l.voiceConnectionError : l.voiceSaveError;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n, c = context.mmColors;
    final enabled = !_busy && !_loading;
    Widget input(String label, TextEditingController controller, String id, {bool secret = false}) => MMSettingsRow(
      label: label,
      trailing: SizedBox(
        width: 245,
        child: TextField(
          key: ValueKey(id),
          controller: controller,
          enabled: enabled,
          obscureText: secret,
          autocorrect: false,
          enableSuggestions: false,
          style: context.mmText.body,
          onChanged: _changed,
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            hintText: secret ? l.voiceKeyPlaceholder : null,
          ),
        ),
      ),
    );
    return SettingsPage(
      key: const ValueKey('settings-voice'),
      children: [
        const SizedBox(height: MMSpacing.s),
        MMSettingsGroup(
          children: [
            MMSettingsRow(
              label: l.voiceService,
              trailing: MMPopUpButton<VoiceProvider>(
                key: const ValueKey('voice-provider'),
                value: _provider,
                semanticLabel: l.voiceService,
                items: [
                  (VoiceProvider.none, l.voiceDisabled),
                  (VoiceProvider.doubao, l.voiceDoubao),
                  (VoiceProvider.aliyun, l.voiceAliyun),
                ],
                onChanged: !enabled
                    ? null
                    : (value) {
                        setState(() {
                          _provider = value;
                          _status = null;
                        });
                        unawaited(_loadKey());
                      },
              ),
            ),
            if (_provider == VoiceProvider.doubao) ...[
              MMSettingsRow(
                label: l.voiceAuthentication,
                trailing: MMPopUpButton<bool>(
                  value: _apiKey,
                  semanticLabel: l.voiceAuthentication,
                  items: [(false, 'App ID + Access Token'), (true, 'API Key')],
                  onChanged: !enabled
                      ? null
                      : (value) => setState(() {
                          _apiKey = value;
                          _key.clear();
                          _status = null;
                        }),
                ),
              ),
              if (!_apiKey) input('App ID', _appId, 'voice-app-id'),
              input(_apiKey ? 'API Key' : 'Access Token', _key, 'voice-key', secret: true),
              MMSettingsRow(
                label: l.voiceResource,
                trailing: MMPopUpButton<String>(
                  value: _resource,
                  semanticLabel: l.voiceResource,
                  items: [
                    ('volc.seedasr.sauc.duration', l.voiceDuration),
                    ('volc.seedasr.sauc.concurrent', l.voiceConcurrent),
                  ],
                  onChanged: !enabled
                      ? null
                      : (value) => setState(() {
                          _resource = value;
                          _status = null;
                        }),
                ),
              ),
            ],
            if (_provider == VoiceProvider.aliyun) ...[
              input('API Key', _key, 'voice-key', secret: true),
              MMSettingsRow(
                label: l.assistantModel,
                trailing: MMPopUpButton<String>(
                  value: _model,
                  semanticLabel: l.assistantModel,
                  items: const [
                    ('paraformer-realtime-v2', 'Paraformer Realtime v2'),
                    ('fun-asr-realtime', 'Fun-ASR Realtime'),
                  ],
                  onChanged: !enabled
                      ? null
                      : (value) => setState(() {
                          _model = value;
                          _status = null;
                        }),
                ),
              ),
              input(l.settingsAddress, _endpoint, 'voice-endpoint'),
            ],
          ],
        ),
        const SizedBox(height: MMSpacing.m),
        if (_provider != VoiceProvider.none)
          Text(l.voicePrivacy, style: context.mmText.footnote.copyWith(color: c.secondaryLabel)),
        const SizedBox(height: MMSpacing.m),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (_busy || _loading) ...[const CupertinoActivityIndicator(radius: 6), const SizedBox(width: MMSpacing.m)],
            if (_provider != VoiceProvider.none) ...[
              MMButton(
                key: const ValueKey('voice-test'),
                label: l.voiceTest,
                onPressed: enabled ? () => unawaited(_perform(test: true)) : null,
              ),
              const SizedBox(width: MMSpacing.s),
            ],
            MMButton(
              key: const ValueKey('voice-save'),
              label: l.voiceSave,
              variant: MMButtonVariant.primary,
              onPressed: enabled ? () => unawaited(_perform()) : null,
            ),
          ],
        ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: MMSpacing.s),
            child: Text(
              _status!,
              key: const ValueKey('voice-settings-status'),
              style: context.mmText.footnote.copyWith(color: _failed ? c.critical : c.secondaryLabel),
            ),
          ),
      ],
    );
  }
}
