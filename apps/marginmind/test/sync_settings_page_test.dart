import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:marginmind/settings/sync_settings_controller.dart';
import 'package:marginmind/settings/sync_settings_page.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_sync/mm_sync.dart';

class _Secrets implements SecretStore {
  @override
  Future<String?> read(String account) async => null;
  @override
  Future<void> write(String account, String value) async {}
  @override
  Future<void> delete(String account) async {}
}

class _Settings extends SyncSettingsController {
  _Settings({bool available = true})
    : super(
        FileLibraryStore(Directory('unused')),
        FileVocabularyStore(Directory('unused')),
        secrets: _Secrets(),
        canActivate: available,
        canStoreSecrets: available,
      ) {
    initialized = true;
  }
  final actions = <Object>[];
  SyncSettingsFailure? nextFailure;
  Completer<void>? gate;
  Future<void> action(Object value) async {
    actions.add(value);
    busy = true;
    notifyListeners();
    if (gate != null) await gate!.future;
    busy = false;
    failure = nextFailure;
    notifyListeners();
  }

  @override
  Future<void> activate({String? existingLibraryId, required String deviceName}) async {
    await action((existingLibraryId, deviceName));
    if (failure == null) {
      restartRequired = true;
      libraryId = existingLibraryId ?? 'new-library';
      notifyListeners();
    }
  }

  @override
  Future<void> cancelActivation() async {
    restartRequired = false;
    libraryId = null;
    notifyListeners();
  }

  @override
  Future<void> connectWebDav({required String directory, required String username, required String password}) =>
      action((directory, username, password));
  @override
  Future<void> connectICloud() => action('icloud');
  @override
  Future<void> syncOnce() => action('sync');
  @override
  Future<void> downloadResource(SyncResourceStatus resource) => action(resource);
  @override
  Future<void> refreshResources() => action('resources');
  @override
  Future<void> pause() => action('pause');
  @override
  Future<void> initialize() => action('initialize');
  void publish() => notifyListeners();
}

