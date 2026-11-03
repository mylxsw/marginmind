import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/library/share_import_sheet.dart';
import 'package:marginmind/features/workspace/document_import.dart';
import 'package:marginmind/features/workspace/workspace_browser.dart';
import 'package:marginmind/shared/paste_web_url.dart';
import 'package:mm_book/mm_book.dart' as book;
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import 'helpers.dart';

class _Inbox implements MMIncomingShareSource {
  _Inbox(this.batches);
  final List<MMIncomingShareBatch> batches;
  final updates = StreamController<void>.broadcast();
  final completed = <String>[];
  Future<void> Function(String)? onComplete;
  bool failRead = false;

  @override
  Stream<void> get changes => updates.stream;
  @override
  Future<List<MMIncomingShareBatch>> pending() async {
    if (failRead) throw StateError('read failed');
    return batches.toList();
  }

  @override
  Future<void> complete(String id) async {
    await onComplete?.call(id);
    completed.add(id);
    batches.removeWhere((b) => b.id == id);
  }

  @override
  void dispose() => unawaited(updates.close());
}

class _PausedImporter extends DocumentImporter {
  final gate = Completer<void>();
  @override
  Future<DocumentPackage> prepare(
    MMDocumentFile file, {
    required String id,
    required DateTime now,
    book.BookCancellationToken? cancellation,
  }) async {
    await gate.future;
    return super.prepare(file, id: id, now: now, cancellation: cancellation);
  }
}

Future<void> _drain(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 50 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
  expect(done(), isTrue);
}

