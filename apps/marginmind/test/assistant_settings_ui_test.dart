import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/assistant/settings/web_search_settings.dart';
import 'package:marginmind/features/assistant/widgets/service_logo.dart';
import 'package:marginmind/settings/settings_window.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import 'assistant_support.dart';
import 'assistant_services_test.dart' show RecordingServicesStore;
import 'helpers.dart' show doubleTap, settleHud;

/// Opens the panel, then the shared Settings › Models page.
Future<void> _openModels(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('toolbar-assistant')));
  await tester.pumpAndSettle();
  await openAssistantModelSettings(tester);
  expect(find.byKey(const ValueKey('settings-models')), findsOneWidget);
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(EditableText)), text);
  await tester.pump();
}

/// Saves the visible model or search form and waits for validation.
Future<void> _save(WidgetTester tester) async {
  final service = find.byKey(const ValueKey('service-save'));
  final search = find.byKey(const ValueKey('search-save'));
  final target = service.evaluate().isNotEmpty ? service : search;
  await tester.ensureVisible(target);
  await tester.tap(target);
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

class DelayedKeyStore extends FakeSecrets {
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> write(String account, String key) async {
    if (!started.isCompleted) started.complete();
    await release.future;
    await super.write(account, key);
  }
}

class DelayedCheckCatalog extends FakeCatalog {
  final result = Completer<ConnectionStatus>();
  @override
  Future<ConnectionStatus> check(AssistantService service, String key, {CancellationToken? cancellation}) =>
      result.future;
}

void main() {
  testWidgets('a check from the previous save cannot label new edits as an invalid key', (tester) async {
    final catalog = DelayedCheckCatalog();
    await openAssistantApp(tester, catalog: catalog);
    await _openModels(tester);
    await tester.tap(find.byKey(const ValueKey('service-header-legacy-claude')));
    await tester.pumpAndSettle();
    await _enter(tester, 'service-key', 'first-key');
    await tester.tap(find.byKey(const ValueKey('service-save')));
    await tester.pump();
    await _enter(tester, 'service-key', 'new-draft');
    catalog.result.complete(ConnectionStatus.authFailed);
    await tester.pumpAndSettle();
    expect(find.text('API Key 无效'), findsNothing);
    expect(find.text('未保存'), findsOneWidget);
  });

  testWidgets('a write that cannot be read back never says saved or enables search', (tester) async {
    final secrets = UnreadableAfterWriteSecrets(), catalog = FakeCatalog();
    final app = await openAssistantApp(tester, secretStore: secrets, catalog: catalog);
    await _openModels(tester);
    await tester.tap(find.byKey(const ValueKey('service-header-legacy-claude')));
    await tester.pumpAndSettle();
    await _enter(tester, 'service-key', 'unreadable-key');
    await _save(tester);
    expect(find.text('保存失败，请重试'), findsOneWidget);
    expect(find.text('已保存'), findsNothing);
    expect(catalog.checked, isEmpty);
    await tester.tap(find.byKey(const ValueKey('settings-tab-webSearch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('search-backend')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tavily').last);
    await tester.pumpAndSettle();
    await _enter(tester, 'search-key', 'unreadable-search-key');
    await _save(tester);
    expect(find.text('已保存'), findsNothing);
    expect(app.container.read(webSearchSettingsProvider).backend, WebSearchBackend.none);
  });

  testWidgets('model listing waits for an in-flight key save', (tester) async {
    final secrets = DelayedKeyStore(), catalog = FakeCatalog();
    await openAssistantApp(tester, secretStore: secrets, catalog: catalog);
    await _openModels(tester);
    await tester.tap(find.byKey(const ValueKey('service-header-legacy-claude')));
    await tester.pumpAndSettle();
    await _enter(tester, 'service-key', 'replacement-key');
    await tester.tap(find.byKey(const ValueKey('service-save')));
    await tester.pump();
    expect(secrets.started.isCompleted, isTrue);
    expect(tester.widget<MMIconButton>(find.byKey(const ValueKey('service-add-model'))).onPressed, isNull);
    expect(catalog.listed, isEmpty);
    expect(find.text('正在保存…'), findsOneWidget);
    secrets.release.complete();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('service-add-model')));
    await tester.pumpAndSettle();
    expect(catalog.listed.single.$2, 'replacement-key');
  });

  testWidgets('failed settings key save prevents fetching and offers retry with the draft', (tester) async {
    final secrets = UnavailableKeyStore()..blockReads = false;
    final catalog = FakeCatalog();
    final app = await openAssistantApp(tester, secretStore: secrets, catalog: catalog);
    await _openModels(tester);
    await tester.tap(find.byKey(const ValueKey('service-header-legacy-claude')));
    await tester.pumpAndSettle();
    await _enter(tester, 'service-key', 'replacement-key');
    await tester.tap(find.byKey(const ValueKey('service-save')));
    await tester.pumpAndSettle();
    expect(catalog.listed, isEmpty);
    expect(find.byKey(const ValueKey('add-models')), findsNothing);
    expect(find.text('API Key 无效'), findsNothing);
    expect(find.text('保存失败，请重试'), findsOneWidget);
    secrets.blockWrites = false;
    await tester.tap(find.byKey(const ValueKey('service-save')));
    await tester.pumpAndSettle();
    expect(find.text('已保存'), findsOneWidget);
    expect(app.secrets.values[AssistantServicesStore.account('legacy-claude')], 'replacement-key');
    await tester.tap(find.byKey(const ValueKey('service-add-model')));
    await tester.pumpAndSettle();
    expect(catalog.listed.single.$2, 'replacement-key');
  });

  testWidgets('service edits stay unsaved until Save, and fetching uses the saved key and address', (tester) async {
    final catalog = FakeCatalog();
    final app = await openAssistantApp(tester, catalog: catalog);
    await _openModels(tester);
    await tester.tap(find.byKey(const ValueKey('service-header-legacy-claude')));
    await tester.pumpAndSettle();
    await _enter(tester, 'service-endpoint', 'https://proxy.example');
    await _enter(tester, 'service-key', 'replacement-key');
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('未保存'), findsOneWidget);
    expect(catalog.checked, isEmpty);
    expect(app.secrets.values[AssistantServicesStore.account('legacy-claude')], isNull);
    expect(tester.widget<MMIconButton>(find.byKey(const ValueKey('service-add-model'))).onPressed, isNull);
    await _save(tester);
    await tester.tap(find.byKey(const ValueKey('service-add-model')));
    await tester.pumpAndSettle();
    expect(catalog.listed.single, ('https://proxy.example', 'replacement-key'));
    expect(app.secrets.values[AssistantServicesStore.account('legacy-claude')], 'replacement-key');
  });

  testWidgets('Save commits all fields together; closing discards unsaved model drafts', (tester) async {
    final app = await openAssistantApp(tester);
    await _openModels(tester);
    await tester.tap(find.byKey(const ValueKey('service-header-legacy-claude')));
    await tester.pumpAndSettle();
    await _enter(tester, 'service-key', 'replacement-key');
    await _enter(tester, 'service-name', 'Renamed');
    await _save(tester);
    expect(app.secrets.values[AssistantServicesStore.account('legacy-claude')], 'replacement-key');
    expect(_services(app).services.first.name, 'Renamed');
    await _enter(tester, 'service-key', 'last-key');
    await tester.tap(find.byKey(const ValueKey('settings-close')));
    await tester.pumpAndSettle();
    expect(app.secrets.values[AssistantServicesStore.account('legacy-claude')], 'replacement-key');
    final reloaded = await app.container.read(assistantServicesStoreProvider).load();
    expect(reloaded.services.first.name, 'Renamed');
  }, semanticsEnabled: false);

  testWidgets('an unreadable key directs users to replace and save it, without read-retry buttons', (tester) async {
    final secrets = UnavailableKeyStore()..blockWrites = false;
    final catalog = FakeCatalog();
    final app = await openAssistantApp(tester, secretStore: secrets, catalog: catalog);
    await _openModels(tester);
    await tester.tap(find.byKey(const ValueKey('service-header-legacy-claude')));
    await tester.pumpAndSettle();
    expect(find.text('无法读取 API Key，请重新填写并保存。'), findsOneWidget);
    expect(find.byKey(const ValueKey('service-key-retry')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('service-add-model')));
    await tester.pumpAndSettle();
    expect(find.text('API Key 无效'), findsNothing);
    expect(find.byKey(const ValueKey('add-model-key-retry')), findsNothing);
    expect(catalog.listed, isEmpty);
    // Return to the service form and make the change that enables recovery.
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    secrets.blockReads = false;
    await _enter(tester, 'service-key', 'replacement-key');
    await _save(tester);
    expect(app.secrets.values[AssistantServicesStore.account('legacy-claude')], 'replacement-key');
    await tester.tap(find.byKey(const ValueKey('service-add-model')));
    await tester.pumpAndSettle();
    expect(catalog.listed.single.$2, 'replacement-key');
    expect(find.text('Claude Sonnet'), findsOneWidget);
  });

  testWidgets('credential recovery opens Model Settings and uses its save flow', (tester) async {
    final secrets = UnavailableKeyStore(), catalog = FakeCatalog();
    final app = await openAssistantApp(tester, key: false, secretStore: secrets, catalog: catalog);
    await tester.tap(find.byKey(const ValueKey('toolbar-assistant')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('connect-key')), findsNothing);
    expect(find.byKey(const ValueKey('connect-anthropic')), findsNothing);
    expect(catalog.checked, isEmpty);
    await tester.tap(find.byKey(const ValueKey('assistant-configure-models')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-models')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-general')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('service-header-legacy-claude')));
    await tester.pumpAndSettle();
    await _enter(tester, 'service-key', 'valid-test-key');
    await _save(tester);
    expect(find.textContaining('暂时无法保存 API Key'), findsOneWidget);
    expect(find.text('API Key 无效'), findsNothing);
    expect(await app.container.read(assistantConfiguredProvider.future), isFalse);
    expect(secrets.values, isEmpty);
    secrets
      ..blockReads = false
      ..blockWrites = false;
    await _save(tester);
    expect(catalog.checked.single.$2, 'valid-test-key');
    expect(await app.container.read(assistantConfiguredProvider.future), isTrue);
    expect(secrets.values[AssistantServicesStore.account('legacy-claude')], 'valid-test-key');
    await tester.tap(find.byKey(const ValueKey('settings-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('assistant-connect')), findsNothing);
    expect(find.byKey(const ValueKey('assistant-suggestions')), findsOneWidget);
  }, semanticsEnabled: false);

  testWidgets('the settings link keeps the selected service when providers are shared', (tester) async {
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
    await tester.tap(find.byKey(const ValueKey('assistant-configure-models')));
    await tester.pumpAndSettle();
    secrets
      ..blockReads = false
      ..blockWrites = false;
    await tester.tap(find.byKey(const ValueKey('service-header-selected')));
    await tester.pumpAndSettle();
    await _enter(tester, 'service-key', 'replacement-test-key');
    await _save(tester);
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
    final addModel = find.byKey(const ValueKey('service-add-model'));
    final modelHeading = find.byKey(const ValueKey('service-models-heading'));
    expect(tester.getCenter(addModel).dy, closeTo(tester.getCenter(modelHeading).dy, 1));
    expect(tester.getRect(addModel).left, greaterThanOrEqualTo(tester.getRect(modelHeading).right));
    expect(tester.widget<MMIconButton>(find.byKey(const ValueKey('service-remove'))).icon, MMIcons.trash);

    await _enter(tester, 'service-key', 'sk-test');
    expect(catalog.checked, isEmpty); // Only after Save.
    await _save(tester);
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

  testWidgets('a service card: failure reason, hidden key, address, rename, remove model, off, remove', (tester) async {
    final catalog = FakeCatalog(status: ConnectionStatus.authFailed);
    final app = await openAssistantApp(tester, catalog: catalog);
    await _openModels(tester);
    // Anthropic hides its address until asked.
    await tester.tap(find.byKey(const ValueKey('settings-add-service')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('service-option-anthropic')));
    await tester.pumpAndSettle();
    final id = _services(app).services.last.id;
    expect(find.bySemanticsLabel('移除服务'), findsOneWidget);
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
    expect(find.byKey(const ValueKey('service-reveal')), findsNothing);
    await _save(tester);
    // Failure shows on the card's second line; there is no check button.
    expect(find.byKey(const ValueKey('service-failure')), findsOneWidget);
    expect(find.text('API Key 无效'), findsOneWidget);
    expect(_services(app).services.last.endpoint, 'https://proxy.example');
    catalog.status = ConnectionStatus.unreachable;
    await _enter(tester, 'service-key', 'other');
    await _save(tester);
    expect(find.text('连不上服务'), findsOneWidget);
    // Clearing the key stops checking and clears the reason.
    await _enter(tester, 'service-key', '');
    await _save(tester);
    expect(find.byKey(const ValueKey('service-failure')), findsNothing);

    // Rename the service.
    await _enter(tester, 'service-name', '我的代理');
    await _save(tester);
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
    expect(app.container.read(webSearchSettingsProvider).backend, WebSearchBackend.none);
    await _enter(tester, 'search-endpoint', 'http://localhost:8080');
    await _save(tester);
    expect(checks, hasLength(1));
    expect(app.container.read(webSearchSettingsProvider).endpoint, 'http://localhost:8080');
    expect(find.text('连不上搜索服务'), findsOneWidget);

    await choose('Cloudflare');
    expect(find.text('账户 ID'), findsOneWidget);
    expect(find.text('API Token'), findsOneWidget);
    await _enter(tester, 'search-key', 'token');
    await _save(tester);
    expect(checks, hasLength(1)); // The account is still missing.
    status = ConnectionStatus.authFailed;
    await _enter(tester, 'search-account', 'acct');
    await _save(tester);
    expect(checks, hasLength(2));
    expect(find.text('API Token 无效'), findsOneWidget);
    expect(app.secrets.values[WebSearchSettingsController.cloudflareAccount], 'acct');
    expect(app.secrets.values[WebSearchSettingsController.account(WebSearchBackend.cloudflare)], 'token');

    await choose('Tavily');
    expect(find.text('API Token 无效'), findsNothing);
    status = ConnectionStatus.ok;
    await _enter(tester, 'search-key', 'tvly');
    await _save(tester);
    expect(find.byKey(const ValueKey('search-failure')), findsNothing);
    expect(app.secrets.values[WebSearchSettingsController.account(WebSearchBackend.tavily)], 'tvly');

    await choose('Brave Search');
    status = ConnectionStatus.authFailed;
    await _enter(tester, 'search-key', 'brave');
    await _save(tester);
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
    await _save(tester);
    expect(find.byKey(const ValueKey('search-unavailable')), findsNothing);
    expect(find.textContaining('不带搜索'), findsNothing);
    expect(app.container.read(webSearchSettingsProvider).backend, WebSearchBackend.none);
  });

  testWidgets('an unconfigured assistant routes to models and updates after setup', (tester) async {
    final catalog = FakeCatalog(
      models: const [
        ServiceModel(id: 'gpt-5'),
        ServiceModel(id: 'gpt-5-mini'),
      ],
    );
    final app = await openAssistantApp(
      tester,
      key: false,
      catalog: catalog,
      prefs: {AssistantServicesStore.settingsKey: jsonEncode(AssistantServices().toJson())},
    );
    await tester.tap(find.byKey(const ValueKey('toolbar-assistant')));
    await tester.pumpAndSettle();
    expect(find.text('添加模型后即可使用'), findsOneWidget);
    expect(find.byKey(const ValueKey('assistant-input')), findsNothing);
    expect(find.byKey(const ValueKey('connect-key')), findsNothing);
    expect(find.byKey(const ValueKey('connect-button')), findsNothing);
    expect(find.byKey(const ValueKey('quick-explain')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('assistant-configure-models')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-models')), findsOneWidget);
    expect(catalog.checked, isEmpty);
    await tester.tap(find.byKey(const ValueKey('settings-add-service')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('service-option-openai')));
    await tester.pumpAndSettle();
    await _enter(tester, 'service-key', 'key');
    await _save(tester);
    expect(await app.container.read(assistantConfiguredProvider.future), isFalse);
    await tester.tap(find.byKey(const ValueKey('service-add-model')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-model-gpt-5')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('add-models-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('assistant-connect')), findsNothing);
    expect(find.byKey(const ValueKey('assistant-suggestions')), findsOneWidget);
    expect(conversationOf(tester).model.model, 'gpt-5');
    expect(_services(app).defaultModel!.modelId, 'gpt-5');
  }, semanticsEnabled: false);

  test('service marks', () {
    expect(serviceBrand(ServiceProtocol.openai, 'https://api.openai.com/v1'), ServiceBrand.openai);
    expect(serviceBrand(ServiceProtocol.openai, 'https://proxy.example/v1'), ServiceBrand.compatible);
    expect(serviceBrand(ServiceProtocol.gemini, ''), ServiceBrand.gemini);
    expect(serviceBrand(ServiceProtocol.anthropic, ''), ServiceBrand.anthropic);
    expect(serviceBrand(ServiceProtocol.ollama, ''), ServiceBrand.ollama);
    expect(SettingsTab.values, hasLength(6));
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
