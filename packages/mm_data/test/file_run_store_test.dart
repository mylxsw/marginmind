import 'dart:convert';
import 'dart:io';

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:test/test.dart';

RunManifest manifest(int revision, {RunStatus status = RunStatus.running, String id = 'run'}) {
  final identity = CapabilityIdentity(
    model: const ModelReference('service', 'model'),
    protocol: ModelProtocol.chatCompletions,
    endpointFingerprint: 'endpoint',
    adapterVersion: 'fixture',
    serviceRevision: 1,
  );
  return RunManifest(
    context: RunContext(
      runId: id,
      knowledgeVersions: {'test': '1'},
      modelDisplayName: 'Model',
      inputRange: {
        'ids': ['page-1'],
      },
      config: ResolvedTaskConfig(
        capabilities: ModelCapabilityProfile(identity: identity),
        policy: ProviderCallPolicy(
          identity: identity,
          requested: ReasoningPolicy.off,
          effective: ReasoningPolicy.off,
          recipe: ReasoningRecipe.effortNone,
          parameters: {'reasoning_effort': 'none'},
        ),
        routingRevision: 3,
        source: RoutingSource.functionBinding,
      ),
    ),
    taskType: TaskType.titleGenerate,
    inputFingerprint: 'input',
    promptVersion: '1',
    schemaVersion: '1',
    status: status,
    revision: revision,
    checkpoint: {'sdk': 'dart_agent_core', 'version': '2.1.8', 'adapter': 1},
  );
}

void main() {
  late Directory dir;
  late FileRunStore store;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mm-runs-');
    store = FileRunStore(dir);
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  test('durable roundtrip, model references, unknown usage and atomic idempotent completion', () async {
    await store.checkpoint(manifest(0), expectedRevision: null);
    final reopened = FileRunStore(dir);
    final loaded = await reopened.load('run');
    expect(loaded!.context.config.model, const ModelReference('service', 'model'));
    expect(loaded.context.modelDisplayName, 'Model');
    expect(loaded.usage.quality, UsageQuality.unknown);
    expect((await reopened.resumable()).single.context.inputRange['ids'], ['page-1']);
    final terminal = manifest(1, status: RunStatus.completed);
    await reopened.complete(terminal, {'title': 'Saved'}, expectedRevision: 0);
    await store.complete(terminal, {'title': 'Saved'}, expectedRevision: 0);
    expect(await store.loadResult('run'), {'title': 'Saved'});
    expect(await store.resumable(), isEmpty);
    await expectLater(store.checkpoint(manifest(2), expectedRevision: 1), throwsA(isA<RunStoreConflict>()));
  });
  test('two instances serialize CAS and preserve winner', () async {
    await store.checkpoint(manifest(0), expectedRevision: null);
    final outcomes = await Future.wait(
      [store, FileRunStore(dir)].map((s) async {
        try {
          await s.checkpoint(manifest(1, status: RunStatus.paused), expectedRevision: 0);
          return 'ok';
        } on RunStoreConflict {
          return 'conflict';
        }
      }),
    );
    // Identical duplicate snapshots are idempotent, including lost acknowledgements.
    expect(outcomes, ['ok', 'ok']);
    await expectLater(
      store.checkpoint(manifest(1, status: RunStatus.interrupted), expectedRevision: 0),
      throwsA(isA<RunStoreConflict>()),
    );
  });
  test('unknown format, identity mismatch and links fail without overwriting', () async {
    await store.checkpoint(manifest(0), expectedRevision: null);
    final file = File('${dir.path}/ai-runs/v1/run.json');
    final unknown = jsonEncode({'version': 99});
    await file.writeAsString(unknown);
    await expectLater(store.load('run'), throwsFormatException);
    await expectLater(store.checkpoint(manifest(1), expectedRevision: 0), throwsFormatException);
    expect(await file.readAsString(), unknown);
    await file.delete();
    await Link(file.path).create('${dir.path}/outside');
    await expectLater(store.load('run'), throwsA(isA<FileSystemException>()));
    await expectLater(store.load('../escape'), throwsFormatException);
  });
}
