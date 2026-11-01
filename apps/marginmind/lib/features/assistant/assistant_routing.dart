import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/providers.dart';
import 'assistant_services.dart';
import 'assistant_settings.dart';

class RoutingRevisionConflict implements Exception {
  const RoutingRevisionConflict(this.expected, this.actual);
  final int expected, actual;
}

/// All instances sharing these preferences participate in one write queue.
/// Unsupported documents remain byte-for-byte intact, including during migration.
class AssistantRoutingStore {
  AssistantRoutingStore(this.prefs, this.services);
  final SharedPreferences prefs;
  final AssistantServicesStore services;
  static const settingsKey = 'assistant.task-routing.v1';
  static final _queues = Expando<Future<void>>();

  Future<T> _serial<T>(Future<T> Function() operation) {
    final next = (_queues[prefs] ?? Future<void>.value()).then((_) => operation());
    _queues[prefs] = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<RoutingConfig> load() => _serial(_load);
  Future<RoutingConfig> _load() async {
    final raw = prefs.getString(settingsKey);
    if (raw != null) return _decode(raw);
    final catalog = await services.load();
    // Read the persisted reference, before the compatibility catalog's historical
    // first-enabled repair. Invalid legacy references must remain invalid.
    final legacyRaw = prefs.getString(AssistantServicesStore.settingsKey);
    final legacy = legacyRaw == null ? catalog.defaultModel?.toJson() : (jsonDecode(legacyRaw) as Map)['default'];
    final model = legacy == null ? null : ModelReference.fromJson(Map<String, dynamic>.from(legacy as Map));
    final initial = RoutingConfig(
      document: {
        'version': 1,
        'revision': 0,
        'defaults': {
          for (final category in TaskCategory.values)
            if (model != null) category.name: routeModelSnapshot(model, catalog),
        },
        'bindings': <String, dynamic>{},
        'heavyReasoning': 'auto',
      },
    );
    await _write(initial);
    return initial;
  }

  RoutingConfig _decode(String raw) {
    final config = RoutingConfig(document: Map<String, dynamic>.from(jsonDecode(raw) as Map));
    // Validate only owned fields. Unknown task keys and extra fields survive.
    for (final category in TaskCategory.values) {
      config.defaultModel(category);
    }
    for (final type in TaskType.values) {
      config.binding(type);
    }
    config.heavyReasoning;
    return config;
  }

  Future<RoutingConfig> save(RoutingConfig draft, {required int expectedRevision}) => _serial(() async {
    final current = await _load();
    if (current.revision != expectedRevision) throw RoutingRevisionConflict(expectedRevision, current.revision);
    final catalog = await services.load();
    Map<String, dynamic> snapshot(Map raw, Map? previous) {
      final reference = ModelReference.fromJson(Map<String, dynamic>.from(raw));
      final service = catalog.services.where((s) => s.id == reference.serviceId).firstOrNull;
      final model = service?.models.where((m) => m.id == reference.modelId).firstOrNull;
      return {
        if (previous != null && previous['serviceId'] == raw['serviceId'] && previous['modelId'] == raw['modelId'])
          ...Map<String, dynamic>.from(previous),
        ...Map<String, dynamic>.from(raw),
        if (service != null) 'serviceLabel': service.name,
        if (model != null) 'modelLabel': model.displayName,
      };
    }

    // Merge unknown data from the current document too: typed UI drafts need not
    // know about fields introduced by a newer version of the application.
    final defaults = {...?current.document['defaults'] as Map?, ...?draft.document['defaults'] as Map?};
    for (final category in TaskCategory.values) {
      final value = (draft.document['defaults'] as Map?)?[category.name];
      if (value == null) {
        defaults.remove(category.name);
      } else {
        defaults[category.name] = snapshot(
          value as Map,
          (current.document['defaults'] as Map?)?[category.name] as Map?,
        );
      }
    }
    final bindings = {...?current.document['bindings'] as Map?, ...?draft.document['bindings'] as Map?};
    for (final type in TaskType.values) {
      final raw = (draft.document['bindings'] as Map?)?[type.key] as Map?;
      if (raw == null) {
        bindings.remove(type.key);
        continue;
      }
      final previous = ((current.document['bindings'] as Map?)?[type.key] as Map?) ?? {};
      bindings[type.key] = {
        ...previous,
        ...raw,
        if (raw['model'] is Map) 'model': snapshot(raw['model'] as Map, previous['model'] as Map?),
      };
    }
    final saved = _decode(
      jsonEncode({
        ...current.document,
        ...draft.document,
        'version': 1,
        'revision': current.revision + 1,
        'defaults': defaults,
        'bindings': bindings,
      }),
    );
    await _write(saved);
    return saved;
  });
  Future<void> _write(RoutingConfig config) async {
    try {
      if (!await prefs.setString(settingsKey, jsonEncode(config.toJson()))) {
        throw StateError('Routing settings write failed');
      }
    } catch (_) {
      // SharedPreferences updates its cache before the platform write succeeds.
      // Reload durable state so a retry cannot observe an uncommitted revision.
      await prefs.reload();
      rethrow;
    }
  }
}

final assistantRoutingStoreProvider = Provider<AssistantRoutingStore>(
  (ref) => AssistantRoutingStore(ref.watch(sharedPreferencesProvider), ref.watch(assistantServicesStoreProvider)),
);
final assistantRoutingProvider = AsyncNotifierProvider<AssistantRoutingController, RoutingConfig>(
  AssistantRoutingController.new,
);

class AssistantRoutingController extends AsyncNotifier<RoutingConfig> {
  @override
  Future<RoutingConfig> build() => ref.watch(assistantRoutingStoreProvider).load();
  Future<void> save(RoutingConfig draft, {required int expectedRevision}) async {
    final saved = await ref.read(assistantRoutingStoreProvider).save(draft, expectedRevision: expectedRevision);
    state = AsyncData(saved);
  }
}

final assistantCapabilityProfilesProvider = Provider<CapabilityProfiles>((ref) => CapabilityProfiles());
final assistantModelResolverProvider = Provider<TaskModelResolver>(
  (ref) => TaskModelResolver(
    catalog: () => ref.read(assistantServicesStoreProvider).load(),
    profiles: ref.watch(assistantCapabilityProfilesProvider),
    credentialsAvailable: (service) async =>
        service.protocol == ServiceProtocol.ollama ||
        (await assistantServiceKey(
              ref.read(assistantSecretsProvider),
              service.id,
              service.provider,
            ))?.trim().isNotEmpty ==
            true,
  ),
);
final assistantCapabilityProbeProvider = Provider<RoutingCapabilityProbe>(
  (ref) => RoutingCapabilityProbe(
    resolver: ref.watch(assistantModelResolverProvider),
    key: (model) async => await assistantModelKey(ref.read(assistantSecretsProvider), model) ?? '',
  ),
);

/// The archive/RunStore owner supplies a read-only index at composition time.
final assistantRoutingUsageProvider = Provider.family<RoutingUsage, RoutingUsageIndex>(
  (ref, index) => RoutingUsage(routing: () => ref.read(assistantRoutingStoreProvider).load(), index: index),
);