void main() {
  late _Settings service;
  setUp(() => service = _Settings());
  tearDown(() => service.dispose());
  Future<void> pump(WidgetTester tester, {String locale = 'en', double width = 700, bool absent = false}) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [syncSettingsControllerProvider.overrideWithValue(absent ? null : service)],
        child: MaterialApp(
          theme: MMTheme.light(),
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SyncSettingsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  void active() {
    service.libraryId = 'library-code';
    service.setup = SyncSetup(
      libraryId: 'library-code',
      deviceId: 'private-device',
      deviceName: 'My Mac',
      joining: false,
    );
    service.target = SyncTarget(
      service: 'webdav',
      account: 'alice',
      location: 'https://dav.test/',
      libraryId: 'library-code',
    );
  }

  testWidgets('prepare and cancel clearly retain local mode until restart', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const ValueKey('sync-device-name')), 'Mac');
    await tap(tester, 'sync-prepare');
    expect(service.actions, [(null, 'Mac')]);
    expect(find.byKey(const ValueKey('sync-restart')), findsOneWidget);
    expect(find.byKey(const ValueKey('sync-once')), findsNothing);
    await tap(tester, 'sync-cancel-activation');
    expect(find.byKey(const ValueKey('sync-prepare')), findsOneWidget);
  });

  testWidgets('join asks for exact code; failed preparation preserves input', (tester) async {
    service.nextFailure = SyncSettingsFailure.invalidInput;
    await pump(tester);
    await tester.tap(find.byType(MMPopUpButton<bool>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Join an existing library').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('sync-library-code')), 'shared');
    await tester.enterText(find.byKey(const ValueKey('sync-device-name')), 'Phone');
    await tap(tester, 'sync-prepare');
    expect(service.actions.single, ('shared', 'Phone'));
    expect(find.text('shared'), findsOneWidget);
    expect(find.byKey(const ValueKey('sync-restart')), findsNothing);
  });

  testWidgets('credentials stay on failure and clear only after saved connection', (tester) async {
    active();
    service.nextFailure = SyncSettingsFailure.authentication;
    await pump(tester);
    await tester.enterText(find.byKey(const ValueKey('sync-password')), 'secret');
    await tap(tester, 'sync-connect');
    final input = tester.widget<MMTextField>(find.byKey(const ValueKey('sync-password')));
    expect(input.obscureText, true);
    expect(input.controller!.text, 'secret');
    expect(service.actions.single, ('https://dav.test/', 'alice', 'secret'));
    service.nextFailure = null;
    await tap(tester, 'sync-connect');
    expect(input.controller!.text, '');
    await tap(tester, 'sync-icloud');
    expect(service.actions.last, 'icloud');
  });

  testWidgets('busy cycle disables writes but offers pause; staged differs from confirmed', (tester) async {
    active();
    service.pending = 4;
    await pump(tester);
    await tap(tester, 'sync-once');
    expect(service.actions.last, 'sync');
    service.busy = true;
    service.publish();
    await tester.pumpAndSettle();
    expect(tester.widget<MMButton>(find.byKey(const ValueKey('sync-once'))).onPressed, isNull);
    await tap(tester, 'sync-pause');
    expect(service.actions.last, 'pause');
    service.result = const SyncRunResult(received: 2, confirmed: 0, staged: 5);
    service.publish();
    await tester.pumpAndSettle();
    expect(find.textContaining('awaiting cloud confirmation: 5'), findsOneWidget);
    expect(find.textContaining('confirmed by the service: 0'), findsOneWidget);
  });

  testWidgets('Chinese narrow layout keeps status and account controls readable', (tester) async {
    active();
    await pump(tester, width: 375, locale: 'zh');
    expect(find.text('library-code'), findsOneWidget);
    expect(find.textContaining('本机名称: My Mac'), findsOneWidget);
    await tap(tester, 'sync-connect');
    expect(tester.takeException(), isNull);
    expect(find.textContaining('文件按需下载'), findsOneWidget);
    expect(find.text('private-device'), findsNothing);
  });

  testWidgets('resource availability distinguishes missing and changed files and guards downloads', (tester) async {
    active();
    final missing = SyncResourceStatus(
      'set',
      'document/missing',
      'Missing',
      'rev',
      SyncResourceAvailability.missing,
      100,
    );
    service.resources = [
      missing,
      const SyncResourceStatus('set', 'changed', 'Changed', 'rev', SyncResourceAvailability.changed, 10),
      const SyncResourceStatus('set', 'ready', 'Ready', 'rev', SyncResourceAvailability.available, 10),
      const SyncResourceStatus('set', 'unknown', 'Unknown', 'rev', SyncResourceAvailability.unverified, 0),
    ];
    await pump(tester, width: 375);
    expect(find.text('Not fully downloaded'), findsOneWidget);
    expect(find.text('Verified and available'), findsOneWidget);
    await tap(tester, 'sync-download-document/missing');
    expect(service.actions.last, missing);
    service.busy = true;
    service.publish();
    await tester.pumpAndSettle();
    expect(tester.widget<MMButton>(find.byKey(const ValueKey('sync-download-document/missing'))).onPressed, isNull);
    service.busy = false;
    service.publish();
    await tester.pumpAndSettle();
    await tap(tester, 'sync-resources-refresh');
    expect(service.actions.last, 'resources');
  });

  testWidgets('unavailable providers and platforms do not offer activation', (tester) async {
    await pump(tester, absent: true);
    expect(find.byKey(const ValueKey('sync-prepare')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
    service = _Settings(available: false);
    await pump(tester);
    expect(find.byKey(const ValueKey('sync-prepare')), findsNothing);
  });

  testWidgets('typed failures expose actionable messages without raw errors', (tester) async {
    active();
    await pump(tester);
    for (final failure in [
      SyncSettingsFailure.incompleteLibrary,
      SyncSettingsFailure.missingLibrary,
      SyncSettingsFailure.unsupported,
      SyncSettingsFailure.accountChanged,
      SyncSettingsFailure.legacyProtocol,
      SyncSettingsFailure.missingHistory,
      SyncSettingsFailure.paused,
      SyncSettingsFailure.storage,
    ]) {
      service.failure = failure;
      service.publish();
      await tester.pumpAndSettle();
      expect(find.byType(Semantics), findsWidgets);
      expect(tester.takeException(), isNull);
    }
    service.initialized = false;
    service.publish();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reload status'));
    await tester.pumpAndSettle();
    expect(service.actions.last, 'initialize');
  });
}
