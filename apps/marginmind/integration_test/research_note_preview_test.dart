import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_platform/mm_platform.dart';

import '../test/helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().defaultTestTimeout = const Timeout(Duration(minutes: 5));
  testWidgets('native PDF note preview responds immediately and remains interactive', (tester) async {
    debugPrint('Note preview: initialize native window');
    await tester.runAsync(() => DesktopWindow.initialize(title: 'Foliarc', minimumSize: MMSizes.windowMinSize));
    debugPrint('Note preview: prepare PDF fixture');
    final directory = await Directory.systemTemp.createTemp('foliarc-note-preview-');
    addTearDown(() => directory.delete(recursive: true));
    final bytes = await rootBundle.load('assets/sample/sample.pdf');
    final file = await File('${directory.path}/source.pdf').writeAsBytes(bytes.buffer.asUint8List());
    await tester.runAsync(MMPdfEngine.initialize);
    debugPrint('Note preview: mount workspace');
    final fixture = demoContent();
    final content = fixture.copyWith(
      documents: [fixture.documents.first.copyWith(fileName: file.path, lastPage: 1, cropSuggestionDismissed: true)],
    );
    final container = await pumpApp(
      tester,
      renderPdf: true,
      size: const Size(1600, 1000),
      prefs: {'settings.language': 'zh', 'settings.appearance': 'dark'},
      content: InMemoryStudySetContentRepository({'demo-1': content}),
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    final pdf = container.read(documentPdfProvider(('demo-1', 'c1')));
    for (var i = 0; i < 100 && !pdf.isReady; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    expect(pdf.isReady, isTrue);
    final workspace = container.read(workspaceProvider('demo-1').notifier);
    await workspace.saveResearchNote(
      ResearchNote(
        id: 'native-note',
        title: '间隔重复与主动回想',
        question: '怎样记得更牢？',
        body: '把练习分散到不同的日子，每次合上书主动回想。\n这条笔记已保存，悬停即可查看。',
        createdAt: testNow,
        updatedAt: testNow,
      ),
      source: PdfTarget(
        documentId: 'c1',
        pages: const [
          AnnotationPage(page: 1, rects: [PageRect(70, 620, 270, 600)]),
        ],
        quote: 'Spaced repetition',
      ),
      toMap: true,
    );
    await tester.pumpAndSettle();
    await tester.pump(MMMotion.flash);
    final marker = find.byKey(
      ValueKey(
        'pdf-marker-${noteMarkId(workspace.content.noteAttachments.singleWhere((a) => a.noteId == 'native-note' && a.target is PdfTarget).id)}',
      ),
    );
    final popover = find.byKey(const ValueKey('research-note-popover'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1, 1));
    await mouse.moveTo(tester.getCenter(marker));
    await tester.pump();
    expect(popover, findsOneWidget);
    expect(container.read(workspaceProvider('demo-1')).pending, isNull);
    await mouse.moveTo(tester.getCenter(popover));
    await tester.pump();
    await tester.pump(MMMotion.hoverExit + MMMotion.quick);
    expect(popover, findsOneWidget);
    const evidence = String.fromEnvironment('MM_NOTE_PREVIEW_EVIDENCE');
    if (evidence.isNotEmpty) {
      final image = await (tester.binding.renderViews.first.debugLayer! as OffsetLayer).toImage(
        Offset.zero & tester.view.physicalSize,
        pixelRatio: 1,
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = File('${Directory.systemTemp.path}/foliarc-note-hover.png');
      await output.writeAsBytes(data!.buffer.asUint8List());
      debugPrint('Note preview screenshot: ${output.path}');
      image.dispose();
    }
    await mouse.moveTo(const Offset(1, 1));
    await tester.pump();
    await tester.pump(MMMotion.hoverExit);
    expect(popover, findsNothing);
    // Clicking the same icon must pin the note without advancing the clock.
    await mouse.down(tester.getCenter(marker));
    await mouse.up();
    expect(container.read(workspaceProvider('demo-1')).pending, isA<PendingResearchNote>());
    await tester.pump();
    expect(popover, findsOneWidget);
    await tester.pump(MMMotion.hoverExit * 2);
    expect(popover, findsOneWidget);
    await mouse.removePointer();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(popover, findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }, semanticsEnabled: false);
}
