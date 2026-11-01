import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart' show phoneProvider, touchPlatformProvider;
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/assistant/assistant_routing.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/assistant/settings/ai_routing_usage.dart';
import 'package:marginmind/features/assistant/settings/ai_task_settings.dart';
import 'package:marginmind/features/assistant/settings/ai_task_status.dart';
import 'package:marginmind/features/assistant/settings/model_route_picker.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:marginmind/l10n/generated/app_localizations_zh.dart';
import 'package:marginmind/settings/settings_window.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'assistant_support.dart' show FakeSecrets;
import 'helpers.dart';

final _anthropic = AssistantService(
  id: 'anthropic',
  protocol: ServiceProtocol.anthropic,
  name: 'Anthropic',
  endpoint: 'https://api.anthropic.com',
  models: const [
    ServiceModel(id: 'haiku', name: 'Claude Haiku'),
    ServiceModel(id: 'opus', name: 'Claude Opus'),
  ],
);
final _proxy = AssistantService(
  id: 'proxy',
  protocol: ServiceProtocol.openai,
  name: 'Proxy',
  endpoint: 'https://proxy.test/v1',
  models: const [ServiceModel(id: 'opus-proxy', name: 'Claude Opus')],
);
const _haiku = ModelReference('anthropic', 'haiku');
const _opus = ModelReference('anthropic', 'opus');
const _proxyOpus = ModelReference('proxy', 'opus-proxy');

class _UsageIndex implements AiRoutingUsageIndex {
  _UsageIndex(this.uses, {this.fail = false});
  final List<RoutingUse> uses;
  final bool fail;
  @override
  Future<List<RoutingUse>> listModelUses() async {
    if (fail) throw StateError('index unreadable');
    return uses;
  }

  @override
  (TaskType, String)? run(String runId) => runId == 'run-1' ? (TaskType.documentTranslate, 'Deep Work') : null;
}

class _Probe extends RoutingCapabilityProbe {
  _Probe(TaskModelResolver resolver) : super(resolver: resolver, key: (_) async => 'k');
  final calls = <ModelReference>[];
  final result = Completer<void>();
  @override
  Future<CapabilityProbeResult> probe(
    ModelReference reference, {
    required CancellationToken cancellation,
    ReasoningPolicy reasoning = ReasoningPolicy.auto,
  }) async {
    calls.add(reference);
    await cancellation.bind(result.future);
    final catalog = await resolver.catalog();
    final service = catalog.services.firstWhere((s) => s.id == reference.serviceId);
    final identity = serviceCapabilityIdentity(service, service.models.firstWhere((m) => m.id == reference.modelId));
    return CapabilityProbeResult(
      identity: identity,
      accepted: true,
      profile: ModelCapabilityProfile(identity: identity),
    );
  }
}

/// Production-shaped registry whose reads can fail on demand.
class _FlakyProfiles extends CapabilityProfiles {
  bool fail = false;
  @override
  Future<void> refresh() async {
    if (fail) throw StateError('capability store unavailable');
  }
}

class _UnsavedProbe extends RoutingCapabilityProbe {
  _UnsavedProbe(TaskModelResolver resolver) : super(resolver: resolver, key: (_) async => 'k');
  @override
  Future<CapabilityProbeResult> probe(
    ModelReference reference, {
    required CancellationToken cancellation,
    ReasoningPolicy reasoning = ReasoningPolicy.auto,
  }) async => throw StateError('Capability persistence failed');
}

/// An exact model/endpoint pair from the reviewed production allowlist.
final _openai = AssistantService(
  id: 'openai',
  protocol: ServiceProtocol.openai,
  name: 'OpenAI',
  endpoint: 'https://api.openai.com/v1',
  models: const [ServiceModel(id: 'gpt-4.1-2025-04-14', name: 'GPT-4.1')],
);

class _UnreadableSecrets extends FakeSecrets {
  @override
  Future<String?> read(String name) async =>
      throw const ResearchFailure(ResearchFailureKind.authentication, 'secret_store');
}

Map<String, Object> _prefs({List<AssistantService>? services, Map<String, dynamic>? routing}) {
  final list = services ?? [_anthropic, _proxy];
  return {
    'settings.language': 'zh',
    AssistantServicesStore.settingsKey: jsonEncode(
      AssistantServices(services: list, defaultModel: list.isEmpty ? null : _haiku).toJson(),
    ),
    if (routing != null) AssistantRoutingStore.settingsKey: jsonEncode(routing),
  };
}

Map<String, dynamic> _routing({
  Map<String, dynamic>? quick = const {'serviceId': 'anthropic', 'modelId': 'haiku'},
  Map<String, dynamic>? heavy = const {'serviceId': 'anthropic', 'modelId': 'opus'},
  Map<String, dynamic> bindings = const {},
  int revision = 3,
}) => {
  'version': 1,
  'revision': revision,
  'defaults': {'quick': ?quick, 'heavy': ?heavy},
  'bindings': bindings,
  'heavyReasoning': 'auto',
};