void main() {
  setUpAll(() async {
    if (Platform.environment['GUL659_CAPTURE'] != '1') return;
    final font = Platform.environment['GUL659_FONT'];
    if (font == null) throw StateError('Set GUL659_FONT to a local CJK font for visual evidence');
    final data = ByteData.sublistView(await File(font).readAsBytes());
    for (final family in [
      '.AppleSystemUIFont',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      'Roboto',
      'PingFang SC',
      'Noto Sans CJK SC',
      'Noto Sans SC',
    ]) {
      await (FontLoader(family)..addFont(Future.value(data))).load();
    }
    for (final asset in [
      ('packages/lucide_icons_flutter/Lucide', 'packages/lucide_icons_flutter/assets/lucide.ttf'),
      ('packages/cupertino_icons/CupertinoIcons', 'packages/cupertino_icons/assets/CupertinoIcons.ttf'),
    ]) {
      await (FontLoader(asset.$1)..addFont(rootBundle.load(asset.$2))).load();
    }
  });
  test('destinations pin the recent set, sort consistently and search without case', () {
    final sets = DemoLibrary.studySets(testNow);
    final recent = sets.last.id;
    final ordered = shareImportStudySets(sets, recent, '');
    expect(ordered.first.id, recent);
    expect(shareImportStudySets(sets, 'deleted', ' no result '), isEmpty);
    expect(shareImportStudySets([sets.first.copyWith(title: 'Research')], null, 'RESEARCH').single.id, sets.first.id);
  });

  testWidgets('cold inbox serializes shares and deduplicates notifications while choosing', (tester) async {
    final source = _Inbox([
      MMIncomingShareBatch(id: 'a', url: Uri.parse('https://one.example')),
      MMIncomingShareBatch(id: 'b', url: Uri.parse('https://two.example')),
    ]);
    addTearDown(source.dispose);
    final container = await pumpApp(tester, overrides: [incomingSharesProvider.overrideWithValue(source)]);
    expect(find.byType(ShareImportSheet), findsOneWidget);
    expect(find.text('one.example'), findsOneWidget);
    source.updates.add(null);
    source.updates.add(null);
    await tester.pumpAndSettle();
    expect(find.byType(ShareImportSheet), findsOneWidget);
    await tester.tap(find.widgetWithText(MMButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(source.completed, ['a']);
    expect(find.text('two.example'), findsOneWidget);
    await tester.tap(find.widgetWithText(MMButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(source.completed, ['a', 'b']);
    expect(container.read(navigationProvider), isA<LibraryRoute>());
  });

  testWidgets('URL creates a named study set and retains its browser across navigation', (tester) async {
    final source = _Inbox([
      MMIncomingShareBatch(id: 'url', url: Uri.parse('https://example.com/article'), title: 'Article'),
    ]);
    addTearDown(source.dispose);
    final container = await pumpApp(tester, sets: [], overrides: [incomingSharesProvider.overrideWithValue(source)]);
    expect(tester.widget<TextField>(find.byType(TextField).last).controller!.text, 'Article');
    await tester.enterText(find.byType(TextField).last, '  My Reading  ');
    await tester.tap(find.widgetWithText(MMButton, 'Create and Import'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    final created = container.read(studySetsProvider).value!.single;
    expect(created.title, 'My Reading');
    expect(container.read(workspaceBrowserProvider(created.id)).session!.url.path, '/article');
    expect(source.completed, ['url']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('search chooses a visible existing destination and disables empty results', (tester) async {
    final source = _Inbox([]);
    addTearDown(source.dispose);
    final container = await pumpApp(tester, overrides: [incomingSharesProvider.overrideWithValue(source)]);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    source.batches.add(MMIncomingShareBatch(id: 'url', url: Uri.parse('https://example.com')));
    source.updates.add(null);
    await tester.pumpAndSettle();
    final rows = find.descendant(of: find.byType(ShareImportSheet), matching: find.byType(MMInteractive));
    expect(rows, findsWidgets);
    expect(find.text('Recent'), findsOneWidget);
    await tester.enterText(
      find.descendant(of: find.byType(ShareImportSheet), matching: find.byType(TextField)),
      'zzzz',
    );
    await tester.pumpAndSettle();
    expect(tester.widget<MMButton>(find.widgetWithText(MMButton, 'Import')).onPressed, isNull);
    final destination = container.read(studySetsProvider).value!.last;
    await tester.enterText(
      find.descendant(of: find.byType(ShareImportSheet), matching: find.byType(TextField)),
      destination.title,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MMButton, 'Import'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect((container.read(navigationProvider) as WorkspaceRoute).studySetId, destination.id);
    expect(container.read(workspaceBrowserProvider(destination.id)).session!.url.host, 'example.com');
    expect(source.completed, ['url']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('file acknowledgements follow parsing and preserve partial successes', (tester) async {
    final directory = (await tester.runAsync(() => Directory.systemTemp.createTemp('incoming-test-')))!;
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final path = '${directory.path}/notes.md';
    await tester.runAsync(() => File(path).writeAsString('# Document\n\nShared body'));
    final source = _Inbox([
      MMIncomingShareBatch(
        id: 'files',
        files: [(path: path, name: 'notes.md'), (path: '${directory.path}/missing.epub', name: 'missing.epub')],
      ),
    ]);
    addTearDown(source.dispose);
    final importer = _PausedImporter();
    final content = InMemoryStudySetContentRepository();
    final container = await pumpApp(
      tester,
      sets: [],
      content: content,
      overrides: [
        incomingSharesProvider.overrideWithValue(source),
        documentImporterProvider.overrideWithValue(importer),
      ],
    );
    source.onComplete = (_) async {
      final created = container.read(studySetsProvider).value!.single;
      expect((await content.load(created.id)).documents.length, 1);
      expect(await File(path).exists(), isTrue);
      await directory.delete(recursive: true);
    };
    await tester.tap(find.widgetWithText(MMButton, 'Create and Import'));
    await tester.pumpAndSettle();
    expect(source.completed, isEmpty);
    source.updates.add(null);
    importer.gate.complete();
    await _drain(tester, () => source.completed.isNotEmpty);
    final created = container.read(studySetsProvider).value!.single;
    expect(created.title, 'notes');
    expect((await content.load(created.id)).documents.single.title, 'Document');
    expect(source.completed, ['files']);
    await settleHud(tester);
  });

  testWidgets('native errors and read failures recover without creating a set', (tester) async {
    final source = _Inbox([
      const MMIncomingShareBatch(id: 'bad', error: 'unsupported'),
      const MMIncomingShareBatch(id: 'large', error: 'limit'),
    ]);
    source.failRead = true;
    addTearDown(source.dispose);
    final container = await pumpApp(tester, sets: [], overrides: [incomingSharesProvider.overrideWithValue(source)]);
    for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    source.failRead = false;
    for (final state in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(source.completed, ['bad', 'large']);
    expect(container.read(studySetsProvider).value, isEmpty);
    expect(find.byType(ShareImportSheet), findsNothing);
    await settleHud(tester);
  });

  testWidgets('notification and cleanup failures leave later batches usable', (tester) async {
    final source = _Inbox([
      const MMIncomingShareBatch(id: 'first', error: 'unavailable'),
      const MMIncomingShareBatch(id: 'second', error: 'unsupported'),
    ]);
    source.onComplete = (id) async {
      if (id == 'first') throw StateError('cleanup failed');
    };
    addTearDown(source.dispose);
    await pumpApp(tester, overrides: [incomingSharesProvider.overrideWithValue(source)]);
    expect(source.completed, ['second']);
    source.updates.addError(StateError('staging failed'));
    source.updates.add(null);
    await tester.pumpAndSettle();
    expect(find.byType(ShareImportSheet), findsNothing);
    expect(source.completed, ['second']);
    await settleHud(tester);
  });

  testWidgets('files can join an existing set and an all-failed new import rolls back', (tester) async {
    final directory = (await tester.runAsync(() => Directory.systemTemp.createTemp('incoming-existing-')))!;
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/shared.md';
    await tester.runAsync(() => File(path).writeAsString('# Shared\n\nContent'));
    final source = _Inbox([]);
    addTearDown(source.dispose);
    final container = await pumpApp(tester, overrides: [incomingSharesProvider.overrideWithValue(source)]);
    final originalCount = container.read(studySetsProvider).value!.length;
    source.batches.add(MMIncomingShareBatch(id: 'join', files: [(path: path, name: 'shared.md')]));
    source.updates.add(null);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MMButton, 'Import'));
    await _drain(tester, () => source.completed.contains('join'));
    final id = (container.read(navigationProvider) as WorkspaceRoute).studySetId;
    expect(
      (await container.read(contentRepositoryProvider).load(id)).documents.any((d) => d.title == 'Shared'),
      isTrue,
    );
    source.batches.add(const MMIncomingShareBatch(id: 'fail', files: [(path: '/missing.epub', name: 'missing.epub')]));
    source.updates.add(null);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(ShareImportSheet), matching: find.text('New Study Set')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MMButton, 'Create and Import'));
    await _drain(tester, () => source.completed.contains('fail'));
    expect(container.read(studySetsProvider).value!.length, originalCount);
    await settleHud(tester);
  });

  testWidgets('paste action reads only after a tap, extracts prose and explains invalid content', (tester) async {
    var reads = 0;
    var clipboard = 'Article https://example.com/read。';
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        reads++;
        return {'text': clipboard};
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await pumpApp(tester);
    Uri? pasted;
    final context = tester.element(find.byType(IncomingShareHost));
    unawaited(
      showMMSheet<void>(
        context: context,
        builder: (_) => MMSheet(
          title: 'Paste',
          child: PasteWebUrlButton(onPaste: (url) => pasted = url),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(reads, 0);
    await tester.tap(find.widgetWithText(MMButton, 'Paste Link'));
    await tester.pumpAndSettle();
    expect(pasted!.path, '/read');
    clipboard = 'not a link';
    await tester.tap(find.widgetWithText(MMButton, 'Paste Link'));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.text('No valid web link on the clipboard.'), findsOneWidget);
    await settleHud(tester);
  });

  for (final phone in [true, false]) {
    for (final dark in [false, true]) {
      testWidgets('share picker fits ${phone ? 'phone' : 'tablet'} ${dark ? 'dark' : 'light'}', (tester) async {
        final source = _Inbox([
          MMIncomingShareBatch(id: 'preview', url: Uri.parse('https://example.com/learning'), title: '如何让知识留下来'),
        ]);
        addTearDown(source.dispose);
        await pumpApp(
          tester,
          size: phone ? const Size(393, 852) : const Size(1024, 768),
          prefs: {'settings.appearance': dark ? 'dark' : 'light', 'settings.language': 'zh'},
          overrides: [
            incomingSharesProvider.overrideWithValue(source),
            touchPlatformProvider.overrideWithValue(true),
            phoneProvider.overrideWithValue(phone),
          ],
        );
        expect(find.byType(ShareImportSheet), findsOneWidget);
        expect(find.byType(MMBottomSheet), phone ? findsOneWidget : findsNothing);
        expect(tester.takeException(), isNull);
        final submit = find.widgetWithText(MMButton, '导入');
        expect(submit.hitTestable(), findsOneWidget);
        if (Platform.environment['GUL659_CAPTURE'] == '1') {
          await expectLater(
            find.byType(MarginMindApp),
            matchesGoldenFile(
              '../../../docs/evidence/gul-659/${phone ? 'phone' : 'tablet'}-${dark ? 'dark' : 'light'}.png',
            ),
          );
        }
        await tester.tap(find.widgetWithText(MMButton, '取消'));
        await tester.pumpAndSettle();
      });
    }
  }
}
