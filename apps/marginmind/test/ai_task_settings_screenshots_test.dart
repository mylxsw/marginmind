/// Renders Settings › AI Features in the running app widget tree to PNGs with
/// real fonts. Skipped unless MM_SCREENSHOTS names an output directory and
/// MM_FONT a CJK font file:
///
///   MM_SCREENSHOTS=docs/evidence/gul-648 MM_FONT=~/.fonts/NotoSansSC.otf \
///     flutter test test/ai_task_settings_screenshots_test.dart
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart' show phoneProvider, touchPlatformProvider;
import 'package:marginmind/features/assistant/assistant_routing.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/assistant/settings/ai_routing_usage.dart';
import 'package:marginmind/features/assistant/settings/ai_task_settings.dart';
import 'package:marginmind/features/assistant/settings/model_route_picker.dart';
import 'package:marginmind/settings/settings_window.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import 'assistant_support.dart' show FakeSecrets;
import 'helpers.dart';

final _out = Platform.environment['MM_SCREENSHOTS'];
final _font = Platform.environment['MM_FONT'];

Future<void> _loadFonts() async {
  final bytes = ByteData.sublistView(await File(_font!).readAsBytes());
  for (final family in ['.AppleSystemUIFont', 'CupertinoSystemText', 'CupertinoSystemDisplay', 'Roboto', 'SF Mono']) {
    await (FontLoader(family)..addFont(Future.value(bytes))).load();
  }
  final pub = Platform.environment['PUB_CACHE'] ?? '${Platform.environment['HOME']}/.pub-cache';
  final hosted = Directory('$pub/hosted/pub.dev').listSync().whereType<Directory>();
  final cupertino = hosted.lastWhere((d) => d.path.contains('cupertino_icons-'));
  await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
        Future.value(ByteData.sublistView(File('${cupertino.path}/assets/CupertinoIcons.ttf').readAsBytesSync())),
      ))
      .load();
  final lucide = hosted.lastWhere((d) => d.path.contains('lucide_icons_flutter-'));
  final lucideBytes = ByteData.sublistView(File('${lucide.path}/assets/lucide.ttf').readAsBytesSync());
  await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(Future.value(lucideBytes))).load();
}

Future<void> _save(WidgetTester tester, String name) async {
  Directory(_out!).createSync(recursive: true);
  final image = (await tester.runAsync(() {
    final view = tester.binding.renderViews.first;
    return (view.debugLayer! as OffsetLayer).toImage(Offset.zero & view.size, pixelRatio: 2);
  }))!;
  final png = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png)))!;
  await tester.runAsync(() => File('$_out/$name.png').writeAsBytes(png.buffer.asUint8List()));
}

final _services = [
  AssistantService(
    id: 'anthropic',
    protocol: ServiceProtocol.anthropic,
    name: 'Anthropic',
    endpoint: 'https://api.anthropic.com',
    models: const [
      ServiceModel(id: 'claude-haiku-5-5', name: 'Claude Haiku 5.5'),
      ServiceModel(id: 'claude-opus-5-5', name: 'Claude Opus 5.5'),
    ],
  ),
  AssistantService(
    id: 'proxy',
    protocol: ServiceProtocol.openai,
    name: '公司代理',
    endpoint: 'https://proxy.example/v1',
    models: const [
      ServiceModel(id: 'opus-proxy', name: 'Claude Opus 5.5'),
      ServiceModel(id: 'gpt-5-mini', name: 'GPT-5 mini'),
    ],
  ),
];

Map<String, Object> _prefs({
  bool dark = false,
  Map<String, dynamic> bindings = const {},
  Map<String, dynamic>? quick,
}) => {
  'settings.language': 'zh',
  if (dark) 'settings.appearance': 'dark',
  AssistantServicesStore.settingsKey: jsonEncode(AssistantServices(services: _services).toJson()),
  AssistantRoutingStore.settingsKey: jsonEncode({
    'version': 1,
    'revision': 1,
    'defaults': {
      'quick': quick ?? {'serviceId': 'anthropic', 'modelId': 'claude-haiku-5-5'},
      'heavy': {'serviceId': 'anthropic', 'modelId': 'claude-opus-5-5'},
    },
    'bindings': {
      'title_generate': {
        'mode': 'explicit',
        'model': {'serviceId': 'proxy', 'modelId': 'gpt-5-mini'},
      },
      ...bindings,
    },
    'heavyReasoning': 'auto',
  }),
};

