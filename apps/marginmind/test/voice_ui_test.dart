import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/app/app_commands.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/voice/voice_controller.dart';
import 'package:marginmind/features/voice/voice_settings.dart';
import 'package:marginmind/features/voice/voice_settings_page.dart';
import 'package:marginmind/settings/settings_window.dart';
import 'package:mm_design/mm_design.dart';

import 'assistant_support.dart';
import 'helpers.dart';
import 'voice_support.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('speech settings persist credentials outside preferences (${dark ? 'dark' : 'light'})', (tester) async {
      final secrets = FakeSecrets();
      var checks = 0;
      final scope = await pumpApp(
        tester,
        size: const Size(1000, 760),
        prefs: {'settings.language': 'zh', if (dark) 'settings.appearance': 'dark'},
        overrides: [
          assistantSecretsProvider.overrideWithValue(secrets),
          voiceConnectionTestProvider.overrideWithValue((settings, key) async {
            checks++;
            expect(settings.provider, VoiceProvider.doubao);
            expect(key, 'test-token');
          }),
        ],
      );
      showSettings(tester.element(find.byType(MMWindowScaffold)), tab: SettingsTab.voice);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('voice-provider')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('豆包实时语音识别 2.0').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('voice-app-id')), 'app-123');
      await tester.enterText(find.byKey(const ValueKey('voice-key')), 'test-token');
      await tester.tap(find.byKey(const ValueKey('voice-test')));
      await tester.pumpAndSettle();
      expect(checks, 1);
      expect(find.text('连接正常'), findsOneWidget);
      expect(scope.read(voiceSettingsProvider).provider, VoiceProvider.none); // Testing doesn't save the draft.
      await tester.tap(find.byKey(const ValueKey('voice-save')));
      await tester.pumpAndSettle();
      expect(scope.read(voiceSettingsProvider).provider, VoiceProvider.doubao);
      expect(secrets.values[VoiceSettings.account(VoiceProvider.doubao)], 'test-token');
      final prefs = scope.read(sharedPreferencesProvider);
      expect(prefs.getKeys().where((key) => prefs.get(key) == 'test-token'), isEmpty);
      expect(find.text('已保存'), findsOneWidget);
      expect(tester.takeException(), null);
    });
  }

  testWidgets('dictation replaces selected text, revises interim text and Enter finishes without sending', (
    tester,
  ) async {
    final mic = FakeMicrophone(), session = FakeVoiceSession();
    final controller = VoiceController(microphone: mic, sessionFactory: session.factory);
    final secrets = FakeSecrets()..values[VoiceSettings.account(VoiceProvider.aliyun)] = 'speech-key';
    final app = await openAssistantApp(
      tester,
      secretStore: secrets,
      prefs: {'voice.provider': 'aliyun'},
      overrides: [voiceControllerFactoryProvider.overrideWithValue(() => controller)],
    );
    app.workspace.toggleAssistantPanel();
    await pumpFor(tester);
    final field = find.byKey(const ValueKey('assistant-input'));
    await tester.enterText(field, '前文旧内容后文');
    final text = tester.widget<TextField>(field).controller!;
    text.selection = const TextSelection(baseOffset: 2, extentOffset: 5);
    await tester.tap(find.byKey(const ValueKey('assistant-voice')));
    await tester.pumpAndSettle();
    expect(controller.phase, VoicePhase.recording);
    expect(tester.widget<TextField>(field).readOnly, true);
    session.onText!('临时');
    await tester.pump();
    expect(text.text, '前文临时后文');
    session.onText!('修正后的文字');
    await tester.pump();
    expect(text.text, '前文修正后的文字后文');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await pumpFor(tester, 12);
    expect(controller.phase, VoicePhase.idle);
    expect(text.text, '前文最终识别结果。后文');
    expect(conversationOf(tester).messages, isEmpty);
    expect(tester.widget<TextField>(field).readOnly, false);
    expect(tester.takeException(), null);
  });

  testWidgets('cancel restores the original draft and panel closure stops the microphone', (tester) async {
    final mic = FakeMicrophone(), session = FakeVoiceSession();
    final controller = VoiceController(microphone: mic, sessionFactory: session.factory);
    final secrets = FakeSecrets()..values[VoiceSettings.account(VoiceProvider.aliyun)] = 'speech-key';
    final app = await openAssistantApp(
      tester,
      secretStore: secrets,
      prefs: {'voice.provider': 'aliyun'},
      overrides: [voiceControllerFactoryProvider.overrideWithValue(() => controller)],
    );
    app.workspace.toggleAssistantPanel();
    await pumpFor(tester);
    final field = find.byKey(const ValueKey('assistant-input'));
    await tester.enterText(field, '保留我的草稿');
    await tester.tap(find.byKey(const ValueKey('assistant-voice')));
    await tester.pumpAndSettle();
    session.onText!('不要插入');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpFor(tester, 12);
    expect(tester.widget<TextField>(field).controller!.text, '保留我的草稿');
    session.onText!('迟到的结果');
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, '保留我的草稿');
    Actions.invoke(tester.element(field), const VoiceInputIntent());
    await pumpFor(tester);
    expect(controller.phase, VoicePhase.recording);
    app.workspace.closePanel();
    await pumpFor(tester, 12);
    expect(controller.active, false);
    expect(mic.stops, greaterThan(0));
    expect(tester.takeException(), null);
  });

  testWidgets('unconfigured microphone opens speech settings without recording', (tester) async {
    final mic = FakeMicrophone(), session = FakeVoiceSession();
    final app = await openAssistantApp(
      tester,
      overrides: [
        voiceControllerFactoryProvider.overrideWithValue(
          () => VoiceController(microphone: mic, sessionFactory: session.factory),
        ),
      ],
    );
    app.workspace.toggleAssistantPanel();
    await pumpFor(tester);
    await tester.tap(find.byKey(const ValueKey('assistant-voice')));
    await tester.pumpAndSettle();
    expect(find.byType(VoiceSettingsPage), findsOneWidget);
    expect(mic.starts, 0);
  });
}
