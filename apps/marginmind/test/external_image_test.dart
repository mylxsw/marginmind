import 'dart:async';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/review/review_screen.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/workspace/widgets/card_details.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:marginmind/shared/card_image.dart';
import 'package:marginmind/shared/image_picker.dart';
import 'package:marginmind/shared/pdf_drop.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import 'helpers.dart';
import 'map_keyboard_test.dart' show key, focusMap;

class ImageRepository extends InMemoryStudySetContentRepository {
  ImageRepository() : super({'demo-1': demoContent()});
  Completer<void>? wait;
  bool fail = false;
  @override
  Future<String> importImage(String studySetId, String sourcePath) async {
    await wait?.future;
    if (fail) throw const FormatException('invalid image');
    return 'images/test.png';
  }
}

void main() {
  test('batch imports nest under excerpts, flash, undo/redo once; failures leave history intact', () async {
    final repo = ImageRepository();
    final container = ProviderContainer(overrides: await testOverrides(content: repo));
    addTearDown(container.dispose);
    final provider = workspaceProvider('demo-1');
    container.listen(provider, (_, _) {});
    await container.read(contentProvider('demo-1').future);
    final controller = container.read(provider.notifier);
    controller.selectCard('c6');
    final before = controller.content;
    expect(await controller.insertImages(), isFalse);
    await controller.insertImages(paths: ['/tmp/diagram.PNG', '/tmp/photo.jpeg']);
    final added = controller.content.cards.skip(before.cards.length).toList();
    expect(added, hasLength(2));
    expect(added.map((c) => c.annotationId), everyElement(isNull));
    expect(added.map((c) => controller.content.node(c.id)!.parentId), everyElement('c6'));
    expect(added.first.imageOrigin, 'file:diagram.PNG');
    expect(container.read(provider).flashCardId, added.last.id);
    await controller.undo();
    expect(controller.content.cards, before.cards);
    await controller.redo();
    expect(controller.content.cards.length, before.cards.length + 2);
    await controller.undo();
    await expectLater(controller.insertImages(paths: ['ok.png', 'bad.gif']), throwsFormatException);
    expect(controller.content.cards, before.cards);
    expect(container.read(provider).canRedo, isTrue);
    repo.fail = true;
    await expectLater(controller.insertImages(paths: ['corrupt.jpg']), throwsFormatException);
    expect(controller.content.cards, before.cards);
    repo.fail = false;
    await controller.insertImages(bytes: Uint8List.fromList([1, 2, 3]), pasted: true);
    expect(controller.content.cards.last.imageOrigin, 'pasted');
    expect(repo.images[controller.content.cards.last.imageFileName], [1, 2, 3]);
  });

  test('import blocks undo during copying and supports undo after completion', () async {
    final repo = ImageRepository()..wait = Completer<void>();
    final container = ProviderContainer(overrides: await testOverrides(content: repo));
    addTearDown(container.dispose);
    final provider = workspaceProvider('demo-1');
    container.listen(provider, (_, _) {});
    await container.read(contentProvider('demo-1').future);
    final controller = container.read(provider.notifier);
    final before = controller.content.cards.length;
    final insertion = controller.insertImages(paths: ['chart.png']);
    expect(await controller.insertImages(paths: ['duplicate.png']), isFalse);
    final undo = controller.undo();
    repo.wait!.complete();
    await insertion;
    expect(await undo, isNull);
    await controller.undo();
    expect(controller.content.cards.length, before);
    await controller.redo();
    expect(controller.content.cards.length, before + 1);
    expect(controller.content.node(controller.content.cards.last.id)!.parentId, isNull);
  });

  testWidgets('pastes screenshots and Finder files; internal nodes take precedence', (tester) async {
    final container = await pumpApp(tester, content: ImageRepository());
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    final controller = container.read(workspaceProvider('demo-1').notifier);
    Object? image = {
      'bytes': Uint8List.fromList([1, 2, 3]),
    };
    String? internal;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      MMMapClipboard.channel,
      (call) async => call.method == 'readImage' ? image : {'text': 'ignored screenshot text', 'internal': internal},
    );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        MMMapClipboard.channel,
        null,
      ),
    );
    await focusMap(tester);
    await key(tester, LogicalKeyboardKey.keyV, primary: true);
    expect(controller.content.cards.last.kind, CardKind.image);
    final imageCount = controller.content.cards.length;
    controller.showDetails(controller.content.cards.last.id);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(CardDetails), matching: find.byType(EditableText)));
    await key(tester, LogicalKeyboardKey.keyV, primary: true);
    expect(controller.content.cards.length, imageCount);
    controller.closePanel();
    await tester.pumpAndSettle();
    image = {'path': '/tmp/finder.jpg'};
    await controller.pasteSelection();
    expect(controller.content.cards.last.imageOrigin, 'pasted');
    internal = MapClipboard.encode(MapClipboard.fromText('Node'));
    final beforeText = controller.content.cards.length;
    await controller.pasteSelection(imagesOnly: true);
    expect(controller.content.cards.length, beforeText);
    await controller.pasteSelection();
    expect(controller.content.cards.last.title, 'Node');
    expect(controller.content.cards.last.kind, isNot(CardKind.image));
    internal = null;
    image = null;
    final afterText = controller.content.cards.length;
    await controller.pasteSelection(imagesOnly: true);
    expect(controller.content.cards.length, afterText);
    await tester.pumpAndSettle();
    await settleHud(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('picker, drop, question and Space preview are connected', (tester) async {
    final container = await pumpApp(
      tester,
      overrides: [
        imagePickerProvider.overrideWithValue((_) async => ['/tmp/picked.png']),
      ],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Insert Image…'));
    await tester.pumpAndSettle();
    final provider = workspaceProvider('demo-1');
    final controller = container.read(provider.notifier);
    expect(controller.content.cards.last.imageOrigin, 'file:picked.png');
    final drop = tester.widgetList<PdfDropTarget>(find.byType(PdfDropTarget)).firstWhere((w) => w.onImageDrop != null);
    drop.onImageDrop!([(path: '/tmp/dropped.jpeg', name: 'dropped.jpeg')]);
    await tester.pumpAndSettle();
    final card = controller.content.cards.last;
    expect(card.imageOrigin, 'file:dropped.jpeg');
    controller.showDetails(card.id);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(of: find.byType(CardDetails), matching: find.byType(EditableText)),
      'What does the diagram explain?',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.content.card(card.id)!.title, 'What does the diagram explain?');
    controller.closePanel();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    await settleHud(tester);
  });

  testWidgets('review front conceals images; back shows the image without a source', (tester) async {
    var seq = 0;
    final editor = StudySetEditor(newId: () => '${seq++}', now: () => testNow);
    final (c, topic) = editor.addTopic(StudySetContent.empty, title: 'Biology');
    final (content, image) = editor.createImage(c, imageFileName: 'images/a.png', parentId: topic.id);
    for (final question in ['', 'How does this work?']) {
      final face = buildReviewFace(image.copyWith(title: question), content);
      expect(face.front.title, question.isEmpty ? 'Biology' : question);
      expect(face.front.path, ['Biology']);
      expect(face.back.source, isNull);
      for (final revealed in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: MMTheme.light(),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Scaffold(
              body: ReviewCardView(face: face, revealed: revealed, onRevealSource: () => fail('no source')),
            ),
          ),
        );
        expect(find.byType(CardImage), revealed ? findsOneWidget : findsNothing);
        expect(find.byType(MMButton), findsNothing);
        expect(
          find.text(question.isEmpty ? 'Biology' : question),
          question.isEmpty ? findsNWidgets(2) : findsOneWidget,
        );
      }
    }
  });
}