FakeSecrets _keys() => FakeSecrets()
  ..values[AssistantServicesStore.account('anthropic')] = 'a'
  ..values[AssistantServicesStore.account('proxy')] = 'p';

Future<void> _open(
  WidgetTester tester, {
  required Map<String, Object> prefs,
  Size size = const Size(1280, 860),
  SettingsTab tab = SettingsTab.aiTasks,
  AiTaskFocus? focus,
  bool phone = false,
  List<RoutingUse> uses = const [],
}) async {
  await pumpApp(
    tester,
    prefs: prefs,
    size: size,
    overrides: [
      assistantSecretsProvider.overrideWithValue(_keys()),
      if (phone) ...[touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(true)],
      aiRoutingUsageIndexProvider.overrideWithValue(_Uses(uses)),
    ],
  );
  showSettings(tester.element(find.byType(MMWindowScaffold)), tab: tab, focus: focus);
  await tester.pumpAndSettle();
}

class _Uses implements AiRoutingUsageIndex {
  _Uses(this.uses);
  final List<RoutingUse> uses;
  @override
  Future<List<RoutingUse>> listModelUses() async => uses;
  @override
  (TaskType, String)? run(String runId) => (TaskType.documentTranslate, 'Deep Work');
}

Finder _row(String label) => find.byWidgetPredicate((w) => w is ModelRoutePicker && w.semanticLabel == label);

void main() {
  final skip = _out == null || _font == null;
  setUpAll(() async {
    if (!skip) await _loadFonts();
  });

  testWidgets('AI features: compatibility explanation', (tester) async {
    await _open(tester, prefs: _prefs(dark: true));
    await _save(tester, 'compatibility-status');
    await tester.tap(find.byKey(const ValueKey('ai-action-default-quick')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await _save(tester, 'compatibility-explanation');
  }, skip: skip);

  testWidgets('AI features: normal, menu, draft', (tester) async {
    await _open(tester, prefs: _prefs());
    await _save(tester, '01-normal');
    await tester.tap(_row('单词释义'));
    await tester.pumpAndSettle();
    await _save(tester, '02-quick-menu');
    await tester.tap(find.text('Claude Haiku 5.5').hitTestable().last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(_row('调研与查证'));
    await tester.pumpAndSettle();
    await tester.tap(_row('调研与查证'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GPT-5 mini').hitTestable().last);
    await tester.pumpAndSettle();
    await _save(tester, '03-draft-unsaved');
    await tester.tap(find.byKey(const ValueKey('ai-tasks-save')));
    await tester.pumpAndSettle();
    await _save(tester, '04-saved');
    await settleHud(tester);
  }, skip: skip);

  testWidgets('AI features: invalid references and dark', (tester) async {
    await _open(
      tester,
      prefs: _prefs(
        dark: true,
        quick: {
          'serviceId': 'anthropic',
          'modelId': 'claude-sonnet-4',
          'serviceLabel': 'Anthropic',
          'modelLabel': 'Claude Sonnet 4',
        },
        bindings: {
          'research': {
            'mode': 'explicit',
            'model': {'serviceId': 'gone', 'modelId': 'x', 'serviceLabel': '旧服务', 'modelLabel': 'Qwen3 8B'},
          },
        },
      ),
    );
    await _save(tester, '05-invalid-dark');
  }, skip: skip);

  testWidgets('AI features: located model, removal impact, narrow phone', (tester) async {
    await _open(
      tester,
      prefs: _prefs(),
      focus: const AiTaskFocusModel(ModelReference('anthropic', 'claude-haiku-5-5')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _save(tester, '06-located-model');
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.tap(find.byKey(const ValueKey('settings-tab-models')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('service-header-anthropic')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('model-remove-claude-haiku-5-5')));
    await tester.pumpAndSettle();
    await _save(tester, '07-remove-impact');
  }, skip: skip);

  testWidgets(
    'AI features: phone sheet',
    (tester) async {
      await _open(tester, prefs: _prefs(), size: const Size(375, 760), phone: true);
      await tester.drag(find.byKey(const ValueKey('settings-ai-tasks')), const Offset(0, -260));
      await tester.pumpAndSettle();
      await _save(tester, '08-phone');
    },
    skip: skip,
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
