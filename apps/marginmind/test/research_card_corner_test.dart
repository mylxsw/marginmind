import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('research stripe stays inside ${dark ? 'dark' : 'light'} card corners', (tester) async {
      final colors = dark ? MMColors.dark : MMColors.light;
      final transform = TransformationController();
      final focus = FocusNode();
      addTearDown(transform.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: (dark ? MMTheme.dark() : MMTheme.light()).copyWith(extensions: [colors.copyWith(flat: true)]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: RepaintBoundary(
              key: const ValueKey('capture'),
              child: MindMapCanvas(
                content: StudySetContent(
                  researchNotes: [
                    ResearchNote(
                      id: 'note',
                      title: 'Research',
                      question: 'Why?',
                      body: 'A short research note.',
                      createdAt: DateTime(2026),
                      updatedAt: DateTime(2026),
                    ),
                  ],
                  cards: [
                    Card(
                      id: 'research',
                      kind: CardKind.research,
                      researchNoteId: 'note',
                      title: 'Research',
                      createdAt: DateTime(2026),
                    ),
                  ],
                  nodes: const [MapNode(cardId: 'research', order: 0, width: 240)],
                ),
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
        ),
      );
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('capture')));
      final rect = tester.getRect(find.byKey(const ValueKey('research')));
      final origin = boundary.globalToLocal(rect.topLeft);
      final scale = mapScale(transform.value);
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 3);
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        Color pixel(double x, double y) {
          final offset = ((y * 3).floor() * image.width + (x * 3).floor()) * 4;
          return Color.fromARGB(
            bytes.getUint8(offset + 3),
            bytes.getUint8(offset),
            bytes.getUint8(offset + 1),
            bytes.getUint8(offset + 2),
          );
        }

        final x = origin.dx + 2 * scale;
        expect(pixel(x, origin.dy + 2 * scale), isNot(colors.research), reason: 'top corner must be clipped');
        expect(
          pixel(x, origin.dy + rect.height - 2 * scale),
          isNot(colors.research),
          reason: 'bottom corner must be clipped',
        );
        expect(
          pixel(x, origin.dy + rect.height / 2),
          colors.research,
          reason: 'the middle of the stripe remains visible',
        );
        image.dispose();
      });
      expect(tester.takeException(), isNull);
    });
  }
}
