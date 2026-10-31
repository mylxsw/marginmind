import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:marginmind/shared/note_text.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';
import 'map_keyboard_test.dart' show key;
import 'workspace_test.dart' show openFirstSet;

const noteText = '她的态度从犹豫转向支持。\n关键在于先听取意见，再表达立场。\n这也是人物关系变化的线索。';
final _now = DateTime.utc(2026);

void main() => attachedNoteTests();

void attachedNoteTests({bool native = false}) {
  for (final parent in ['c3', 'c6']) {
    testWidgets('attached note on $parent edits inside owner and retains undo', (tester) async {
      final container = await openFirstSet(tester);
      final provider = workspaceProvider('demo-1');
      final controller = container.read(provider.notifier);
      controller.selectCard(parent);
      await tester.pumpAndSettle();
      await controller.addNoteAndEdit('');
      await tester.pumpAndSettle();
      final noteId = container.read(provider).editingCardId!;
      expect(find.byKey(ValueKey(noteId)), findsNothing, reason: 'no separate map node for a note');
      expect(
        find.descendant(of: find.byKey(ValueKey(parent)), matching: find.byType(MMInlineTextField)),
        findsOneWidget,
      );
      await tester.enterText(find.byType(MMInlineTextField), noteText);
      await key(tester, LogicalKeyboardKey.enter);
      expect(container.read(provider).selectedCardId, parent);
      expect(find.text(noteText), findsNothing, reason: 'notes default to folded after creation');
      final toggle = find.byKey(ValueKey('map-notes-toggle-$parent'));
      await tester.tap(toggle, kind: PointerDeviceKind.touch);
      await tester.pumpAndSettle();
      expect(find.text(noteText), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('map-note-edit-$noteId')));
      await tester.pumpAndSettle();
      expect(find.byType(MMInlineTextField), findsOneWidget);
      expect(find.byType(NoteFormatBar), findsOneWidget);
      await tester.enterText(find.byType(MMInlineTextField), 'Cancelled');
      await key(tester, LogicalKeyboardKey.escape);
      expect(controller.content.card(noteId)!.title, noteText);
      await controller.undo();
      await tester.pumpAndSettle();
      expect(controller.content.card(noteId), isNull);
      expect(find.byKey(ValueKey(parent)), findsOneWidget);
      expect(toggle, findsNothing);
      await controller.redo();
      await tester.pumpAndSettle();
      expect(controller.content.card(noteId)!.title, noteText);
      expect(toggle, findsOneWidget);
      await tester.tap(
        find.byKey(ValueKey('map-attached-note-$noteId')),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from Map'));
      await tester.pumpAndSettle();
      expect(controller.content.node(noteId), isNull);
      await controller.undo();
      await tester.pumpAndSettle();
      expect(controller.content.node(noteId), isNotNull);
      expect(tester.takeException(), isNull);
      await settleHud(tester);
    }, semanticsEnabled: !native);
  }

  testWidgets('map arrows skip attached notes while the outline keeps note navigation', (tester) async {
    final container = await openFirstSet(tester);
    final provider = workspaceProvider('demo-1');
    final controller = container.read(provider.notifier);
    controller.selectCard('c6');
    final note = await controller.addNote('Attached');
    controller.selectCard('c6');
    final topic = await controller.addTopic('Real child', asChild: true);
    controller.selectCard('c6');
    controller.selectNeighbor(AxisDirection.right);
    expect(container.read(provider).selectedCardId, topic.id);
    controller.selectNeighbor(AxisDirection.left);
    expect(container.read(provider).selectedCardId, 'c6');
    controller.setMapView(MapViewMode.outline);
    controller.selectNeighbor(AxisDirection.right);
    expect(container.read(provider).selectedCardId, note.id);
    await tester.pumpAndSettle();
    await settleHud(tester);
  }, semanticsEnabled: !native);

  for (final dark in [false, true]) {
    testWidgets(
      'real styled ${dark ? 'dark' : 'light'} notes fold independently from topics',
      (tester) async {
        final output = native ? '${Directory.systemTemp.path}/node-attached-notes-evidence' : null;
        tester.view.physicalSize = const Size(1100, 620);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final transform = TransformationController();
        final focus = FocusNode();
        addTearDown(transform.dispose);
        addTearDown(focus.dispose);
        final content = StudySetContent(
          documents: [Document(id: 'doc', title: '人物态度', fileName: 'a.pdf', pageCount: 1, importedAt: _now)],
          annotations: [
            Annotation(
              id: 'quote',
              documentId: 'doc',
              page: 1,
              rects: const [],
              quote: '她听了笔者的意见后，说：“我支持你们的想法。”',
              colorIndex: 1,
              createdAt: _now,
            ),
          ],
          cards: [
            Card(id: 'owner', kind: CardKind.excerpt, annotationId: 'quote', createdAt: _now),
            Card(id: 'note', kind: CardKind.note, title: noteText, createdAt: _now),
            Card(id: 'second', kind: CardKind.note, title: '第二条笔记', createdAt: _now),
            Card(id: 'topic', kind: CardKind.topic, title: '新主题', createdAt: _now),
          ],
          nodes: const [
            MapNode(cardId: 'owner', parentId: null, order: 0, width: 320),
            MapNode(cardId: 'note', parentId: 'owner', order: 0),
            MapNode(cardId: 'second', parentId: 'owner', order: 1),
            MapNode(cardId: 'topic', parentId: 'owner', order: 2),
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh'),
            theme: (dark ? MMTheme.dark() : MMTheme.light()).copyWith(
              extensions: [(dark ? MMColors.dark : MMColors.light).copyWith(flat: true)],
            ),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: RepaintBoundary(
                key: const ValueKey('capture'),
                child: ColoredBox(
                  color: dark ? MMColors.dark.canvas : MMColors.light.canvas,
                  child: DefaultTextStyle.merge(
                    style: const TextStyle(fontFamily: 'PingFang SC'),
                    child: MindMapCanvas(
                      content: content,
                      rootTitle: '人物态度',
                      selectedCardId: null,
                      flashCardId: null,
                      transformation: transform,
                      focusNode: focus,
                      onSelect: (_) {},
                      onReveal: (_) {},
                      onRename: (_) {},
                      onDelete: () {},
                      onMove: (_, _, _) {},
                      onToggleCollapsed: (_) {},
                      onNavigate: (_) {},
                      onAddChild: () {},
                      onShift: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> capture(String state) async {
          if (output == null) return;
          final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('capture')));
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            await Directory(output).create(recursive: true);
            await File('$output/${dark ? 'dark' : 'light'}-$state.png').writeAsBytes(bytes!.buffer.asUint8List());
            if (native) debugPrint('NOTE_EVIDENCE=$output');
            image.dispose();
          });
        }

        expect(find.byKey(const ValueKey('note')), findsNothing);
        expect(find.byKey(const ValueKey('second')), findsNothing);
        expect(find.byKey(const ValueKey('topic')), findsOneWidget);
        final folded = tester.getSize(find.byKey(const ValueKey('owner')));
        await capture('collapsed');
        await tester.tap(find.byKey(const ValueKey('map-notes-toggle-owner')));
        await tester.pumpAndSettle();
        expect(find.text(noteText), findsOneWidget);
        expect(find.text('第二条笔记'), findsOneWidget);
        expect(tester.getSize(find.byKey(const ValueKey('owner'))).height, greaterThan(folded.height));
        expect(find.byKey(const ValueKey('topic')), findsOneWidget);
        await capture('expanded');
        await tester.tap(find.byKey(const ValueKey('map-notes-toggle-owner')));
        await tester.pumpAndSettle();
        expect(find.text(noteText), findsNothing);
        expect(tester.getSize(find.byKey(const ValueKey('owner'))), folded);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      semanticsEnabled: !native,
    );
  }
}
