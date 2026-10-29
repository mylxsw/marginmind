import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:marginmind/shared/card_image.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

void main() {
  testWidgets('short area images keep every edge and resolve enough pixels as the map zooms', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(1800, 1200);
    addTearDown(tester.view.reset);
    final directory = (await tester.runAsync(() => Directory.systemTemp.createTemp('area-image-rendering-')))!;
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/area.png');
    // Same wide, short proportions as a two-line PDF excerpt. Edge bands
    // detect masking at the corners as well as cropping the top or bottom.
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(Colors.white, BlendMode.src);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 1530, 12), Paint()..color = Colors.red);
      canvas.drawRect(const Rect.fromLTWH(0, 246, 1530, 12), Paint()..color = Colors.green);
      canvas.drawRect(const Rect.fromLTWH(0, 12, 12, 234), Paint()..color = Colors.blue);
      canvas.drawRect(const Rect.fromLTWH(1518, 12, 12, 234), Paint()..color = Colors.orange);
      final picture = recorder.endRecording();
      final image = await picture.toImage(1530, 258);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await file.writeAsBytes(bytes.buffer.asUint8List());
      image.dispose();
      picture.dispose();
    });
    final transform = TransformationController();
    final focus = FocusNode();
    addTearDown(transform.dispose);
    addTearDown(focus.dispose);
    var nextId = 0;
    final editor = StudySetEditor(newId: () => 'i${nextId++}', now: () => DateTime(2026));
    final (withDoc, doc) = editor.addDocument(
      StudySetContent.empty,
      title: 'PDF',
      fileName: 'sample.pdf',
      pageCount: 1,
    );
    final (content, card) = editor.createAreaExcerpt(
      withDoc,
      documentId: doc.id,
      page: 1,
      rect: const PageRect(50, 700, 560, 614),
      imageFileName: 'area.png',
      colorIndex: 0,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: MMTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CardImageScope(
          resolve: (_) => file.path,
          child: MindMapCanvas(
            content: content,
            rootTitle: 'Root',
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
    );
    await tester.pumpAndSettle();
    final cardFinder = find.byKey(ValueKey(card.id));
    final imageFinder = find.descendant(of: cardFinder, matching: find.byType(CardImage));
    final imageBox = tester.renderObject<RenderBox>(imageFinder);
    expect(imageBox.size.aspectRatio, closeTo(1530 / 258, .001), reason: 'short excerpts must not get tinted strips');
    final rawFinder = find.descendant(of: imageFinder, matching: find.byType(RawImage));
    Future<ui.Image> waitForImage(int minWidth) async {
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
        final decoded = tester.widget<RawImage>(rawFinder).image;
        if (decoded != null && decoded.width >= minWidth) return decoded;
      }
      fail('image did not resolve at least $minWidth pixels');
    }

    final width = imageBox.size.width;
    await waitForImage((width * 2).ceil());
    // No parent rebuild: the image itself must observe transform changes.
    for (final zoom in [2.21, 2.25, mapMaxScale]) {
      transform.value = Matrix4.identity()..scaleByDouble(zoom, zoom, 1, 1);
      await tester.pump();
      final decoded = await waitForImage((width * 2 * zoom).ceil());
      expect(decoded.width, lessThanOrEqualTo(1530), reason: 'never upscale the source bitmap in the cache');
      expect(decoded.width / decoded.height, closeTo(1530 / 258, .05));
    }
    final provider = tester.widget<Image>(find.descendant(of: imageFinder, matching: find.byType(Image))).image;
    transform.value = Matrix4.identity()
      ..translateByDouble(12, 8, 0, 1)
      ..scaleByDouble(2.22, 2.22, 1, 1);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Image>(find.descendant(of: imageFinder, matching: find.byType(Image))).image,
      provider,
      reason: 'panning and small zoom changes reuse the decode',
    );

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.descendant(of: cardFinder, matching: find.byType(RepaintBoundary)).first,
    );
    final origin = boundary.globalToLocal(imageBox.localToGlobal(Offset.zero));
    final pixels = (await tester.runAsync(() => boundary.toImage(pixelRatio: 4)))!;
    final data = (await tester.runAsync(() => pixels.toByteData()))!;
    Color at(double x, double y) {
      final i = (((origin.dy + y) * 4).floor() * pixels.width + ((origin.dx + x) * 4).floor()) * 4;
      return Color.fromARGB(data.getUint8(i + 3), data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
    }

    // Check the two corners AND middle of both horizontal edges.
    for (final x in [0.5, width / 2, width - 0.5]) {
      expect(at(x, .5).toARGB32(), Colors.red.toARGB32());
      expect(at(x, imageBox.size.height - .5).toARGB32(), Colors.green.toARGB32());
    }
    expect(at(.5, imageBox.size.height / 2).toARGB32(), Colors.blue.toARGB32());
    expect(at(width - .5, imageBox.size.height / 2).toARGB32(), Colors.orange.toARGB32());
    pixels.dispose();
    await tester.pumpWidget(const SizedBox());
  });
}
