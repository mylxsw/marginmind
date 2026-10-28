import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:marginmind/shared/pdf_drop.dart';
import 'package:mm_design/mm_design.dart';

void main() {
  testWidgets('Finder drop shows a dashed target, routes images and PDFs, then clears hover', (tester) async {
    final images = <String>[];
    final pdfs = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: MMTheme.light(),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: PdfDropTarget(
            label: 'Drop image',
            onDrop: (files) => pdfs.addAll(files.map((f) => f.path)),
            onImageDrop: (files) => images.addAll(files.map((f) => f.path)),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    var drop = tester.widget<DropTarget>(find.byType(DropTarget));
    drop.onDragEntered!(DropEventDetails(localPosition: Offset.zero, globalPosition: Offset.zero));
    await tester.pump();
    expect(find.text('Drop image'), findsOneWidget);
    drop.onDragExited!(DropEventDetails(localPosition: Offset.zero, globalPosition: Offset.zero));
    await tester.pump();
    expect(find.text('Drop image'), findsNothing);
    drop.onDragEntered!(DropEventDetails(localPosition: Offset.zero, globalPosition: Offset.zero));
    await tester.pump();
    drop = tester.widget<DropTarget>(find.byType(DropTarget));
    drop.onDragDone!(
      DropDoneDetails(
        files: [DropItemFile('/tmp/chart.PNG'), DropItemFile('/tmp/book.pdf')],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await tester.pump();
    expect(images, ['/tmp/chart.PNG']);
    expect(pdfs, ['/tmp/book.pdf']);
    expect(find.text('Drop image'), findsNothing);
    drop.onDragDone!(
      DropDoneDetails(files: [DropItemFile('/tmp/chart.jpg')], localPosition: Offset.zero, globalPosition: Offset.zero),
    );
    expect(images, ['/tmp/chart.PNG', '/tmp/chart.jpg']);
  }, variant: TargetPlatformVariant({TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux}));
}
