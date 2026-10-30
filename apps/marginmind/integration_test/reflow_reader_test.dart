import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/reflow_session.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/settings/app_settings.dart';
import 'package:mm_core/testing.dart';

import '../test/helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('import → read → excerpt → resize → source', (tester) async {
    final directory = await Directory.systemTemp.createTemp('marginmind-reflow-');
    addTearDown(() => directory.delete(recursive: true));
    final file = await File('${directory.path}/Reading.md').writeAsString('''# Learning by reading

Source anchors keep annotations stable when the text is reflowed.

A remembered position belongs to the original text, independent of font size.

## Retrieval practice

Recall a passage and connect it to your map.

${List.generate(30, (i) => 'Paragraph $i: Read, select, annotate and return to the source. 中文文字和 emoji 😀 remain intact.').join('\n\n')}
''');
    final repo = InMemoryStudySetContentRepository();
    final container = await pumpApp(
      tester,
      content: repo,
      pdfPicker: (_) async => [(path: file.path, name: 'Reading.md')],
      size: const Size(1280, 720),
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    Future<void> shot(String name) async {
      const output = String.fromEnvironment('GUL576_SHOTS');
      if (output.isEmpty) return;
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      final result = await Process.run('python3', [
        '-c',
        'from PIL import ImageGrab; import sys; ImageGrab.grab().save(sys.argv[1])',
        '$output/$name.png',
      ]);
      expect(result.exitCode, 0, reason: 'Native X11 screenshot: ${result.stderr}');
    }

    await shot('01-import');
    await tester.tap(find.text('Import Document…').last);
    final workspace = container.read(workspaceProvider('demo-1').notifier);
    for (var i = 0; i < 100 && workspace.content.documents.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(workspace.content.documents.length, 1);
    final doc = workspace.content.documents.single;
    final s = container.read(reflowSessionProvider(('demo-1', doc.id)));
    expect(s.ready, isTrue);
    await shot('02-read');
    final text = s.layout!.chapter.canonicalText, start = s.layout!.chapter.canonicalText.indexOf('Source anchors');
    final anchor = s.layout!.chapter.anchor(start, start + 'Source anchors'.length, revision: doc.revision!);
    expect(text.substring(anchor.start, anchor.end), anchor.quote);
    final box = s.layout!.boxes(anchor).first.rect;
    final surface = find.byKey(const ValueKey('reflow-surface'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getTopLeft(surface) + box.topLeft + const Offset(1, 5));
    await tester.pump();
    await mouse.down(tester.getTopLeft(surface) + box.topLeft + const Offset(1, 5));
    await mouse.moveBy(const Offset(20, 0));
    await tester.pump();
    await mouse.moveTo(tester.getTopLeft(surface) + box.topRight + const Offset(-1, 5));
    await mouse.up();
    await mouse.removePointer();
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider('demo-1')).pending, isA<PendingSelection>());
    await shot('03-selection');
    await tester.tap(find.byTooltip('Add to Map'));
    await tester.pumpAndSettle();
    final annotation = workspace.content.annotations.single, card = workspace.content.cards.single;
    expect(annotation.isText, isTrue);
    final original = annotation.textAnchors.first.toJson();
    await shot('04-excerpt');
    await tester.tap(find.byTooltip('Reading Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reading-larger')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reading-larger')));
    await tester.pumpAndSettle();
    await shot('05-font-size');
    await tester.tapAt(const Offset(10, 300));
    await tester.pumpAndSettle();
    expect(workspace.content.annotations.single.textAnchors.first.toJson(), original);
    expect(s.layout!.boxes(annotation.textAnchors.first), isNotEmpty);
    expect(container.read(settingsProvider).articleReading.size, 5);
    await shot('06-annotation-alignment');
    workspace.revealCard(card.id);
    await tester.pumpAndSettle();
    expect(s.position!.chapterId, annotation.textAnchors.first.chapterId);
    expect(s.position!.offset, annotation.textAnchors.first.start);
    await shot('07-back-to-source');
    await settleHud(tester);
    expect(tester.takeException(), isNull);
  });
}
