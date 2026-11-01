import 'dart:convert';

import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'assistant_services.dart';

/// Durable, derived evidence cache. Persist only exact identities, reviewed rule
/// revision and acceptance observations, never arbitrary user capability claims.
/// All instances for the same preferences object share one write queue.
class AssistantCapabilityProfiles extends CapabilityProfiles {
  AssistantCapabilityProfiles(this.prefs, this.services);
  final SharedPreferences prefs;
  final AssistantServicesStore services;
  static const settingsKey = 'assistant.capability-profiles.v1';
  static final _queues = Expando<Future<void>>();
  Map<String, Map<String, dynamic>> _rows = {};
  String? _serviceSnapshot;

  void _discard() {
    clear();
    _rows = {};
    _serviceSnapshot = null;
  }

  // Preferences change synchronously before platform persistence completes.
  // Fence the published snapshot even while a queued refresh is still waiting.
  void _validateSnapshot() {
    if (_serviceSnapshot != prefs.getString(AssistantServicesStore.settingsKey)) _discard();
  }

  @override
  ModelCapabilityProfile lookup(CapabilityIdentity identity) {
    _validateSnapshot();
    return super.lookup(identity);
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final next = (_queues[prefs] ?? Future<void>.value()).then((_) => action());
    _queues[prefs] = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  String _key(CapabilityIdentity identity) => jsonEncode(capabilityIdentityJson(identity));

  /// Independent remote acceptance evidence. It never grants semantic support.
  Map<String, dynamic>? probeObservation(CapabilityIdentity identity) {
    _validateSnapshot();
    final probe = _rows[_key(identity)]?['probe'];
    return probe == null ? null : freezeAgentJson(Map<String, dynamic>.from(probe as Map));
  }

  @override
  Future<void> refresh() => _serial(() => _refresh());

  @override
  Future<void> recordProbe(CapabilityIdentity identity, ReasoningPolicy reasoning) =>
      _serial(() => _refresh(probed: identity, reasoning: reasoning));

  Future<void> _refresh({CapabilityIdentity? probed, ReasoningPolicy? reasoning}) async {
    try {
      await _buildAndPublish(probed: probed, reasoning: reasoning);
    } catch (_) {
      _discard();
      rethrow;
    }
  }

  Future<void> _buildAndPublish({CapabilityIdentity? probed, ReasoningPolicy? reasoning}) async {
    final raw = prefs.getString(settingsKey);
    final previous = <String, Map<String, dynamic>>{};
    if (raw != null) {
      try {
        final document = jsonDecode(raw) as Map;
        if (document['version'] != 1 ||
            (document['rules'] != maintainedCapabilityRevision &&
                !previousMaintainedCapabilityRevisions.contains(document['rules']))) {
          throw const ConfigurationFailure('unsupportedCapabilityStoreVersion');
        }
        for (final row in document['entries'] as List) {
          final entry = Map<String, dynamic>.from(row as Map);
          // Keys must have been emitted by this schema. Unknown or corrupt data
          // is kept intact on disk and cannot bootstrap a fresh trusted cache.
          if (entry.keys.any((k) => !{'identity', 'rule', 'probe'}.contains(k)) || entry['identity'] is! Map) {
            throw const FormatException('Invalid capability row');
          }
          final id = entry['identity'] as Map;
          if (id.length != 6 ||
              id.keys.any(
                (key) => !{
                  'model',
                  'protocol',
                  'endpointFingerprint',
                  'adapterVersion',
                  'serviceRevision',
                  'modelRevision',
                }.contains(key),
              ) ||
              id['model'] is! Map ||
              (id['model'] as Map).length != 2 ||
              (id['model'] as Map)['serviceId'] is! String ||
              (id['model'] as Map)['modelId'] is! String ||
              id['serviceRevision'] is! int ||
              (id['serviceRevision'] as int) < 0 ||
              id['adapterVersion'] is! String ||
              id['endpointFingerprint'] is! String ||
              !RegExp(r'^[a-f0-9]{64}$').hasMatch(id['endpointFingerprint'] as String) ||
              (id['modelRevision'] != null && id['modelRevision'] is! String) ||
              (entry['rule'] != null && entry['rule'] != document['rules'])) {
            throw const FormatException('Invalid capability identity or rule');
          }
          ModelProtocol.values.byName(id['protocol'] as String);
          final key = jsonEncode(entry['identity']);
          if (previous.containsKey(key)) throw const FormatException('Duplicate capability row');
          if (entry['probe'] != null) {
            final probe = entry['probe'] as Map;
            if (probe.length != 2 || probe['acceptedAt'] is! String || probe['reasoning'] is! String) {
              throw const FormatException('Invalid probe observation');
            }
            DateTime.parse(probe['acceptedAt'] as String);
            ReasoningPolicy.values.byName(probe['reasoning'] as String);
          }
          previous[key] = entry;
        }
      } on ConfigurationFailure {
        rethrow;
      } catch (_) {
        throw const ConfigurationFailure('corruptCapabilityStore');
      }
    }
    final catalog = await services.load();
    final serviceSnapshot = prefs.getString(AssistantServicesStore.settingsKey);
    final rows = <String, Map<String, dynamic>>{};
    final profiles = <ModelCapabilityProfile>[];
    for (final service in catalog.services) {
      if (!service.enabled || (service.protocol == ServiceProtocol.ollama && !service.localEnabled)) continue;
      for (final model in service.models.where((m) => m.enabled)) {
        final CapabilityIdentity identity;
        try {
          identity = serviceCapabilityIdentity(service, model);
        } on ConfigurationFailure {
          continue;
        } on FormatException {
          continue;
        }
        final key = _key(identity);
        final profile = maintainedCapabilityProfile(service, model);
        final rule = profile == null ? null : maintainedCapabilityRevision;
        final old = previous[key];
        rows[key] = {
          'identity': capabilityIdentityJson(identity),
          'rule': rule,
          if (old != null && old['rule'] == rule && old['probe'] != null) 'probe': old['probe'],
          if (identity == probed)
            'probe': {'acceptedAt': DateTime.now().toUtc().toIso8601String(), 'reasoning': reasoning!.name},
        };
        if (profile != null) profiles.add(profile);
      }
    }
    if (probed != null && !rows.containsKey(_key(probed))) {
      throw const ConfigurationFailure('serviceConfigurationChanged');
    }
    final encoded = jsonEncode({'version': 1, 'rules': maintainedCapabilityRevision, 'entries': rows.values.toList()});
    if (encoded != raw) {
      try {
        if (!await prefs.setString(settingsKey, encoded)) throw StateError('Capability persistence failed');
      } catch (_) {
        _discard();
        await prefs.reload();
        rethrow;
      }
    }
    // An edit while the platform write was pending makes this refresh stale.
    // Stale identity rows are harmless on disk and pruned by the next refresh.
    final latest = await services.load();
    if (prefs.getString(AssistantServicesStore.settingsKey) != serviceSnapshot ||
        jsonEncode(latest.toJson()) != jsonEncode(catalog.toJson())) {
      throw const ConfigurationFailure('serviceConfigurationChanged');
    }
    // Publish the fully validated snapshot without yielding to another caller.
    clear();
    _serviceSnapshot = serviceSnapshot;
    _rows = rows;
    for (final profile in profiles) {
      super.put(profile);
    }
  }

  /// Production admission is derived only by refresh; callers cannot persist or
  /// inject claims through the compatibility in-memory method.
  @override
  void put(ModelCapabilityProfile profile) => throw UnsupportedError('Use refresh with maintained evidence');
}
