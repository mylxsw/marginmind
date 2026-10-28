import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/assistant/settings/web_search_settings.dart';
import 'package:marginmind/features/assistant/widgets/assistant_panel.dart' show preferredModel;
import 'package:marginmind/features/assistant/widgets/service_logo.dart';
import 'package:marginmind/settings/settings_window.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import 'assistant_support.dart';
import 'assistant_services_test.dart' show RecordingServicesStore;
import 'helpers.dart' show doubleTap, settleHud;

/// Opens the panel, then Settings › Models from its gear.
Future<void> _openModels(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('toolbar-assistant')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('assistant-settings')));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('settings-models')), findsOneWidget);
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(EditableText)), text);
  await tester.pump();
}

/// Lets the 0.7 second pause pass and the check finish.
Future<void> _afterPause(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 750));
  await tester.pumpAndSettle();
}

Future<TestGesture> _hover(WidgetTester tester, Finder finder) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: tester.getCenter(finder));
  addTearDown(gesture.removePointer);
  await tester.pumpAndSettle();
  return gesture;
}

AssistantServices _services(AssistantApp app) => app.container.read(assistantServicesProvider).value!;

class UnavailableKeyStore extends FakeSecrets {
  bool blockReads = true;
  bool blockWrites = true;
  @override
  Future<String?> read(String account) async {
    if (blockReads) throw const ResearchFailure(ResearchFailureKind.authentication, 'secret_store');
    return super.read(account);
  }

  @override
  Future<void> write(String account, String key) async {
    if (blockWrites) throw const ResearchFailure(ResearchFailureKind.authentication, 'secret_store');
    await super.write(account, key);
  }
}

