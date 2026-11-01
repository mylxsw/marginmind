import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/library/library_controller.dart';
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';
import 'package:marginmind/features/workspace/phone_reader_controls_controller.dart';
import 'package:mm_design/mm_design.dart';

import 'adaptive_layout_test.dart' show Device, iphone, iphoneLandscape, openWorkspace, pumpDevice;

const android = (name: 'Android portrait', size: Size(411, 914), safe: EdgeInsets.fromLTRB(0, 50, 0, 24), touch: true);
const androidLandscape = (
  name: 'Android landscape',
  size: Size(914, 411),
  safe: EdgeInsets.fromLTRB(50, 0, 0, 24),
  touch: true,
);

void main() {
  for (final Device device in [iphone, android, iphoneLandscape, androidLandscape]) {
    testWidgets('${device.name}: library title fits and search still filters', (tester) async {
      tester.view.display.size = device.size;
      addTearDown(tester.view.display.resetSize);
      final container = await pumpDevice(tester, device);
      // A compact phone shows the large "Library" title for all study sets (GUL-635).
      final compactPhone = device.size.width < device.size.height;
      final title = find.descendant(
        of: find.byWidgetPredicate((w) => w is MMToolbar || w is PreferredSize),
        matching: find.text(compactPhone ? 'Library' : 'All Study Sets'),
      );
      expect(title, findsOneWidget);
      expect(tester.renderObject<RenderParagraph>(title).didExceedMaxLines, isFalse);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), 'no matching study set');
      await tester.pumpAndSettle();
      expect(container.read(libraryViewProvider).query.search, 'no matching study set');
      expect(find.text('注意力与专注'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${device.name}: page controls leave the first content line clear', (tester) async {
      tester.view.display.size = device.size;
      addTearDown(tester.view.display.resetSize);
      await openWorkspace(tester, device);
      final viewport = tester.getRect(find.byKey(const ValueKey('pdf-placeholder-c1')));
      final compactPhone = usePhoneReaderControls(tester.element(find.byType(ReaderPane)));
      final navigation = tester.getRect(
        find.byKey(ValueKey(compactPhone ? 'phone-reader-page' : 'reader-page-navigation')),
      );
      // The PDF's first line must have clear space even before it has loaded.
      expect(navigation.overlaps(Rect.fromLTWH(viewport.left, viewport.top, viewport.width, 24)), isFalse);
      if (!compactPhone && device.size.height < 500) {
        // Docked controls cannot cover any PDF text, at any scroll position.
        expect(navigation.overlaps(viewport), isFalse);
      }
      if (compactPhone) {
        expect(find.byKey(const ValueKey('phone-reader-page')).hitTestable(), findsOneWidget);
      } else {
        expect(find.byKey(const ValueKey('reader-page-badge')).hitTestable(), findsOneWidget);
        expect(find.byKey(const ValueKey('reader-page-progress')).hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      // Resizing the same reader restores the existing floating layout.
      tester.view.physicalSize = const Size(402, 874);
      await tester.pumpAndSettle();
      final portraitViewport = tester.getRect(find.byKey(const ValueKey('pdf-placeholder-c1')));
      expect(tester.getRect(find.byKey(const ValueKey('phone-reader-page'))).overlaps(portraitViewport), isTrue);
      expect(find.byType(ReaderPane), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
