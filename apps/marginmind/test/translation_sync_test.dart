import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:marginmind/features/workspace/full_translation.dart';
import 'package:marginmind/features/workspace/widgets/translation_paragraph.dart';

import 'full_translation_test.dart' show MockFullTranslationController, testHost;

import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';

class Translator implements ParagraphTranslator {
  final requests = <Completer<ParagraphTranslation>>[];
  @override
  Future<ParagraphTranslation> translate(
    TranslationParagraph p,
    String language,
    CancellationToken cancel,
    int maxTokens, {
    String? sourceLanguage,
  }) {
    final c = Completer<ParagraphTranslation>();
    requests.add(c);
    return c.future;
  }

  @override
  void close() {}
}

class SyncController extends MockFullTranslationController {
  SyncController(FullTranslationState s) : super('set', 'doc', 'zh', s);
  String? observed;
  bool reject = true;
  void change(TranslationSnapshot snapshot) => state = state.copyWith(syncSnapshot: snapshot);
  @override
  Future<void> editParagraph(TranslationParagraph p, String text, {String? expectedToken}) async {
    observed = expectedToken;
    if (reject) throw const ContentSyncActionException(ContentSyncActionFailure.stale);
  }

  @override
  Future<void> chooseTranslation(TranslationParagraph p, String choice, String token) async {
    observed = token;
    if (reject) throw const ContentSyncActionException(ContentSyncActionFailure.stale);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('paragraph choices are readable and a remote update cannot replace an open editor buffer', (
    tester,
  ) async {
    final p = TranslationParagraph(
      documentId: 'doc',
      fingerprint: 'fp',
      index: 0,
      page: 1,
      text: 'Source paragraph',
      rects: [const PageRect(0, 20, 100, 0)],
    );
    final key = textKey(p.text, 'zh');
    TranslationSegment segment(String text) => TranslationSegment(
      key: key,
      fingerprint: 'fp',
      page: 1,
      index: 0,
      text: text,
      model: 'm',
      profile: 'p',
      origin: TranslationOrigin.edited,
      at: DateTime.utc(2026),
    );
    TranslationSnapshot snapshot(String token) => TranslationSnapshot(
      documentVersion: 'doc-version',
      segments: {key: segment('Current')},
      tokens: {key: token},
      conflicts: {
        key: [
          TranslationChoice('private-a', segment('Current')),
          TranslationChoice('private-b', segment('Other wording')),
        ],
      },
    );
    final controller = SyncController(
      FullTranslationState(
        studySetId: 'set',
        documentId: 'doc',
        targetLang: 'zh',
        loading: false,
        paragraphs: [p],
        segments: {key: segment('Current')},
        syncSnapshot: snapshot('observed'),
      ),
    );
    await tester.pumpWidget(
      testHost(
        SizedBox(
          width: 360,
          child: Padding(
            padding: const EdgeInsets.only(top: 60),
            child: TranslationParagraphView(
              studySetId: 'set',
              language: 'zh',
              paragraph: p,
              value: 'Current',
              style: const TextStyle(fontSize: 14),
              placeholder: const SizedBox(),
              contextMenuBuilder: (_, _) => const SizedBox(),
            ),
          ),
        ),
        locale: const Locale('en'),
        overrides: [fullTranslationProvider(('set', 'doc', 'zh')).overrideWith(() => controller)],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Other wording'), findsOneWidget);
    expect(find.textContaining('private-a'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('translation-choice-private-b')));
    await tester.pumpAndSettle();
    expect(controller.observed, 'observed');
    expect(find.text('Other wording'), findsOneWidget);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(SelectableText).first));
    await tester.pump();
    await tester.tap(find.byTooltip('Edit Translation'));
    await tester.pump();
    final editor = find.byKey(const ValueKey('translation-editor-0'));
    await tester.enterText(editor, 'My unsaved text');
    controller.change(snapshot('remote'));
    await tester.pump();
    expect(tester.widget<TextField>(editor).controller!.text, 'My unsaved text');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.observed, 'observed');
    expect(editor, findsOneWidget);
    expect(tester.widget<TextField>(editor).controller!.text, 'My unsaved text');
    expect(find.byKey(const ValueKey('translation-choice-private-b')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    controller.reject = false;
    await tester.tap(find.byKey(const ValueKey('translation-choice-private-b')));
    await tester.pumpAndSettle();
    expect(controller.observed, 'remote');
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
  });
  test('live scheduler observes remote choices and refuses editor and AI results based on old observations', () async {
    final root = await Directory.systemTemp.createTemp('translation-scheduler-sync-');
    final left = FileSyncLedger(Directory('${root.path}/a'), libraryId: 'lib', deviceId: 'a'),
        right = FileSyncLedger(Directory('${root.path}/b'), libraryId: 'lib', deviceId: 'b');
    final a = FileLibraryStore(left.root, sync: left), b = FileLibraryStore(right.root, sync: right);
    final id = (await a.create(const NewStudySet(title: 'Study', colorIndex: 0))).id;
    final now = DateTime.utc(2026);
    final paragraph = TranslationParagraph(
      documentId: 'doc',
      fingerprint: 'fp',
      index: 0,
      page: 1,
      text: 'Source paragraph',
      rects: [const PageRect(0, 20, 100, 0)],
    );
    TranslationSegment value(String text) => TranslationSegment(
      key: textKey(paragraph.text, 'zh'),
      fingerprint: 'fp',
      page: 1,
      index: 0,
      text: text,
      model: 'm',
      profile: '',
      origin: TranslationOrigin.edited,
      at: now,
    );
    await a.importDocumentPackage(
      id,
      DocumentPackage(
        document: Document(id: 'doc', title: 'Book', fileName: 'documents/a.pdf', pageCount: 1, importedAt: now),
        files: {
          'documents/a.pdf': [1, 2, 3],
        },
      ),
    );
    await b.receiveSync(await left.pending());
    final x = await a.translationStore(id), y = await b.translationStore(id);
    await x.append('doc', 'zh', value('original'));
    await b.receiveSync(await left.pending());
    final translator = Translator();
    final scheduler = TranslationScheduler(
      documentId: 'doc',
      language: 'zh',
      paragraphs: [paragraph],
      translator: translator,
      store: x,
      model: 'm',
    );
    await scheduler.initialize();
    final key = textKey(paragraph.text, 'zh'), observed = scheduler.snapshot.tokenFor(textKey(paragraph.text, 'zh'));
    Future<void> settle() async {
      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    try {
      final request = scheduler.retranslate(paragraph);
      await settle();
      expect(translator.requests, hasLength(1));
      await y.appendGuarded('doc', 'zh', value('remote'), expectedToken: (await y.load('doc', 'zh')).tokenFor(key));
      await a.receiveSync(await right.pending());
      await settle();
      expect(scheduler.segments[key]!.text, 'remote');
      translator.requests.single.complete(const ParagraphTranslation('late ai'));
      await request;
      expect((await x.load('doc', 'zh')).segments[key]!.text, 'remote');
      await expectLater(
        scheduler.edit(paragraph, 'stale input', expectedToken: observed),
        throwsA(isA<ContentSyncActionException>()),
      );
      await scheduler.edit(paragraph, 'fresh', expectedToken: scheduler.snapshot.tokenFor(key));
      final original = scheduler.segments[key]!;
      await settle();
      expect(identical(original, scheduler.segments[key]), isTrue);
      await y.append('doc', 'zh', value('another'));
      await a.receiveSync(await right.pending());
      await settle();
      expect(scheduler.snapshot.conflicts[key], hasLength(2));
      final choice = scheduler.snapshot.conflicts[key]!.singleWhere((c) => c.segment!.text == 'fresh');
      await scheduler.choose(paragraph, choice.id, scheduler.snapshot.tokenFor(key)!);
      expect(scheduler.snapshot.conflicts, isEmpty);
      expect(scheduler.segments[key]!.text, 'fresh');
      await a.update(
        id,
        (c) => c.copyWith(
          documents: [
            Document(id: 'doc', title: 'Replaced', fileName: 'documents/replaced.pdf', pageCount: 1, importedAt: now),
          ],
        ),
      );
      await settle();
      await expectLater(scheduler.retranslate(paragraph), throwsA(isA<ContentSyncActionException>()));
      await expectLater(scheduler.edit(paragraph, 'old source'), throwsA(isA<ContentSyncActionException>()));
      final count = translator.requests.length;
      await scheduler.close();
      await a.receiveSync(await right.pending());
      expect(translator.requests, hasLength(count));
    } finally {
      await scheduler.close();
      await a.dispose();
      await b.dispose();
      await root.delete(recursive: true);
    }
  });
}