CapabilityEvidence _evidence() => CapabilityEvidence(
  source: CapabilityEvidenceSource.officialMetadata,
  reference: 'fixture',
  verifiedAt: DateTime(2026),
  semanticBasis: 'fixture',
  wireVerified: true,
);

FakeSecrets _keys() => FakeSecrets()
  ..values[AssistantServicesStore.account('anthropic')] = 'a'
  ..values[AssistantServicesStore.account('proxy')] = 'p';

Future<ProviderContainer> _open(
  WidgetTester tester, {
  Map<String, Object>? prefs,
  FakeSecrets? secrets,
  List<Override> overrides = const [],
  SettingsTab tab = SettingsTab.aiTasks,
  AiTaskFocus? focus,
  Size size = const Size(1280, 820),
}) async {
  final container = await pumpApp(
    tester,
    prefs: prefs ?? _prefs(routing: _routing()),
    size: size,
    overrides: [assistantSecretsProvider.overrideWithValue(secrets ?? _keys()), ...overrides],
  );
  showSettings(tester.element(find.byType(MMWindowScaffold)), tab: tab, focus: focus);
  await tester.pumpAndSettle();
  return container;
}

Finder _row(String id) => find.byWidgetPredicate((w) => w is ModelRoutePicker && w.semanticLabel == id);
ModelRoutePicker _pickerOf(WidgetTester tester, String semanticLabel) =>
    tester.widget<ModelRoutePicker>(_row(semanticLabel));

Future<void> _choose(WidgetTester tester, String row, String item, {int index = 0}) async {
  await tester.ensureVisible(_row(row));
  await tester.pumpAndSettle();
  await tester.tap(_row(row));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).hitTestable().at(index));
  await tester.pumpAndSettle();
}

RoutingConfig _stored(ProviderContainer container) => RoutingConfig(
  document: Map<String, dynamic>.from(
    jsonDecode(container.read(sharedPreferencesProvider).getString(AssistantRoutingStore.settingsKey)!) as Map,
  ),
);