void main() {
  testWidgets('inaccessible saved keys are explained and retry restores AI without re-entering a key', (tester) async {
    final secrets = UnavailableKeyStore(), catalog = FakeCatalog();
    final app = await openAssistantApp(tester, secretStore: secrets, catalog: catalog);
    await tester.tap(find.byKey(const ValueKey('toolbar-assistant')));
    await tester.pumpAndSettle();
    expect(await app.container.read(assistantCredentialStateProvider.future), AssistantCredentialState.unavailable);
    expect(find.byKey(const ValueKey('connect-key-unavailable')), findsOneWidget);
    expect(find.text('API Key 无效'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('connect-retry-key')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('connect-key-unavailable')), findsOneWidget);
    secrets.blockReads = false;
    await tester.tap(find.byKey(const ValueKey('connect-retry-key')));
    await tester.pumpAndSettle();
    expect(await app.container.read(assistantCredentialStateProvider.future), AssistantCredentialState.ready);
    expect(find.byKey(const ValueKey('assistant-connect')), findsNothing);
    expect(catalog.checked, isEmpty); // Retry reads storage; it does not send the key to the network.
  });

  testWidgets('storage failures never say the provider rejected a valid key and saving can be retried', (tester) async {
    final secrets = UnavailableKeyStore(), catalog = FakeCatalog();
    final app = await openAssistantApp(tester, key: false, secretStore: secrets, catalog: catalog);
    await tester.tap(find.byKey(const ValueKey('toolbar-assistant')));
    await tester.pumpAndSettle();
    await _enter(tester, 'connect-key', 'valid-test-key');
    await tester.tap(find.byKey(const ValueKey('connect-button')));
    await tester.pumpAndSettle();
    expect(catalog.checked.single.$2, 'valid-test-key');
    expect(find.textContaining('暂时无法保存 API Key'), findsOneWidget);
    expect(find.text('API Key 无效'), findsNothing);
    expect(await app.container.read(assistantConfiguredProvider.future), isFalse);
    expect(secrets.values, isEmpty);
    secrets
      ..blockReads = false
      ..blockWrites = false;
    await tester.tap(find.byKey(const ValueKey('connect-button')));
    await tester.pumpAndSettle();
    expect(await app.container.read(assistantConfiguredProvider.future), isTrue);
    expect(secrets.values[AssistantServicesStore.account('legacy-claude')], 'valid-test-key');
    expect(find.byKey(const ValueKey('assistant-connect')), findsNothing);
  });

  testWidgets('credential recovery uses the selected service when multiple services share a protocol', (tester) async {
    AssistantService service(String id, String host) => AssistantService(
      id: id,
      protocol: ServiceProtocol.openai,
      name: id,
      endpoint: 'https://$host/v1',
      models: const [ServiceModel(id: 'model')],
    );
    final value = AssistantServices(
      services: [service('first', 'first.example'), service('selected', 'selected.example')],
      defaultModel: const ModelReference('selected', 'model'),
    );
    final secrets = UnavailableKeyStore(), catalog = FakeCatalog();
    final app = await openAssistantApp(
      tester,
      key: false,
      secretStore: secrets,
      catalog: catalog,
      prefs: {AssistantServicesStore.settingsKey: jsonEncode(value.toJson())},
    );
    await tester.tap(find.byKey(const ValueKey('toolbar-assistant')));
    await tester.pumpAndSettle();
    secrets
      ..blockReads = false
      ..blockWrites = false;
    await _enter(tester, 'connect-key', 'replacement-test-key');
    await tester.tap(find.byKey(const ValueKey('connect-button')));
    await tester.pumpAndSettle();
    expect(catalog.checked.single, ('https://selected.example/v1', 'replacement-test-key'));
    expect(secrets.values[AssistantServicesStore.account('selected')], 'replacement-test-key');
    expect(secrets.values.containsKey(AssistantServicesStore.account('first')), isFalse);
    expect(_services(app).defaultModel!.serviceId, 'selected');
  });

  // Flutter 3.47 asserts (debug, with semantics) when a sheet closes after a
  // dialog opened over it; this flow needs both, and semantics are tested elsewhere.
  testWidgets('new service → key → fetch models → enable → default → listed in the model menu', (tester) async {
    final catalog = FakeCatalog(
      models: const [
        ServiceModel(id: 'gpt-5', name: 'GPT-5'),
        ServiceModel(id: 'gpt-5-mini'),
      ],
    );
    final app = await openAssistantApp(tester, catalog: catalog);
    await _openModels(tester);
    await tester.tap(find.byKey(const ValueKey('settings-add-service')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('service-list')), findsOneWidget);
    expect(find.text('OpenAI 兼容'), findsOneWidget);
    final options = [for (final p in ServiceProtocol.values) find.byKey(ValueKey('service-option-${p.name}'))];
    final positions = options.map(tester.getTopLeft).toList();
    expect(positions.map((p) => p.dx).toSet(), hasLength(1));
    expect(positions.map((p) => p.dy).toSet(), hasLength(ServiceProtocol.values.length));
    final labelContext = tester.element(find.text('OpenAI 兼容'));
    expect(DefaultTextStyle.of(labelContext).style.decoration, isNot(TextDecoration.underline));

    await tester.tap(find.byKey(const ValueKey('service-option-openai')));
    await tester.pumpAndSettle();
    final service = _services(app).services.last;
    expect(service.protocol, ServiceProtocol.openai);
    expect(service.responses, isTrue);
    // The new card is open, OpenAI's own mark shown.
    expect(find.byKey(const ValueKey('service-key')), findsOneWidget);
    expect(find.byKey(const ValueKey('service-logo-openai')), findsWidgets);

    await _enter(tester, 'service-key', 'sk-test');
    expect(catalog.checked, isEmpty); // Only after a pause.
    await _afterPause(tester);
    expect(catalog.checked.last, ('https://api.openai.com/v1', 'sk-test'));
    expect(app.secrets.values[AssistantServicesStore.account(service.id)], 'sk-test');
    expect(find.byKey(const ValueKey('service-failure')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('service-add-model')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('add-models')), findsOneWidget);
    expect(find.text('GPT-5'), findsOneWidget);
    expect(find.text('添加'), findsOneWidget); // Nothing picked yet.
    await tester.tap(find.byKey(const ValueKey('add-model-gpt-5')));
    await tester.pump();
    await tester.enterText(
      find.descendant(of: find.byKey(const ValueKey('add-model-search')), matching: find.byType(EditableText)),
      'my-model',
    );
    await tester.pump();
    expect(find.text('添加“my-model”'), findsOneWidget);
    expect(find.text('GPT-5'), findsNothing); // Filtered out.
    await tester.tap(find.byKey(const ValueKey('add-model-manual')));
    await tester.pump();
    expect(find.text('添加 2 个'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('add-models-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('add-models')), findsNothing);
    final added = _services(app).services.firstWhere((s) => s.id == service.id).models;
    expect(added.map((m) => m.id), ['gpt-5', 'my-model']);
    expect(added.every((m) => m.enabled && m.tools == ToolCapability.unknown), isTrue);
    expect(catalog.probes, 0);
    expect(find.text('已启用 2 个模型'), findsOneWidget);

    // Off: not in the menu; then on again.
    await tester.tap(find.byKey(const ValueKey('model-switch-my-model')));
    await tester.pumpAndSettle();
    expect(_services(app).enabledModelsByService[service.id]!.map((m) => m.model), ['gpt-5']);

    // Make GPT-5 the default from its row (shown on hover).
    expect(find.byKey(const ValueKey('model-set-default-gpt-5')), findsNothing);
    await _hover(tester, find.byKey(const ValueKey('model-gpt-5')));
    await tester.tap(find.byKey(const ValueKey('model-set-default-gpt-5')));
    await tester.pumpAndSettle();
    expect(_services(app).defaultModel!.modelId, 'gpt-5');
    expect(find.byKey(const ValueKey('model-default')), findsOneWidget);
    // The empty conversation follows the new default.
    expect(conversationOf(tester).model.model, 'gpt-5');

    await tester.tap(find.byKey(const ValueKey('settings-close')));
    await tester.pumpAndSettle();
    expect(find.text('GPT-5'), findsOneWidget); // The model button.
    await tester.tap(find.byKey(const ValueKey('assistant-model')));
    await tester.pumpAndSettle();
    // Grouped by service, names only, then “Manage Models…”.
    expect(find.text('OpenAI'), findsOneWidget);
    expect(find.text('claude'), findsOneWidget);
    expect(find.text('my-model'), findsNothing);
    expect(find.text('管理模型…'), findsOneWidget);
    await tester.tap(find.text('claude-opus-5-5'));
    await tester.pumpAndSettle();
    // Only this conversation changes; the default stays.
    expect(conversationOf(tester).model.model, 'claude-opus-5-5');
    expect(_services(app).defaultModel!.modelId, 'gpt-5');
    await tester.tap(find.byKey(const ValueKey('assistant-model')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('管理模型…'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-models')), findsOneWidget);
  }, semanticsEnabled: false);

  testWidgets('a service card: failure reason, reveal, address, rename, remove model, off, remove', (tester) async {
    final catalog = FakeCatalog(status: ConnectionStatus.authFailed);
    final app = await openAssistantApp(tester, catalog: catalog);
    await _openModels(tester);
    // Anthropic hides its address until asked.
    await tester.tap(find.byKey(const ValueKey('settings-add-service')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('service-option-anthropic')));
    await tester.pumpAndSettle();
    final id = _services(app).services.last.id;
    expect(find.byKey(const ValueKey('service-endpoint')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('service-custom-address')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('service-endpoint')), findsOneWidget);
    await _enter(tester, 'service-endpoint', 'https://proxy.example');
    await _enter(tester, 'service-key', 'bad');
    final field = tester.widget<TextField>(
      find.descendant(of: find.byKey(const ValueKey('service-key')), matching: find.byType(TextField)),
    );
    expect(field.obscureText, isTrue);
    await tester.tap(find.byKey(const ValueKey('service-reveal')));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(
            find.descendant(of: find.byKey(const ValueKey('service-key')), matching: find.byType(TextField)),
          )
          .obscureText,
      isFalse,
    );
    await _afterPause(tester);
    // Failure shows on the card's second line; there is no check button.
    expect(find.byKey(const ValueKey('service-failure')), findsOneWidget);
    expect(find.text('API Key 无效'), findsOneWidget);
    expect(_services(app).services.last.endpoint, 'https://proxy.example');
    catalog.status = ConnectionStatus.unreachable;
    await _enter(tester, 'service-key', 'other');
    await _afterPause(tester);
    expect(find.text('连不上服务'), findsOneWidget);
    // Clearing the key stops checking and clears the reason.
    await _enter(tester, 'service-key', '');
    await _afterPause(tester);
    expect(find.byKey(const ValueKey('service-failure')), findsNothing);

    // Rename the service.
    await _enter(tester, 'service-name', '我的代理');
    await _afterPause(tester);
    expect(_services(app).services.last.name, '我的代理');

    // A model: rename by double click, then remove.
    await app.container
        .read(assistantServicesProvider.notifier)
        .upsertModel(id, const ServiceModel(id: 'claude-x', name: 'Claude X'));
    await tester.pumpAndSettle();
    await doubleTap(tester, find.text('Claude X'));
    await tester.enterText(find.byType(EditableText).last, '新名字');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_services(app).services.last.models.single.name, '新名字');
    await _hover(tester, find.byKey(const ValueKey('model-claude-x')));
    await tester.tap(find.byKey(const ValueKey('model-remove-claude-x')));
    await tester.pumpAndSettle();
    expect(_services(app).services.last.models, isEmpty);
    expect(find.text('还没有模型'), findsOneWidget);

    // Collapse; the switch turns the service off without opening it.
    await tester.tap(find.byKey(ValueKey('service-header-$id')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('service-key')), findsNothing);
    await tester.tap(find.byKey(ValueKey('service-switch-$id')));
    await tester.pumpAndSettle();
    expect(_services(app).services.last.enabled, isFalse);
    expect(find.text('已停用'), findsOneWidget);
    expect(find.byKey(const ValueKey('service-key')), findsNothing);

    // Removing asks first and deletes the key.
    app.secrets.values[AssistantServicesStore.account(id)] = 'k';
    await tester.tap(find.byKey(ValueKey('service-header-$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('service-remove')));
    await tester.pumpAndSettle();
    expect(find.text('移除“我的代理”？'), findsOneWidget);
    await tester.tap(find.text('移除服务').last);
    await tester.pumpAndSettle();
    expect(_services(app).services.any((s) => s.id == id), isFalse);
    expect(app.secrets.values.containsKey(AssistantServicesStore.account(id)), isFalse);
  });

  testWidgets('add models: a listing failure says why; added models are marked', (tester) async {
    final catalog = FakeCatalog(listFailure: const ResearchFailure(ResearchFailureKind.authentication));
    await openAssistantApp(tester, catalog: catalog);
    await _openModels(tester);
    await tester.tap(find.byKey(const ValueKey('service-header-legacy-claude')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('service-add-model')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('add-model-error')), findsOneWidget);
    expect(find.text('API Key 无效'), findsOneWidget);
    // An ID typed by hand can still be added; one already there cannot.
    await tester.enterText(
      find.descendant(of: find.byKey(const ValueKey('add-model-search')), matching: find.byType(EditableText)),
      'claude-new',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('add-model-manual')), findsOneWidget);
    catalog.listFailure = null;
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('service-add-model')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(of: find.byKey(const ValueKey('add-model-search')), matching: find.byType(EditableText)),
      'claude-opus-5-5',
    );
    await tester.pump();
    expect(find.text('已添加'), findsOneWidget);
    expect(find.text('添加'), findsOneWidget);
  });

  testWidgets('a failed local model save keeps the selection for retry', (tester) async {
    late RecordingServicesStore store;
    final catalog = FakeCatalog();
    final app = await openAssistantApp(
      tester,
      catalog: catalog,
      overrides: [
        assistantServicesStoreProvider.overrideWith(
          (ref) =>
              store = RecordingServicesStore(ref.watch(sharedPreferencesProvider), ref.watch(assistantSecretsProvider)),
        ),
      ],
    );
    await _openModels(tester);
    await tester.tap(find.byKey(const ValueKey('service-header-legacy-claude')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('service-add-model')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-model-claude-sonnet-5-5')));
    await tester.pump();
    store.fail = true;
    await tester.tap(find.byKey(const ValueKey('add-models-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('add-models')), findsOneWidget);
    expect(_services(app).services.first.models, hasLength(1));
    store.fail = false;
    await tester.tap(find.byKey(const ValueKey('add-models-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('add-models')), findsNothing);
    expect(_services(app).services.first.models.last.id, 'claude-sonnet-5-5');
    expect(catalog.probes, 0);
    await settleHud(tester);
  });

  testWidgets('web search: unconfigured or an external service, independent of the model', (tester) async {
    final checks = <SearchProvider>[];
    var status = ConnectionStatus.unreachable;
    final app = await openAssistantApp(
      tester,
      overrides: [
        webSearchCheckerProvider.overrideWithValue((provider, {cancellation}) async {
          checks.add(provider);
          return status;
        }),
      ],
    );
    await _openModels(tester);
    await tester.tap(find.byKey(const ValueKey('settings-tab-webSearch')));
    await tester.pumpAndSettle();
    expect(find.text('未配置'), findsOneWidget);
    // Search settings do not explain or depend on the selected model.
    expect(find.byKey(const ValueKey('search-unavailable')), findsNothing);
    Future<void> choose(String label) async {
      await tester.tap(find.byKey(const ValueKey('search-backend')));
      await tester.pumpAndSettle();
      for (final name in ['未配置', 'Cloudflare', 'SearXNG', 'Tavily', 'Brave Search']) {
        expect(find.text(name), findsWidgets);
      }
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    await choose('SearXNG');
    expect(app.container.read(webSearchSettingsProvider).backend, WebSearchBackend.searxng);
    await _enter(tester, 'search-endpoint', 'http://localhost:8080');
    await _afterPause(tester);
    expect(checks, hasLength(1));
    expect(app.container.read(webSearchSettingsProvider).endpoint, 'http://localhost:8080');
    expect(find.text('连不上搜索服务'), findsOneWidget);

    await choose('Cloudflare');
    expect(find.text('账户 ID'), findsOneWidget);
    expect(find.text('API Token'), findsOneWidget);
    await _enter(tester, 'search-key', 'token');
    await _afterPause(tester);
    expect(checks, hasLength(1)); // The account is still missing.
    status = ConnectionStatus.authFailed;
    await _enter(tester, 'search-account', 'acct');
    await _afterPause(tester);
    expect(checks, hasLength(2));
    expect(find.text('API Token 无效'), findsOneWidget);
    expect(app.secrets.values[WebSearchSettingsController.cloudflareAccount], 'acct');
    expect(app.secrets.values[WebSearchSettingsController.account(WebSearchBackend.cloudflare)], 'token');

    await choose('Tavily');
    expect(find.text('API Token 无效'), findsNothing);
    status = ConnectionStatus.ok;
    await _enter(tester, 'search-key', 'tvly');
    await _afterPause(tester);
    expect(find.byKey(const ValueKey('search-failure')), findsNothing);
    expect(app.secrets.values[WebSearchSettingsController.account(WebSearchBackend.tavily)], 'tvly');

    await choose('Brave Search');
    status = ConnectionStatus.authFailed;
    await _enter(tester, 'search-key', 'brave');
    await _afterPause(tester);
    expect(find.text('API Key 无效'), findsOneWidget);

    // Switching to a compatible model does not change the service settings.
    final compatible = AssistantService(
      id: 'compat',
      protocol: ServiceProtocol.openai,
      name: 'Proxy',
      endpoint: 'https://proxy.example/v1',
      models: const [ServiceModel(id: 'coding/auto', name: 'Coding Auto')],
    );
    await app.container.read(assistantServicesProvider.notifier).upsert(compatible);
    await app.container
        .read(assistantServicesProvider.notifier)
        .setDefault(const ModelReference('compat', 'coding/auto'));
    await choose('未配置');
    expect(find.byKey(const ValueKey('search-unavailable')), findsNothing);
    expect(find.textContaining('不带搜索'), findsNothing);
    expect(app.container.read(webSearchSettingsProvider).backend, WebSearchBackend.none);
  });

  testWidgets('not configured: connect in the panel; failures say why; the old service is reused', (tester) async {
    final catalog = FakeCatalog(status: ConnectionStatus.authFailed);
    final app = await openAssistantApp(tester, key: false, catalog: catalog);
    await tester.tap(find.byKey(const ValueKey('toolbar-assistant')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('assistant-connect')), findsOneWidget);
    expect(find.text('先连接 AI 服务'), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-explain')), findsNothing);
    // Nothing to send without a key.
    await tester.tap(find.byKey(const ValueKey('connect-button')));
    await tester.pump();
    expect(catalog.checked, isEmpty);
    await _enter(tester, 'connect-key', 'bad');
    await tester.tap(find.byKey(const ValueKey('connect-button')));
    await tester.pumpAndSettle();
    expect(find.text('API Key 无效'), findsOneWidget);
    catalog.status = ConnectionStatus.unreachable;
    await tester.tap(find.byKey(const ValueKey('connect-button')));
    await tester.pumpAndSettle();
    expect(find.text('连不上服务'), findsOneWidget);
    // Ollama: an address instead of a key.
    await tester.tap(find.byKey(const ValueKey('connect-ollama')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('connect-key')), findsNothing);
    expect(find.byKey(const ValueKey('connect-endpoint')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('connect-button')));
    await tester.pumpAndSettle();
    expect(find.text('找不到本机 Ollama'), findsOneWidget);
    catalog
      ..status = ConnectionStatus.ok
      ..models = const [];
    await tester.tap(find.byKey(const ValueKey('connect-button')));
    await tester.pumpAndSettle();
    expect(find.text('这个服务没有可用的对话模型'), findsOneWidget);
    expect(_services(app).services.where((s) => s.protocol == ServiceProtocol.ollama), isEmpty);

    // Anthropic again: the migrated service without a key gets it.
    await tester.tap(find.byKey(const ValueKey('connect-anthropic')));
    await tester.pumpAndSettle();
    await _enter(tester, 'connect-key', 'good');
    await tester.tap(find.byKey(const ValueKey('connect-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('assistant-connect')), findsNothing);
    expect(find.byKey(const ValueKey('assistant-suggestions')), findsOneWidget);
    expect(_services(app).services.where((s) => s.protocol == ServiceProtocol.anthropic), hasLength(1));
    expect(app.secrets.values[AssistantServicesStore.account('legacy-claude')], 'good');
    expect(find.text('提问…'), findsOneWidget);
  });

  testWidgets('connect Gemini: the everyday model is picked from the list', (tester) async {
    final catalog = FakeCatalog(
      models: const [
        ServiceModel(id: 'gemini-2.5-flash'),
        ServiceModel(id: 'gemini-2.5-pro'),
      ],
    );
    final app = await openAssistantApp(tester, key: false, catalog: catalog);
    await tester.tap(find.byKey(const ValueKey('toolbar-assistant')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('connect-gemini')));
    await tester.pumpAndSettle();
    await _enter(tester, 'connect-key', 'g');
    await tester.tap(find.byKey(const ValueKey('connect-button')));
    await tester.pumpAndSettle();
    final gemini = _services(app).services.firstWhere((s) => s.protocol == ServiceProtocol.gemini);
    expect(_services(app).defaultModel!.serviceId, gemini.id);
    expect(_services(app).defaultModel!.modelId, 'gemini-2.5-pro');
    expect(conversationOf(tester).model.serviceId, gemini.id);
  });

  test('preferred first models and service marks', () {
    const models = [ServiceModel(id: 'a'), ServiceModel(id: 'claude-opus-5'), ServiceModel(id: 'claude-sonnet-5')];
    expect(preferredModel(ServiceProtocol.anthropic, models)!.id, 'claude-sonnet-5');
    expect(
      preferredModel(ServiceProtocol.openai, const [ServiceModel(id: 'o3'), ServiceModel(id: 'gpt-5')])!.id,
      'gpt-5',
    );
    expect(preferredModel(ServiceProtocol.ollama, const [ServiceModel(id: 'qwen3')])!.id, 'qwen3');
    expect(preferredModel(ServiceProtocol.gemini, const []), isNull);
    expect(serviceBrand(ServiceProtocol.openai, 'https://api.openai.com/v1'), ServiceBrand.openai);
    expect(serviceBrand(ServiceProtocol.openai, 'https://proxy.example/v1'), ServiceBrand.compatible);
    expect(serviceBrand(ServiceProtocol.gemini, ''), ServiceBrand.gemini);
    expect(serviceBrand(ServiceProtocol.anthropic, ''), ServiceBrand.anthropic);
    expect(serviceBrand(ServiceProtocol.ollama, ''), ServiceBrand.ollama);
    expect(SettingsTab.values, hasLength(5));
  });

  testWidgets('service marks render on light and dark tiles', (tester) async {
    for (final brand in ServiceBrand.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: MMTheme.dark(),
          home: Center(
            child: ServiceLogo(brand: brand, name: 'squirrel', size: 40),
          ),
        ),
      );
      expect(find.byKey(ValueKey('service-logo-${brand.name}')), findsOneWidget);
      // A compatible service shows its monogram.
      expect(find.text('S'), brand == ServiceBrand.compatible ? findsOneWidget : findsNothing);
    }
  });
}
