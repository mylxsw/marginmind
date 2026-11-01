import 'package:mm_design/mm_design.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';

import 'helpers.dart';
import 'study_notes_ui_test.dart' show noteFixture;
import 'vocabulary_screenshots.dart';

void main() {
  setUpAll(loadVocabularyScreenshotFonts);
  for (final dark in [true, false]) {
    testWidgets('tab chrome visual ${dark ? 'dark' : 'light'}', (tester) async {
      final original = noteFixture();
      final note = original.studyNotes.first;
      final data = original.copyWith(
        studyNotes: [
          StudyNote.fromJson({...note.toJson(), 'title': '关于专注的思考'}),
          StudyNote.fromJson({...note.toJson(), 'id': 'second', 'title': '阅读方法摘记与知识整理实践'}),
        ],
      );
      final c = await pumpApp(
        tester,
        size: const Size(1536, 960),
        prefs: {'settings.language': 'zh', 'settings.appearance': dark ? 'dark' : 'light'},
        content: InMemoryStudySetContentRepository({'demo-1': data}),
      );
      c.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      final owner = c.read(workspaceProvider('demo-1').notifier);
      owner.setLayout(MMSplitMode.secondary);
      await tester.pumpAndSettle();
      Future<void> capture(String name) async {
        final view = tester.binding.renderViews.first;
        final im = (await tester.runAsync(
          () => (view.debugLayer! as OffsetLayer).toImage(
            Rect.fromLTWH(0, 0, view.size.width, name.contains('menu') ? 360 : 104),
            pixelRatio: 2,
          ),
        ))!;
        final png = await tester.runAsync(() => im.toByteData(format: ui.ImageByteFormat.png));
        im.dispose();
        await tester.runAsync(
          () => File('${Platform.environment['MM_SCREENSHOTS']}/$name.png').writeAsBytes(png!.buffer.asUint8List()),
        );
      }

      final suffix = dark ? 'dark' : 'light';
      await capture('single-$suffix');
      owner.openStudyNote(note.id);
      owner.openStudyNote('second');
      owner.activateTab(WorkspaceTab.vocabulary);
      owner.activateTab(WorkspaceTab.review);
      owner.activateTab(WorkspaceTab.documents);
      await tester.pumpAndSettle();
      await capture('multiple-$suffix');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byKey(ValueKey('workspace-tab-note:${note.id}'))));
      await tester.pumpAndSettle();
      await capture('hover-$suffix');
      await mouse.moveTo(Offset.zero);
      tester.view.physicalSize = const Size(900, 820);
      await tester.pumpAndSettle();
      await capture('overflow-$suffix');
      await tester.tap(find.byKey(const ValueKey('workspace-tab-overflow')));
      await tester.pumpAndSettle();
      await capture('overflow-menu-$suffix');
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
    }, skip: !vocabularyScreenshotsEnabled);
  }
}