void main() {
  final l = AppLocalizationsZh();

  group('routeModelLabel', () {
    test('adds the service only when the display name is ambiguous', () {
      final catalog = AssistantServices(services: [_anthropic, _proxy]);
      expect(routeModelLabel(catalog, _haiku), 'Claude Haiku');
      expect(routeModelLabel(catalog, _opus), 'Anthropic · Claude Opus');
      expect(routeModelLabel(catalog, _proxyOpus), 'Proxy · Claude Opus');
      // Deleted: the snapshot, else the IDs; never a guessed same-name model.
      expect(
        routeModelLabel(catalog, const ModelReference('gone', 'x'), serviceLabel: 'Old', modelLabel: 'Sonnet'),
        'Sonnet',
      );
      expect(routeModelLabel(catalog, const ModelReference('gone', 'x')), 'x');
      expect(routeModelNames(catalog, const ModelReference('gone', 'x')), ('gone', 'x'));
    });
  });

  group('AiTaskDraft', () {
    test('keeps unknown keys and unchanged snapshots; dirty only on real changes', () async {
      final base = RoutingConfig(
        document: {
          ..._routing(
            quick: {'serviceId': 'anthropic', 'modelId': 'haiku', 'modelLabel': 'Old Haiku'},
            bindings: {
              'future_task': {'mode': 'explicit', 'model': _opus.toJson()},
              'research': {'mode': 'explicit', 'model': _opus.toJson(), 'reasoning': 'deep'},
            },
          ),
          'extra': {'kept': true},
        },
      );
      final draft = AiTaskDraft()..adopt(base);
      expect(draft.dirty, isFalse);
      expect(draft.binding(TaskType.research).reasoning, ReasoningPolicy.deep);
      draft.setBinding(TaskType.research, const TaskModelBinding.inherit());
      draft.setBinding(TaskType.titleGenerate, const TaskModelBinding.explicit(_proxyOpus));
      expect(draft.dirty, isTrue);
      final doc = draft.toConfig().document;
      expect(doc['extra'], {'kept': true});
      expect((doc['defaults'] as Map)['quick']['modelLabel'], 'Old Haiku');
      expect((doc['bindings'] as Map).keys, containsAll(['future_task', 'title_generate']));
      expect((doc['bindings'] as Map).containsKey('research'), isFalse);
      expect(draft.toConfig(bindings: false).document['bindings'], isEmpty);
      draft.setBinding(TaskType.titleGenerate, const TaskModelBinding.inherit());
      draft.setBinding(TaskType.research, const TaskModelBinding.explicit(_opus, reasoning: ReasoningPolicy.deep));
      expect(draft.dirty, isFalse);

      // A newer stored value does not replace pending edits.
      draft.setDefault(TaskCategory.heavy, _proxyOpus);
      draft.adopt(RoutingConfig(document: _routing(revision: 9)));
      expect(draft.base!.revision, 3);
      expect(await draft.save((_, expected) async => throw RoutingRevisionConflict(expected, 9)), isFalse);
      expect(draft.state, AiTaskSaveState.conflict);
      expect(draft.defaultModel(TaskCategory.heavy), _proxyOpus, reason: 'the draft is kept');
      draft.reload(RoutingConfig(document: _routing(revision: 9)));
      expect((draft.dirty, draft.state, draft.base!.revision), (false, AiTaskSaveState.idle, 9));
    });
  });

  group('settings › AI features', () {
    testWidgets('lists both classes and all twelve features; inherited rows show the effective model', (tester) async {
      await _open(tester);
      expect(find.text('AI 功能'), findsWidgets);
      expect(find.text('快速任务'), findsOneWidget);
      expect(find.text('重型任务'), findsOneWidget);
      for (final type in TaskType.values) {
        expect(_row(aiTaskName(l, type)), findsOneWidget, reason: type.key);
      }
      final chat = _pickerOf(tester, aiTaskName(l, TaskType.assistantChat));
      expect((chat.label, chat.tone), ('Anthropic · Claude Opus', ModelRouteTone.inherited));
      expect(chat.semanticValue, '跟随默认，Anthropic · Claude Opus');
      expect(chat.tooltip, 'Anthropic · opus');
      expect(_pickerOf(tester, aiTaskName(l, TaskType.wordLookup)).label, 'Claude Haiku');
      // Quick thinking is fixed; heavy thinking offers only Auto while capabilities are unknown.
      expect(
        find.descendant(of: find.byKey(const ValueKey('ai-tasks-quick-thinking')), matching: find.text('关闭')),
        findsOneWidget,
      );
      expect(
        tester.widget<MMPopUpButton<ReasoningPolicy>>(find.byKey(const ValueKey('ai-tasks-heavy-reasoning'))).items,
        [(ReasoningPolicy.auto, '自动')],
      );
      // Unknown capabilities are said once, on each default row, never per inheriting feature.
      expect(find.text('需验证兼容性'), findsNWidgets(2));
      expect(find.text('跟随默认'), findsNothing);
      expect(find.text('未保存'), findsNothing);
      expect(tester.widget<MMButton>(find.byKey(const ValueKey('ai-tasks-save'))).onPressed, isNull);
    });

    testWidgets('binding a feature drafts, saves with the read revision and mirrors the heavy default', (tester) async {
      final container = await _open(tester);
      final name = aiTaskName(l, TaskType.titleGenerate);
      await tester.tap(_row(name));
      await tester.pumpAndSettle();
      // The menu: follow (with the effective model), then models grouped by service.
      expect(find.text('跟随默认'), findsOneWidget);
      expect(find.text('Proxy'), findsWidgets);
      expect(find.text('需验证'), findsNWidgets(3));
      await tester.tap(find.text('Claude Opus').hitTestable().last);
      await tester.pumpAndSettle();
      final picker = _pickerOf(tester, name);
      expect(
        (picker.label, picker.tone, picker.selected),
        ('Proxy · Claude Opus', ModelRouteTone.explicit, _proxyOpus),
      );
      expect(find.text('未保存'), findsOneWidget);
      expect(_stored(container).binding(TaskType.titleGenerate).mode, TaskBindingMode.inherit, reason: 'draft only');

      await _choose(tester, '重型任务 · 默认模型', 'Claude Haiku');
      expect(_pickerOf(tester, aiTaskName(l, TaskType.research)).label, 'Claude Haiku', reason: 'inherits the draft');
      await tester.tap(find.byKey(const ValueKey('ai-tasks-save')));
      await tester.pumpAndSettle();
      final stored = _stored(container);
      expect(stored.revision, 4);
      expect(stored.binding(TaskType.titleGenerate).model, _proxyOpus);
      expect((stored.document['bindings'] as Map)['title_generate']['model']['serviceLabel'], 'Proxy');
      expect(stored.defaultModel(TaskCategory.heavy), _haiku);
      expect(container.read(assistantServicesProvider).value!.defaultModel, _haiku);
      expect(find.text('已保存'), findsOneWidget);

      // Reset returns every feature to its default without saving.
      await tester.tap(find.byKey(const ValueKey('ai-tasks-reset')));
      await tester.pumpAndSettle();
      expect(_pickerOf(tester, name).tone, ModelRouteTone.inherited);
      expect(find.text('未保存'), findsOneWidget);
      // ⌘S / Ctrl+S saves.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(_stored(container).binding(TaskType.titleGenerate).mode, TaskBindingMode.inherit);
      await settleHud(tester);
    });

    testWidgets('heavy features take a thinking choice only for a verified explicit model', (tester) async {
      final profiles = CapabilityProfiles();
      final container = await _open(
        tester,
        overrides: [assistantCapabilityProfilesProvider.overrideWithValue(profiles)],
      );
      final proxy = container.read(assistantServicesProvider).value!.services.last;
      profiles.put(
        ModelCapabilityProfile(
          identity: serviceCapabilityIdentity(proxy, proxy.models.single),
          thinking: ThinkingCapability.switchable,
          policies: const {
            ReasoningPolicy.off: ReasoningRecipe.effortNone,
            ReasoningPolicy.deep: ReasoningRecipe.effortHigh,
          },
          evidence: _evidence(),
        ),
      );
      final research = aiTaskName(l, TaskType.research);
      // Anthropic Opus is unverified: no thinking section for it.
      await _choose(tester, research, 'Claude Opus');
      await tester.tap(_row(research));
      await tester.pumpAndSettle();
      expect(find.text('深入'), findsNothing);
      await tester.tap(find.text('Claude Opus').hitTestable().last);
      await tester.pumpAndSettle();
      expect(_pickerOf(tester, research).selected, _proxyOpus);
      await tester.tap(_row(research));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('深入'));
      await tester.pumpAndSettle();
      expect(find.text('标准'), findsNothing, reason: 'the profile cannot compile it');
      await tester.tap(find.text('深入').hitTestable());
      await tester.pumpAndSettle();
      expect(_pickerOf(tester, research).reasoning, ReasoningPolicy.deep);
      // The heavy default offers what its profile compiles: Auto alone for unverified Anthropic Opus.
      Iterable<ReasoningPolicy> heavyChoices() => tester
          .widget<MMPopUpButton<ReasoningPolicy>>(find.byKey(const ValueKey('ai-tasks-heavy-reasoning')))
          .items
          .map((e) => e.$1);
      expect(heavyChoices(), [ReasoningPolicy.auto]);
      await _choose(tester, '重型任务 · 默认模型', 'Claude Opus', index: 1);
      expect(heavyChoices(), [ReasoningPolicy.auto, ReasoningPolicy.off, ReasoningPolicy.deep]);
      await tester.tap(find.byKey(const ValueKey('ai-tasks-save')));
      await tester.pumpAndSettle();
      final stored = _stored(container);
      expect(stored.binding(TaskType.research).reasoning, ReasoningPolicy.deep);
      expect(stored.defaultModel(TaskCategory.heavy), _proxyOpus);
      await settleHud(tester);
    });

    testWidgets('a quick model that cannot turn off thinking is disabled and flagged', (tester) async {
      final profiles = CapabilityProfiles();
      final container = await _open(
        tester,
        overrides: [assistantCapabilityProfilesProvider.overrideWithValue(profiles)],
      );
      final service = container.read(assistantServicesProvider).value!.services.first;
      profiles.put(
        ModelCapabilityProfile(
          identity: serviceCapabilityIdentity(service, service.models.first),
          thinking: ThinkingCapability.alwaysOn,
          evidence: _evidence(),
        ),
      );
      // Re-inspect against the new profile.
      await _choose(tester, aiTaskName(l, TaskType.titleGenerate), 'Claude Opus');
      expect(
        find.descendant(of: find.byKey(const ValueKey('ai-tasks-quick-thinking')), matching: find.text('此模型无法关闭思考')),
        findsOneWidget,
      );
      expect(_pickerOf(tester, aiTaskName(l, TaskType.wordLookup)).tone, ModelRouteTone.caution);
      expect(_pickerOf(tester, aiTaskName(l, TaskType.titleGenerate)).tone, ModelRouteTone.explicit);
      await tester.ensureVisible(find.text('更换模型'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('更换模型'));
      await tester.pumpAndSettle();
      expect(find.text('无法关闭思考'), findsOneWidget, reason: 'the default picker opened with the reason');
      await tester.tap(find.text('Claude Haiku').hitTestable(), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('无法关闭思考'), findsOneWidget, reason: 'a disabled item does not select');
      await tester.tap(find.text('Claude Opus').hitTestable().first);
      await tester.pumpAndSettle();
      expect(find.text('此模型无法关闭思考'), findsNothing);
      expect(_pickerOf(tester, '快速任务 · 默认模型').selected, _opus);
    });

    testWidgets('invalid references keep their name, never inherit, and stay configurable', (tester) async {
      await _open(
        tester,
        prefs: _prefs(
          services: [_anthropic, _proxy.copyWith(enabled: false)],
          routing: _routing(
            quick: {'serviceId': 'anthropic', 'modelId': 'gone', 'serviceLabel': 'Anthropic', 'modelLabel': 'Sonnet 3'},
            bindings: {
              'title_generate': {'mode': 'explicit', 'model': _haiku.toJson()},
              'research': {'mode': 'explicit', 'model': _proxyOpus.toJson()},
            },
          ),
        ),
      );
      final quick = _pickerOf(tester, '快速任务 · 默认模型');
      expect((quick.label, quick.tone), ('Sonnet 3', ModelRouteTone.invalid));
      expect(quick.semanticValue, 'Anthropic · Sonnet 3，模型已删除');
      expect(find.text('模型已删除'), findsOneWidget);
      expect(find.text('服务已停用'), findsOneWidget);
      final lookup = _pickerOf(tester, aiTaskName(l, TaskType.wordLookup));
      expect((lookup.label, lookup.tone), ('需配置', ModelRouteTone.caution));
      expect(
        _pickerOf(tester, aiTaskName(l, TaskType.titleGenerate)).label,
        'Claude Haiku',
        reason: 'explicit binding',
      );
      final research = tester.widget<Text>(
        find.descendant(of: _row(aiTaskName(l, TaskType.research)), matching: find.text('Proxy · Claude Opus')),
      );
      expect(research.style?.decoration, TextDecoration.lineThrough);
      // “Choose Again” opens that row's menu.
      await tester.tap(find.byKey(const ValueKey('ai-action-default-quick')));
      await tester.pumpAndSettle();
      expect(find.text('Anthropic').hitTestable(), findsOneWidget);
    });

    testWidgets('all models off keeps the page; no models and no routing shows Add Model', (tester) async {
      await _open(
        tester,
        prefs: _prefs(services: [_anthropic.copyWith(enabled: false)], routing: _routing()),
      );
      expect(find.byKey(const ValueKey('ai-tasks-add-model')), findsNothing);
      expect(find.text('服务已停用'), findsNWidgets(2));
      Navigator.of(tester.element(find.byType(SettingsWindow))).pop();
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await prefs.setString('settings.language', 'zh');
      await prefs.setString(AssistantServicesStore.settingsKey, jsonEncode(AssistantServices().toJson()));
      final container = ProviderScope.containerOf(tester.element(find.byType(MMWindowScaffold)));
      container.invalidate(assistantServicesProvider);
      container.invalidate(assistantRoutingProvider);
      showSettings(tester.element(find.byType(MMWindowScaffold)), tab: SettingsTab.aiTasks);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ai-tasks-add-model')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-models')), findsOneWidget);
      expect(find.byKey(const ValueKey('service-list')), findsOneWidget);
    });

    testWidgets('save failure keeps the draft; a newer revision is a conflict that only reloads', (tester) async {
      late _FailingRoutingStore failing;
      final container = await _open(
        tester,
        overrides: [
          assistantRoutingStoreProvider.overrideWith(
            (ref) => failing = _FailingRoutingStore(
              ref.watch(sharedPreferencesProvider),
              ref.watch(assistantServicesStoreProvider),
            ),
          ),
        ],
      );
      final name = aiTaskName(l, TaskType.mapExpand);
      await _choose(tester, name, 'Claude Haiku');
      // Another window saves first.
      final store = container.read(assistantRoutingStoreProvider);
      final other = await store.load();
      await store.save(
        RoutingConfig(document: {...other.document, 'heavyReasoning': 'off'}),
        expectedRevision: other.revision,
      );
      await tester.tap(find.byKey(const ValueKey('ai-tasks-save')));
      await tester.pumpAndSettle();
      expect(find.text('设置已在其他窗口更改'), findsOneWidget);
      expect(tester.widget<MMButton>(find.byKey(const ValueKey('ai-tasks-save'))).onPressed, isNull);
      expect(_stored(container).binding(TaskType.mapExpand).mode, TaskBindingMode.inherit);
      await tester.tap(find.byKey(const ValueKey('ai-tasks-reload')));
      await tester.pumpAndSettle();
      expect(_pickerOf(tester, name).tone, ModelRouteTone.inherited);
      expect(find.text('设置已在其他窗口更改'), findsNothing);

      // A failed write: “Save failed”, the draft stays and Save can retry.
      await _choose(tester, name, 'Claude Haiku');
      failing.fail = true;
      await tester.tap(find.byKey(const ValueKey('ai-tasks-save')));
      await tester.pumpAndSettle();
      expect(find.text('保存失败，请重试'), findsOneWidget);
      expect(_pickerOf(tester, name).tone, ModelRouteTone.explicit);
      expect(_stored(container).binding(TaskType.mapExpand).mode, TaskBindingMode.inherit);
      failing.fail = false;
      await tester.tap(find.byKey(const ValueKey('ai-tasks-save')));
      await tester.pumpAndSettle();
      expect(_stored(container).binding(TaskType.mapExpand).model, _haiku);
    });

    testWidgets('locating a model highlights every row that uses it and focuses the first', (tester) async {
      await _open(tester, focus: const AiTaskFocusModel(_haiku));
      for (final type in TaskType.values.where((t) => t.category == TaskCategory.quick)) {
        expect(_pickerOf(tester, aiTaskName(l, type)).highlighted, isTrue);
      }
      expect(_pickerOf(tester, '快速任务 · 默认模型').highlighted, isTrue);
      expect(_pickerOf(tester, aiTaskName(l, TaskType.research)).highlighted, isFalse);
      expect(_pickerOf(tester, '快速任务 · 默认模型').focusNode!.hasFocus, isTrue);
      await tester.pump(const Duration(milliseconds: 1700));
      await tester.pumpAndSettle();
      expect(_pickerOf(tester, '快速任务 · 默认模型').highlighted, isFalse);
    });

    testWidgets('“Assign…” on a model row opens AI Features located at it', (tester) async {
      await _open(tester, tab: SettingsTab.models);
      await tester.tap(find.byKey(const ValueKey('service-header-anthropic')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-default-model')), findsNothing);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: tester.getCenter(find.byKey(const ValueKey('model-opus'))));
      addTearDown(gesture.removePointer);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('model-set-default-opus')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('model-assign-opus')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-ai-tasks')), findsOneWidget);
      expect(_pickerOf(tester, '重型任务 · 默认模型').highlighted, isTrue);
      expect(_pickerOf(tester, aiTaskName(l, TaskType.research)).highlighted, isTrue);
      await settleHud(tester);
    });

    testWidgets('removing a model in use lists its users; cancel keeps it, confirm leaves rows invalid', (
      tester,
    ) async {
      final container = await _open(
        tester,
        tab: SettingsTab.models,
        prefs: _prefs(
          routing: _routing(
            bindings: {
              'research': {'mode': 'explicit', 'model': _haiku.toJson()},
            },
          ),
        ),
        overrides: [
          aiRoutingUsageIndexProvider.overrideWithValue(
            _UsageIndex(const [
              RoutingUse(RoutingUsageKind.conversationOverride, 'c1', _haiku),
              RoutingUse(RoutingUsageKind.conversationOverride, 'c2', _haiku),
              RoutingUse(RoutingUsageKind.recoverableRun, 'run-1', _haiku),
              RoutingUse(RoutingUsageKind.recoverableRun, 'run-2', _opus),
            ]),
          ),
        ],
      );
      await tester.tap(find.byKey(const ValueKey('service-header-anthropic')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('model-remove-haiku')));
      await tester.pumpAndSettle();
      expect(find.text('移除“Claude Haiku”？'), findsOneWidget);
      for (final line in ['快速任务默认模型', '调研与查证', '全文翻译 · Deep Work', '2 个对话']) {
        expect(
          find.descendant(of: find.byKey(const ValueKey('routed-usage')), matching: find.text(line)),
          findsOneWidget,
        );
      }
      expect(find.text('重型任务默认模型'), findsNothing);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(container.read(assistantServicesProvider).value!.services.first.models.length, 2);

      await tester.tap(find.byKey(const ValueKey('model-remove-haiku')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('routed-remove-confirm')));
      await tester.pumpAndSettle();
      expect(container.read(assistantServicesProvider).value!.services.first.models.map((m) => m.id), ['opus']);
      await tester.tap(find.byKey(const ValueKey('settings-tab-aiTasks')));
      await tester.pumpAndSettle();
      expect(_pickerOf(tester, '快速任务 · 默认模型').tone, ModelRouteTone.invalid);
      expect(_pickerOf(tester, aiTaskName(l, TaskType.research)).tone, ModelRouteTone.invalid);
      expect(_stored(container).defaultModel(TaskCategory.quick), _haiku, reason: 'never reassigned');
    });

    testWidgets('an unused model is removed directly; an unreadable index still asks', (tester) async {
      final container = await _open(
        tester,
        tab: SettingsTab.models,
        overrides: [aiRoutingUsageIndexProvider.overrideWithValue(_UsageIndex(const [], fail: true))],
      );
      await tester.tap(find.byKey(const ValueKey('service-header-proxy')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('model-remove-opus-proxy')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('routed-usage-unavailable')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('routed-remove-confirm')));
      await tester.pumpAndSettle();
      expect(container.read(assistantServicesProvider).value!.services.last.models, isEmpty);
    });

    testWidgets('closing with unsaved changes asks; Save persists, Don’t Save discards', (tester) async {
      final container = await _open(tester);
      await _choose(tester, aiTaskName(l, TaskType.studyNotes), 'Claude Haiku');
      // Switching sections keeps the draft.
      await tester.tap(find.byKey(const ValueKey('settings-tab-general')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-tab-aiTasks')));
      await tester.pumpAndSettle();
      expect(_pickerOf(tester, aiTaskName(l, TaskType.studyNotes)).tone, ModelRouteTone.explicit);
      await tester.tap(find.byKey(const ValueKey('settings-close')));
      await tester.pumpAndSettle();
      expect(find.text('保存对 AI 功能的更改？'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ai-tasks-close-save')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsWindow), findsNothing);
      expect(_stored(container).binding(TaskType.studyNotes).model, _haiku);

      showSettings(tester.element(find.byType(MMWindowScaffold)), tab: SettingsTab.aiTasks);
      await tester.pumpAndSettle();
      await _choose(tester, aiTaskName(l, TaskType.studyNotes), '跟随默认');
      await tester.tap(find.byKey(const ValueKey('settings-close')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ai-tasks-discard')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsWindow), findsNothing);
      expect(_stored(container).binding(TaskType.studyNotes).model, _haiku);
    });

    testWidgets('“Test” runs a cancellable probe; acceptance alone stays unverified', (tester) async {
      late _Probe probe;
      await _open(
        tester,
        overrides: [
          assistantCapabilityProbeProvider.overrideWith(
            (ref) => probe = _Probe(ref.watch(assistantModelResolverProvider)),
          ),
        ],
      );
      await tester.tap(find.byKey(const ValueKey('ai-action-default-quick')));
      await tester.pump();
      expect(probe.calls, [_haiku]);
      expect(find.byType(CupertinoActivityIndicator), findsWidgets);
      probe.result.complete();
      await tester.pumpAndSettle();
      expect(find.text('已连接 · 兼容性未验证'), findsOneWidget);
      expect(find.text('需验证兼容性'), findsOneWidget, reason: 'the heavy default is still untested');
    });

    testWidgets('an unreadable key says “Connection unavailable” and opens the service', (tester) async {
      await _open(tester, secrets: _UnreadableSecrets());
      expect(find.text('连接不可用'), findsNWidgets(2));
      await tester.tap(find.byKey(const ValueKey('ai-action-default-heavy')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-models')), findsOneWidget);
      expect(find.byKey(const ValueKey('service-name')), findsOneWidget, reason: 'the Anthropic card is open');
    });

    testWidgets('narrow sheet: two-line rows, no overflow, menu becomes an action sheet', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;

      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _open(
        tester,
        size: const Size(320, 640),
        overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(true)],
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('settings-ai-tasks')), findsOneWidget);
      expect(MMBottomSheet.contains(tester.element(find.byKey(const ValueKey('settings-ai-tasks')))), isTrue);
      final name = aiTaskName(l, TaskType.mapGenerate);
      final label = find.text(name);
      final picker = _row(name);
      await tester.ensureVisible(picker);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(picker).dy, greaterThanOrEqualTo(tester.getBottomLeft(label).dy - 1));
      expect(tester.getTopRight(picker).dx, lessThanOrEqualTo(320));
      await tester.tap(picker);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mm-action-sheet')), findsOneWidget);
      expect(find.text('需验证'), findsWidgets, reason: 'notes stay in the sheet');
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });

  group('capability profiles', () {
    Future<ProviderContainer> openMaintained(WidgetTester tester, {List<Override> overrides = const []}) => _open(
      tester,
      prefs: _prefs(services: [_openai], routing: _routing(quick: null, heavy: null)),
      secrets: FakeSecrets()..values[AssistantServicesStore.account('openai')] = 'k',
      overrides: overrides,
    );

    testWidgets('first open with models but no defaults loads maintained profiles for menus and thinking', (
      tester,
    ) async {
      await openMaintained(tester);
      expect(_pickerOf(tester, '重型任务 · 默认模型').label, '选择模型');
      expect(_pickerOf(tester, aiTaskName(l, TaskType.research)).label, '需配置');
      await tester.tap(_row('重型任务 · 默认模型'));
      await tester.pumpAndSettle();
      expect(find.text('GPT-4.1'), findsWidgets);
      expect(find.text('需验证'), findsNothing, reason: 'the reviewed exact rule is loaded before any row resolves');
      await tester.tap(find.text('GPT-4.1').hitTestable().last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MMPopUpButton<ReasoningPolicy>>(find.byKey(const ValueKey('ai-tasks-heavy-reasoning')))
            .items
            .map((e) => e.$1),
        [ReasoningPolicy.auto, ReasoningPolicy.off],
      );
      expect(find.text('需验证兼容性'), findsNothing);
    });

    testWidgets('changing the service identity refreshes rows, menus and thinking choices', (tester) async {
      final container = await openMaintained(tester);
      await _choose(tester, '重型任务 · 默认模型', 'GPT-4.1');
      expect(find.text('需验证兼容性'), findsNothing);
      await container
          .read(assistantServicesProvider.notifier)
          .updateDetails('openai', endpoint: 'https://proxy.example/v1');
      await tester.pumpAndSettle();
      expect(find.text('需验证兼容性'), findsOneWidget, reason: 'a proxy endpoint is not the reviewed identity');
      expect(
        tester
            .widget<MMPopUpButton<ReasoningPolicy>>(find.byKey(const ValueKey('ai-tasks-heavy-reasoning')))
            .items
            .map((e) => e.$1),
        [ReasoningPolicy.auto],
      );
      await tester.tap(_row(aiTaskName(l, TaskType.research)));
      await tester.pumpAndSettle();
      expect(find.text('需验证'), findsOneWidget);
    });

    testWidgets('a failed profile refresh is visible and retryable; the draft stays', (tester) async {
      final profiles = _FlakyProfiles();
      await _open(tester, overrides: [assistantCapabilityProfilesProvider.overrideWithValue(profiles)]);
      final name = aiTaskName(l, TaskType.documentSummarize);
      await _choose(tester, name, 'Claude Haiku');
      profiles.fail = true;
      await _choose(tester, aiTaskName(l, TaskType.research), 'Claude Haiku');
      expect(find.byKey(const ValueKey('ai-tasks-profiles-failed')), findsOneWidget);
      expect(find.text('无法读取模型能力'), findsOneWidget);
      expect(_pickerOf(tester, name).selected, _haiku, reason: 'the draft is untouched');
      expect(_pickerOf(tester, aiTaskName(l, TaskType.research)).selected, _haiku);
      expect(find.text('未保存'), findsOneWidget);
      profiles.fail = false;
      await tester.ensureVisible(find.byKey(const ValueKey('ai-tasks-profiles-retry')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ai-tasks-profiles-retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-tasks-profiles-failed')), findsNothing);
      expect(_pickerOf(tester, name).selected, _haiku);
    });

    testWidgets('a probe whose observation cannot be saved says so instead of passing', (tester) async {
      await _open(
        tester,
        overrides: [
          assistantCapabilityProbeProvider.overrideWith(
            (ref) => _UnsavedProbe(ref.watch(assistantModelResolverProvider)),
          ),
        ],
      );
      await tester.tap(find.byKey(const ValueKey('ai-action-default-quick')));
      await tester.pumpAndSettle();
      expect(find.text('测试结果未保存'), findsOneWidget);
      expect(find.text('已连接 · 兼容性未验证'), findsNothing);
      expect(find.text('连接不可用'), findsNothing);
    });
  });

  group('status components', () {
    testWidgets('capsules map run states; models list frozen phases', (tester) async {
      Future<void> pump(Widget child) => tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: MMTheme.light(),
          home: Scaffold(body: Center(child: child)),
        ),
      );
      await pump(const RunStatusCapsule(status: RunStatus.partial, unfinished: 3, unit: '段'));
      expect(find.text('部分完成 · 3 段未完成'), findsOneWidget);
      await pump(const RunStatusCapsule(status: RunStatus.interrupted, done: 4, total: 9));
      expect(find.text('已中断 4/9'), findsOneWidget);
      await pump(const RunStatusCapsule(status: RunStatus.running, progress: .42));
      expect(find.text('42%'), findsOneWidget);
      await pump(const RoutingIssueLine(text: '模型已删除', action: '重新选择'));
      expect(find.text('重新选择'), findsOneWidget);

      expect(routingIssueText(l, RoutingIssue.capabilityMissing, failureCode: 'tools:unsupported'), '此模型不支持工具调用');
      expect(routingIssueText(l, RoutingIssue.unset), isNull);
      expect(routingIssueBlocks(RoutingIssue.unknown), isFalse);
      expect(routingIssueBlocks(RoutingIssue.deleted), isTrue);

      final catalog = AssistantServices(services: [_anthropic, _proxy]);
      RunContext phase(ModelReference model, String label) {
        final identity = CapabilityIdentity(
          model: model,
          protocol: ModelProtocol.anthropicMessages,
          endpointFingerprint: 'e',
          adapterVersion: 'a',
          serviceRevision: 1,
        );
        return RunContext(
          runId: 'r',
          knowledgeVersions: const {},
          modelDisplayName: label,
          config: ResolvedTaskConfig(
            capabilities: ModelCapabilityProfile(identity: identity),
            policy: ProviderCallPolicy(
              identity: identity,
              requested: ReasoningPolicy.auto,
              effective: ReasoningPolicy.auto,
              recipe: ReasoningRecipe.omitted,
              parameters: const {},
            ),
            routingRevision: 1,
            source: RoutingSource.categoryDefault,
          ),
        );
      }

      expect(
        runModelsLabel(catalog, [
          phase(_opus, 'x'),
          phase(_opus, 'x'),
          phase(const ModelReference('gone', 'g'), 'GPT-5'),
        ]),
        'Anthropic · Claude Opus → GPT-5',
      );
    });
  });
}

class _FailingRoutingStore extends AssistantRoutingStore {
  _FailingRoutingStore(super.prefs, super.services);
  bool fail = false;
  @override
  Future<RoutingConfig> save(RoutingConfig draft, {required int expectedRevision}) async {
    if (fail) throw StateError('write failed');
    return super.save(draft, expectedRevision: expectedRevision);
  }
}
