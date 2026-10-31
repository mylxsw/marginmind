import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/main.dart' as app;
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

Future<void> idle(WidgetTester tester, int seconds) async {
  for (var i = 0; i < seconds * 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> capture(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull);
  // The host captures the actual simulator screen during this interval.
  // ignore: avoid_print
  print('SHOT:$name');
  await idle(tester, 3);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('phone library title and short reader navigation', (tester) async {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await app.main();
    await idle(tester, 6);
    final container = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    container.read(navigationProvider.notifier).showLibrary();
    await idle(tester, 2);
    final title = find.descendant(of: find.byType(MMToolbar), matching: find.byType(Text)).first;
    expect(tester.renderObject<RenderParagraph>(title).didExceedMaxLines, isFalse);
    await capture(tester, 'portrait-library');
    final sample = find.text('Open Sample Study Set');
    expect(sample, findsOneWidget);
    await tester.tap(sample);
    await idle(tester, 6);
    final route = container.read(navigationProvider) as WorkspaceRoute;
    final controller = container.read(workspaceProvider(route.studySetId).notifier);
    controller.openDocument(controller.content.documents.first.id);
    await idle(tester, 4);
    await tester.tap(find.text('Source').first);
    await idle(tester, 2);
    await capture(tester, 'portrait-reader');
    await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft]);
    await idle(tester, 4);
    final viewport = tester.getRect(find.byType(MMPdfView));
    final navigation = tester.getRect(find.byKey(const ValueKey('reader-page-navigation')));
    expect(viewport.width, greaterThan(viewport.height));
    expect(navigation.overlaps(viewport), isFalse);
    await capture(tester, 'landscape-reader');
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await idle(tester, 3);
    expect(tester.takeException(), isNull);
  });
}
