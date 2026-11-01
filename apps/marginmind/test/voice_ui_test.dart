import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';
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

final _screenshots = Platform.environment['MM_VOICE_SCREENSHOTS'];

Future<void> _capture(WidgetTester tester, String name) async {
  if (_screenshots == null) return;
  final toolbar = tester.getRect(find.byKey(const ValueKey('assistant-voice-toolbar')));
  final input = tester.getRect(find.byKey(const ValueKey('assistant-input-container')));
  final bounds = toolbar.expandToInclude(input).inflate(10);
  final image = (await tester.runAsync(
    () => (tester.binding.renderViews.first.debugLayer! as OffsetLayer).toImage(bounds, pixelRatio: 2),
  ))!;
  final png = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png)))!;
  await tester.runAsync(() async {
    await Directory(_screenshots!).create(recursive: true);
    await File('$_screenshots/$name.png').writeAsBytes(png.buffer.asUint8List());
  });
  image.dispose();
}

void main() {
  setUpAll(() async {
    if (_screenshots == null) return;
    final bytes = ByteData.sublistView(File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf').readAsBytesSync());
    for (final family in ['.AppleSystemUIFont', 'CupertinoSystemText', 'CupertinoSystemDisplay', 'Roboto']) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
    await (FontLoader(
      'packages/cupertino_icons/CupertinoIcons',
    )..addFont(rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'))).load();
    await (FontLoader(
      'packages/lucide_icons_flutter/Lucide',
    )..addFont(rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'))).load();
    await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final phone in [false, true]) {
    testWidgets('voice toolbar stays outside unchanged input with separated controls (phone: $phone)', (tester) async {
      final mic = FakeMicrophone();
      final session = FakeVoiceSession()..result = '';
      final controller = VoiceController(microphone: mic, sessionFactory: session.factory);
      final secrets = FakeSecrets()..values[VoiceSettings.account(VoiceProvider.aliyun)] = 'speech-key';
      final app = await openAssistantApp(
        tester,
        size: phone ? const Size(390, 844) : const Size(1400, 900),
        secretStore: secrets,
        prefs: {'voice.provider': 'aliyun', 'settings.appearance': phone ? 'light' : 'dark'},
        overrides: [
          voiceControllerFactoryProvider.overrideWithValue(() => controller),
          touchPlatformProvider.overrideWithValue(phone),
          phoneProvider.overrideWithValue(phone),
        ],
      );
      app.workspace.toggleAssistantPanel();
      await pumpFor(tester);
      final container = find.byKey(const ValueKey('assistant-input-container'));
      final toolbar = find.byKey(const ValueKey('assistant-voice-toolbar'));
      final voice = find.byKey(const ValueKey('assistant-voice'));
      final send = find.byKey(const ValueKey('assistant-send'));
      final inputSize = tester.getSize(container);
      expect(toolbar, findsNothing);
      expect(tester.getRect(send).left - tester.getRect(voice).right, 8);
      await tester.tap(voice);
      await tester.pumpAndSettle();
      expect(tester.getSize(container), inputSize);
      final barRect = tester.getRect(toolbar), inputRect = tester.getRect(container);
      expect(barRect.left, inputRect.left);
      expect(barRect.right, inputRect.right);
      expect(inputRect.top - barRect.bottom, 8);
      expect(find.descendant(of: container, matching: toolbar), findsNothing);
      expect(find.text('正在录音'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('00:02'), findsOneWidget);
      await _capture(tester, phone ? 'phone-recording' : 'desktop-recording');
      await tester.tap(voice); // Stop produces the neutral empty-speech notice.
      await pumpFor(tester);
      expect(find.text('没有听到声音'), findsOneWidget);
      expect(tester.getSize(container), inputSize);
      final status = tester.widget<Text>(find.byKey(const ValueKey('assistant-voice-status')));
      expect(status.style!.color, isNot(tester.element(container).mmColors.critical));
      await _capture(tester, phone ? 'phone-empty' : 'desktop-empty');
      await tester.tap(find.byKey(const ValueKey('assistant-voice-dismiss')));
      await tester.pumpAndSettle();
      expect(toolbar, findsNothing);
      await tester.tap(voice);
      await tester.pumpAndSettle();
      expect(toolbar, findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('assistant-voice-cancel')));
      await pumpFor(tester);
      expect(toolbar, findsNothing);
      expect(conversationOf(tester).messages, isEmpty);
      expect(tester.takeException(), null);
    });
  }

  testWidgets('external toolbar covers connection, processing, retained transcript and retry', (tester) async {
    final session = FakeVoiceSession()..starting = Completer<void>();
    final controller = VoiceController(microphone: FakeMicrophone(), sessionFactory: session.factory);
    final secrets = FakeSecrets()..values[VoiceSettings.account(VoiceProvider.aliyun)] = 'speech-key';
    final app = await openAssistantApp(
      tester,
      secretStore: secrets,
      prefs: {'voice.provider': 'aliyun', 'settings.appearance': 'dark'},
      overrides: [voiceControllerFactoryProvider.overrideWithValue(() => controller)],
    );
    app.workspace.toggleAssistantPanel();
    await pumpFor(tester);
    final voice = find.byKey(const ValueKey('assistant-voice'));
    final field = find.byKey(const ValueKey('assistant-input'));
    await tester.enterText(field, '原草稿');
    await tester.tap(voice);
    await pumpFor(tester);
    expect(find.text('正在连接语音服务…'), findsOneWidget);
    await _capture(tester, 'desktop-connecting');
    session.starting!.complete();
    await pumpFor(tester);
    session.onText!('第一段');
    await tester.pump();
    session.finishing = Completer<String>();
    await tester.tap(voice);
    await pumpFor(tester);
    expect(find.text('正在转文字…'), findsOneWidget);
    expect(tester.widget<TextField>(field).readOnly, true);
    await _capture(tester, 'desktop-transcribing');
    session.finishing!.complete('第一段');
    await pumpFor(tester);
    expect(find.byKey(const ValueKey('assistant-voice-toolbar')), findsNothing);
    expect(conversationOf(tester).messages, isEmpty);
    await tester.tap(voice);
    await tester.pumpAndSettle();
    session.onText!('第二段');
    session.onError!(StateError('connection lost'));
    await pumpFor(tester);
    expect(find.text('语音连接中断，已保留文字'), findsOneWidget);
    final retained = tester.widget<TextField>(field).controller!.text;
    expect(retained, contains('第一段第二段'));
    await _capture(tester, 'desktop-interrupted');
    await tester.tap(find.byKey(const ValueKey('assistant-voice-retry')));
    await tester.pumpAndSettle();
    expect(controller.phase, VoicePhase.recording);
    session.onText!('重试文字');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('assistant-voice-cancel')));
    await pumpFor(tester);
    expect(tester.widget<TextField>(field).controller!.text, retained);
    expect(tester.takeException(), null);
  });

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
