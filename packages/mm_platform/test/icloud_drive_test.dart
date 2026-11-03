import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_platform/mm_platform.dart';
import 'package:mm_sync/mm_sync.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/icloud');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final directory = 'foliarc-v2/${'a' * 64}/commits';
  final path = 'foliarc-v2/${'a' * 64}/library.json';
  const container = 'iCloud.io.test.foliarc';
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  Future<MMICloudDrive> port() async => (await MMICloudDrive.configured(channel: channel, supported: true))!;
  Matcher problem(SyncTransportProblem kind) => isA<SyncTransportException>().having((e) => e.problem, 'problem', kind);

  test('account events subscribe without tokens and detach on cancellation', () async {
    const event = EventChannel('test/icloud-events');
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (_) async => container);
    messenger.setMockMethodCallHandler(const MethodChannel('test/icloud-events'), (call) async {
      methods.add(call.method);
      return null;
    });
    final drive = (await MMICloudDrive.configured(channel: channel, events: event, supported: true))!;
    var changes = 0;
    final sub = drive.accountChanges.listen((_) => changes++);
    await Future<void>.delayed(Duration.zero);
    await messenger.handlePlatformMessage(
      'test/icloud-events',
      const StandardMethodCodec().encodeSuccessEnvelope(true),
      (_) {},
    );
    expect(changes, 1);
    await sub.cancel();
    expect(methods, ['listen', 'cancel']);
    messenger.setMockMethodCallHandler(const MethodChannel('test/icloud-events'), null);
  });

  test('configured Apple bridge routes bytes and retains cloud confirmation distinction', () async {
    final calls = <MethodCall>[];
    var confirmed = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'configuration') return container;
      expect(call.arguments['container'], container);
      return switch (call.method) {
        'account' => 'opaque-local-account',
        'list' => ['${'b' * 64}.json'],
        'read' => Uint8List.fromList([123, 125]),
        'uploaded' => confirmed,
        _ => null,
      };
    });
    final drive = await port();
    expect(drive.containerIdentifier, container);
    expect(await drive.accountIdentity(), 'opaque-local-account');
    await drive.prepare(directory, 'account');
    final blobDirectory = directory.replaceAll('/commits', '/blobs');
    await drive.prepare(blobDirectory, 'account');
    await drive.create('$blobDirectory/${'c' * 64}.bin', [0, 255, 128], 'account');
    expect(calls.last.arguments['bytes'], [0, 255, 128]);
    expect(await drive.list(directory, 'account'), ['${'b' * 64}.json']);
    await drive.create(path, [123, 125], 'account');
    expect(calls.last.arguments['bytes'], isA<Uint8List>());
    expect(calls.last.arguments['account'], 'account');
    expect(await drive.read(path, 'account'), [123, 125]);
    expect(await drive.uploaded(path, [123, 125], 'account'), isFalse);
    confirmed = true;
    expect(await drive.uploaded(path, [123, 125], 'account'), isTrue);
  });

  test('cancellation snapshots this port and rejects late successful callbacks', () async {
    final pending = <String, Completer<Object?>>{};
    final cancellations = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'configuration') return container;
      final id = call.arguments['requestId'] as String;
      expect(id, matches(r'^[a-f0-9]{32}$'));
      if (call.method == 'cancel') {
        cancellations.add(id);
        return null;
      }
      final result = Completer<Object?>();
      pending[id] = result;
      return result.future;
    });
    final drive = await port(), other = await port();
    final old = drive.accountIdentity();
    final rejected = expectLater(old, throwsA(problem(SyncTransportProblem.paused)));
    final independent = other.accountIdentity();
    await Future<void>.delayed(Duration.zero);
    final ids = pending.keys.toList();
    await drive.cancelPending();
    expect(cancellations, [ids.first]);
    final fresh = drive.accountIdentity();
    await Future<void>.delayed(Duration.zero);
    for (final result in pending.values) {
      result.complete('account');
    }
    await rejected;
    expect(await independent, 'account');
    expect(await fresh, 'account');
    await drive.cancelPending();
    expect(cancellations, [ids.first]);
  });

  test('failed native cancel retains local invalidation and never leaks native details', () async {
    for (final nativeError in [PlatformException(code: 'private-path'), MissingPluginException()]) {
      final result = Completer<Object?>(), entered = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'configuration') return container;
        if (call.method == 'cancel') throw nativeError;
        entered.complete();
        return result.future;
      });
      final drive = await port();
      final work = expectLater(drive.accountIdentity(), throwsA(problem(SyncTransportProblem.paused)));
      await entered.future;
      await expectLater(drive.cancelPending(), throwsA(problem(SyncTransportProblem.unavailable)));
      result.complete('account');
      await work;
    }
  });

  test('native cancellation and deadline errors are typed without path details', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => container);
    final drive = await port();
    for (final entry in {'cancelled': SyncTransportProblem.paused, 'timedOut': SyncTransportProblem.timedOut}.entries) {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: entry.key, message: 'private'),
      );
      await expectLater(drive.accountIdentity(), throwsA(problem(entry.value)));
    }
  });

  test('unsupported or unconfigured app does not open a container', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return null;
    });
    expect(await MMICloudDrive.configured(channel: channel, supported: false), isNull);
    expect(calls, 0);
    expect(await MMICloudDrive.configured(channel: channel, supported: true), isNull);
    messenger.setMockMethodCallHandler(channel, (_) async => throw MissingPluginException());
    expect(await MMICloudDrive.configured(channel: channel, supported: true), isNull);
    messenger.setMockMethodCallHandler(channel, (_) async => throw PlatformException(code: 'failure'));
    await expectLater(
      MMICloudDrive.configured(channel: channel, supported: true),
      throwsA(problem(SyncTransportProblem.unavailable)),
    );
    for (final value in [42, '', 'another-container', 'iCloud.bad/../path']) {
      messenger.setMockMethodCallHandler(channel, (_) async => value);
      await expectLater(
        MMICloudDrive.configured(channel: channel, supported: true),
        throwsA(problem(SyncTransportProblem.invalidResponse)),
      );
    }
  });

  test('typed native errors omit sensitive messages and missing plugins fail closed', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => container);
    final drive = await port();
    for (final kind in [
      SyncTransportProblem.accountChanged,
      SyncTransportProblem.authentication,
      SyncTransportProblem.permission,
      SyncTransportProblem.quota,
      SyncTransportProblem.tooLarge,
      SyncTransportProblem.collision,
      SyncTransportProblem.invalidResponse,
      SyncTransportProblem.unavailable,
    ]) {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: kind.name, message: 'private path and account'),
      );
      await expectLater(drive.read(path, 'account'), throwsA(problem(kind)));
    }
    messenger.setMockMethodCallHandler(channel, (_) async => throw MissingPluginException());
    await expectLater(drive.accountIdentity(), throwsA(problem(SyncTransportProblem.unavailable)));
  });

  test('rejects traversal and malformed or oversized bridge data', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => container);
    final drive = await port();
    var calls = 0;
    Object? value;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return value;
    });
    for (final bad in ['', '/private/file', '$directory/../library.json', '$path/child', '$path\n']) {
      await expectLater(drive.read(bad, 'account'), throwsArgumentError);
    }
    await expectLater(drive.list(path, 'account'), throwsArgumentError);
    await expectLater(drive.read(path, ''), throwsArgumentError);
    await expectLater(drive.read(path, 'a' * 257), throwsArgumentError);
    await expectLater(
      drive.create(path, Uint8List(syncObjectLimit + 1), 'account'),
      throwsA(problem(SyncTransportProblem.tooLarge)),
    );
    expect(calls, 0);
    expect(await drive.accountIdentity(), isNull);
    expect(await drive.read(path, 'account'), isNull);
    for (value in [42, '', 'x' * 257]) {
      await expectLater(drive.accountIdentity(), throwsA(problem(SyncTransportProblem.invalidResponse)));
    }
    for (value in [
      null,
      [1],
      List.filled(100001, 'x'),
    ]) {
      await expectLater(drive.list(directory, 'account'), throwsA(problem(SyncTransportProblem.invalidResponse)));
    }
    value = [1, 2];
    await expectLater(drive.read(path, 'account'), throwsA(problem(SyncTransportProblem.invalidResponse)));
    value = Uint8List(syncObjectLimit + 1);
    await expectLater(drive.read(path, 'account'), throwsA(problem(SyncTransportProblem.tooLarge)));
    value = 'true';
    await expectLater(drive.uploaded(path, [], 'account'), throwsA(problem(SyncTransportProblem.invalidResponse)));
  });
}
