import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/assistant/map_task_factory.dart';
import 'package:marginmind/features/assistant/map_task_journal.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';

import 'map_task_recovery_test.dart' show Fixture, until;

Future<MapTaskSession> restore(ProviderContainer container, TaskSpec spec, String id) =>
    container.read(Provider((ref) => MapTaskSession.restore(ref, 'study', spec, id)));

Future<List<String>> runIds(Directory directory) async => [
  await for (final file in Directory('${directory.path}/ai-runs/v1').list())
    if (file is File && file.path.endsWith('.json'))
      (jsonDecode(await file.readAsString())['manifest']['context']['runId'] as String),
];

void main() {
  for (final spec in [mapGenerateSpec, mapExpandSpec]) {
    test(
      '${spec.type.name}: independent containers reject an active owner, then reuse the exact claimed stage',
      () async {
        final fixture = Fixture();
        await fixture.open();
        final other = ProviderContainer(overrides: fixture.overrides);
        final gate = Completer<void>();
        Future<String>? active;
        try {
          final original = fixture.session(spec);
          await original.saveWorkflow({'request': {}, 'sourceRevision': 'same'});
          await original.execute('fixed', {'stage': 'complete'}, CancellationToken(), (_) => ValidationReport());
          final left = await fixture.restore(spec, original.id!);
          final right = await restore(other, spec, original.id!);
          fixture.beforeReply = () => gate.future;
          active = left.execute('fixed', {'stage': 'next'}, CancellationToken(), (_) => ValidationReport());
          await until(() => fixture.calls == 2);
          final before = await left.journal.load(original.id!);
          await expectLater(
            right.execute('fixed', {'stage': 'next'}, CancellationToken(), (_) => ValidationReport()),
            throwsA(isA<ConfigurationFailure>().having((e) => e.code, 'code', 'mapTaskActive')),
          );
          // A different missing stage of this root cannot take over its live
          // execution either, even with explicitContinuation enabled.
          await expectLater(
            right.execute('fixed', {'stage': 'different'}, CancellationToken(), (_) => ValidationReport()),
            throwsA(isA<ConfigurationFailure>().having((e) => e.code, 'code', 'mapTaskActive')),
          );
          expect(fixture.calls, 2);
          gate.complete();
          expect(await active, 'saved result');
          expect(
            await right.execute('fixed', {'stage': 'next'}, CancellationToken(), (_) => ValidationReport()),
            'saved result',
          );
          final after = await right.journal.load(original.id!);
          expect(after['stages'], before['stages']);
          final linked = (after['stages'] as Map).values.map((s) => s['context']['runId']).toSet();
          expect((await runIds(fixture.directory)).toSet(), linked);
          expect(linked, hasLength(2));
          var paidCalls = 0;
          for (final id in linked) {
            paidCalls += (await FileRunStore(fixture.directory).load(id as String))!.usage.modelCalls;
          }
          expect(paidCalls, 2);
          expect(fixture.calls, 2);
        } finally {
          if (!gate.isCompleted) gate.complete();
          if (active != null) await active;
          other.dispose();
          await fixture.close();
        }
      },
    );
  }

  test(
    'a terminal request failure can be explicitly retried once, retaining both run associations and usage',
    () async {
      final fixture = Fixture();
      await fixture.open();
      final other = ProviderContainer(overrides: fixture.overrides);
      final gate = Completer<void>();
      Future<String>? active;
      try {
        final original = fixture.session(mapGenerateSpec);
        await original.saveWorkflow({'request': {}, 'sourceRevision': 'same'});
        fixture.statusCode = HttpStatus.badRequest;
        await expectLater(
          original.execute('fixed', {'stage': 'failed'}, CancellationToken(), (_) => ValidationReport()),
          throwsA(isA<ResearchFailure>()),
        );
        fixture.statusCode = HttpStatus.ok;
        final failed = (await FileRunStore(fixture.directory).load(original.id!))!;
        expect(failed.status, RunStatus.failed);
        expect(failed.usage.modelCalls, 1);
        final left = await fixture.restore(mapGenerateSpec, original.id!);
        final right = await restore(other, mapGenerateSpec, original.id!);
        fixture.beforeReply = () => gate.future;
        active = left.execute('fixed', {'stage': 'failed'}, CancellationToken(), (_) => ValidationReport());
        await until(() => fixture.calls == 2);
        await expectLater(
          right.execute('fixed', {'stage': 'failed'}, CancellationToken(), (_) => ValidationReport()),
          throwsA(isA<ConfigurationFailure>().having((e) => e.code, 'code', 'mapTaskActive')),
        );
        gate.complete();
        await active;
        await right.execute('fixed', {'stage': 'failed'}, CancellationToken(), (_) => ValidationReport());
        final entry = ((await right.journal.load(original.id!))['stages'] as Map).values.single as Map;
        expect(entry['previousRuns'], [original.id]);
        final child = entry['context']['runId'] as String;
        expect(child, isNot(original.id));
        expect((await runIds(fixture.directory)).toSet(), {original.id, child});
        expect((await FileRunStore(fixture.directory).load(child))!.usage.modelCalls, 1);
        expect((await FileRunStore(fixture.directory).load(original.id!))!.usage.modelCalls, 1);
        expect(fixture.calls, 2);
      } finally {
        if (!gate.isCompleted) gate.complete();
        if (active != null) await active;
        other.dispose();
        await fixture.close();
      }
    },
  );

  test('different roots and same-session parallel stages remain concurrent', () async {
    final fixture = Fixture();
    await fixture.open();
    final gate = Completer<void>();
    final active = <Future<String>>[];
    try {
      fixture.beforeReply = () => gate.future;
      final first = fixture.session(mapGenerateSpec), second = fixture.session(mapGenerateSpec);
      active.addAll([
        first.execute('fixed', {'stage': 'one'}, CancellationToken(), (_) => ValidationReport()),
        first.execute('fixed', {'stage': 'two'}, CancellationToken(), (_) => ValidationReport()),
        second.execute('fixed', {'stage': 'one'}, CancellationToken(), (_) => ValidationReport()),
      ]);
      await until(() => fixture.calls == 3);
      expect(first.id, isNot(second.id));
      gate.complete();
      await Future.wait(active);
      final firstStages = (await first.journal.load(first.id!))['stages'] as Map;
      expect(firstStages, hasLength(2));
      final firstIds = firstStages.values.map((s) => s['context']['runId']).toSet();
      expect(firstIds, hasLength(2));
      expect(firstIds, contains(first.id));
    } finally {
      if (!gate.isCompleted) gate.complete();
      await Future.wait(active);
      await fixture.close();
    }
  });

  test('stopped save_failed execution retains ownership until its same handle flushes', () async {
    final fixture = Fixture();
    await fixture.open();
    final other = ProviderContainer(overrides: fixture.overrides);
    try {
      final original = fixture.session(mapGenerateSpec);
      await original.saveWorkflow({'request': {}, 'sourceRevision': 'same'});
      fixture.beforeReply = fixture.blockRunWrites;
      final cancel = CancellationToken();
      final active = original.execute('fixed', {'stage': 'pending'}, cancel, (_) => ValidationReport());
      final stopped = expectLater(active, throwsA(isA<ResearchFailure>()));
      await until(() => original.saveFailed.isNotEmpty);
      cancel.cancel();
      await stopped;
      final right = await restore(other, mapGenerateSpec, original.id!);
      await expectLater(
        right.execute('fixed', {'stage': 'pending'}, CancellationToken(), (_) => ValidationReport()),
        throwsA(isA<ConfigurationFailure>().having((e) => e.code, 'code', 'mapTaskActive')),
      );
      await fixture.restoreRunWrites();
      await original.retrySave();
      expect(
        await right.execute('fixed', {'stage': 'pending'}, CancellationToken(), (_) => ValidationReport()),
        'saved result',
      );
      expect(fixture.calls, 1);
      expect((await FileRunStore(fixture.directory).load(original.id!))!.usage.modelCalls, 1);
    } finally {
      other.dispose();
      await fixture.close();
    }
  });

  test('execution ownership also excludes another isolate', () async {
    final directory = await Directory.systemTemp.createTemp('map-lease-isolate-');
    final messages = ReceivePort();
    final events = StreamIterator(messages);
    Isolate? worker;
    try {
      worker = await Isolate.spawn((List<Object> args) async {
        final port = args[0] as SendPort;
        final controls = ReceivePort();
        final lease = await MapTaskJournal(args[1] as String).claimExecution('root');
        port.send(controls.sendPort);
        await controls.first;
        await lease.release();
        controls.close();
        port.send('released');
      }, [messages.sendPort, directory.path]);
      expect(await events.moveNext(), isTrue);
      final controls = events.current as SendPort;
      await expectLater(
        MapTaskJournal(directory.path).claimExecution('root'),
        throwsA(isA<ConfigurationFailure>().having((e) => e.code, 'code', 'mapTaskActive')),
      );
      controls.send('release');
      expect(await events.moveNext(), isTrue);
      expect(events.current, 'released');
      final next = await MapTaskJournal(directory.path).claimExecution('root');
      await next.release();
    } finally {
      worker?.kill();
      await events.cancel();
      messages.close();
      await directory.delete(recursive: true);
    }
  });

  test('journal transactions from independent isolates retain every stage association', () async {
    final directory = await Directory.systemTemp.createTemp('map-journal-isolates-');
    final messages = ReceivePort();
    final events = StreamIterator(messages);
    final workers = <Isolate>[];
    try {
      for (var index = 0; index < 2; index++) {
        workers.add(
          await Isolate.spawn((List<Object> args) async {
            final journal = MapTaskJournal(args[1] as String);
            for (var stage = 0; stage < 10; stage++) {
              await journal.update('root', (data) {
                (data['stages'] as Map)['${args[2]}-$stage'] = {'runId': '${args[2]}-$stage'};
              });
            }
            (args[0] as SendPort).send('done');
          }, [messages.sendPort, directory.path, index]),
        );
      }
      expect(await events.moveNext(), isTrue);
      expect(await events.moveNext(), isTrue);
      final stages = (await MapTaskJournal(directory.path).load('root'))['stages'] as Map;
      expect(stages, hasLength(20));
      expect(stages.values.map((s) => s['runId']).toSet(), hasLength(20));
    } finally {
      for (final worker in workers) {
        worker.kill();
      }
      await events.cancel();
      messages.close();
      await directory.delete(recursive: true);
    }
  });

  test('a save failure after the execute waiter is cancelled stays observable and owned', () async {
    final fixture = Fixture();
    await fixture.open();
    final gate = Completer<void>();
    try {
      final session = fixture.session(mapGenerateSpec);
      await session.saveWorkflow({'request': {}, 'sourceRevision': 'same'});
      fixture.beforeReply = () => gate.future;
      final token = CancellationToken();
      final stopped = expectLater(
        session.execute('fixed', {'stage': 'cancelled'}, token, (_) => ValidationReport()),
        throwsA(isA<ResearchFailure>()),
      );
      await until(() => fixture.calls == 1);
      await fixture.blockRunWrites();
      token.cancel();
      gate.complete();
      await stopped;
      await until(() => session.saveFailed.isNotEmpty);
      expect(fixture.container.read(mapSaveFailuresProvider), contains(session));
      await expectLater(
        session.journal.claimExecution(session.id!),
        throwsA(isA<ConfigurationFailure>().having((e) => e.code, 'code', 'mapTaskActive')),
      );
      await fixture.restoreRunWrites();
      await session.retrySave();
      expect(session.saveFailed, isEmpty);
      expect(fixture.calls, 1);
      expect((await FileRunStore(fixture.directory).load(session.id!))!.usage.modelCalls, 1);
      final next = await session.journal.claimExecution(session.id!);
      await next.release();
    } finally {
      if (!gate.isCompleted) gate.complete();
      await fixture.close();
    }
  });

  test('live process ownership cannot be stolen; an exited process can be explicitly recovered', () async {
    final directory = await Directory.systemTemp.createTemp('map-lease-process-');
    final sdk = Platform.environment['FLUTTER_ROOT'];
    final executable = sdk == null ? 'dart' : '$sdk/bin/cache/dart-sdk/bin/dart';
    final localConfig = File('.dart_tool/package_config.json');
    final config = await localConfig.exists() ? localConfig.path : '../../.dart_tool/package_config.json';
    final worker = await Process.start(executable, [
      '--packages=$config',
      'test/support/map_task_lease_worker.dart',
      directory.path,
      'root',
    ]);
    final errors = worker.stderr.transform(utf8.decoder).join();
    try {
      expect(
        await worker.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first
            .timeout(const Duration(seconds: 20)),
        'ready',
      );
      await expectLater(
        MapTaskJournal(directory.path).claimExecution('root'),
        throwsA(isA<ConfigurationFailure>().having((e) => e.code, 'code', 'mapTaskActive')),
      );
      // Another root remains available while the first process is alive.
      final independent = await MapTaskJournal(directory.path).claimExecution('other-root');
      await independent.release();
      worker.stdin.writeln('exit');
      await worker.stdin.flush();
      expect(await worker.exitCode, 0, reason: await errors);
      final recovered = await MapTaskJournal(directory.path).claimExecution('root');
      await recovered.release();
    } finally {
      await worker.stdin.close();
      await worker.exitCode;
      await errors;
      await directory.delete(recursive: true);
    }
  });
}
