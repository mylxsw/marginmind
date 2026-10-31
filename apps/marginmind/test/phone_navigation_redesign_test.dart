import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/library/widgets/continue_card.dart';
import 'package:marginmind/features/library/widgets/study_set_card.dart';
import 'package:marginmind/features/review/review_controller.dart';
import 'package:marginmind/features/workspace/widgets/phone_workspace_sidebar.dart';
import 'package:marginmind/settings/settings_window.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';

import '../../../packages/mm_pdf/test/support/pdf_backend.dart';

import 'helpers.dart';

Future<void> evidence(WidgetTester tester, String name) async {
  if (Platform.environment['MM_SCREENSHOTS'] == null) return;
  final view = tester.binding.renderViews.first;
  final image = (await tester.runAsync(
    () => (view.debugLayer! as OffsetLayer).toImage(Offset.zero & view.size, pixelRatio: 1),
  ))!;
  await expectLater(image, matchesGoldenFile('../../../docs/evidence/gul-632/$name.png'));
  image.dispose();
}

void main() {
  setUpAll(() async {
    if (Platform.environment['MM_SCREENSHOTS'] == null) return;
    final data = ByteData.sublistView(File(Platform.environment['MM_FONT']!).readAsBytesSync());
    for (final family in [
      '.AppleSystemUIFont',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      'Roboto',
      'Songti SC',
    ]) {
      await (FontLoader(family)..addFont(Future.value(data))).load();
    }
    final pub = Platform.environment['PUB_CACHE'] ?? '${Platform.environment['HOME']}/.pub-cache';
    final icons = Directory('$pub/hosted/pub.dev')
        .listSync()
        .whereType<Directory>()
        .lastWhere((dir) => dir.path.contains('cupertino_icons-'));
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
          Future.value(ByteData.sublistView(File('${icons.path}/assets/CupertinoIcons.ttf').readAsBytesSync())),
        ))
        .load();
    await (FontLoader(
      'packages/lucide_icons_flutter/Lucide',
    )..addFont(rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'))).load();
  });

  testWidgets('PDF profile follows phone compact only, including rotation', (tester) async {
    installTestPdfBackend(pageCount: 164);
    final container = await pumpApp(
      tester,
      size: const Size(393, 852),
      renderPdf: true,
      overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(true)],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    container.read(workspaceProvider('demo-1').notifier).openDocument('c1');
    await tester.pump();
    final pdf = container.read(readerPdfProvider('demo-1'));
    for (var i = 0; i < 100 && !pdf.isReady; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(pdf.isReady, true);
    expect(tester.widget<MMPdfView>(find.byType(MMPdfView)).scrollProfile, MMPdfScrollProfile.phone);
    tester.view.physicalSize = const Size(852, 393);
    await tester.pumpAndSettle();
    expect(tester.widget<MMPdfView>(find.byType(MMPdfView)).scrollProfile, isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
  });

  for (final dark in [false, true]) {
    testWidgets('393x852 library, drawer, review and actions dark=$dark', (tester) async {
      var content = demoContent();
      var id = 0;
      final editor = StudySetEditor(newId: () => 'evidence-${id++}', now: () => testNow);
      for (final quote in ['间隔重复能加强长期记忆。', '主动回忆比重复阅读更有效。']) {
        content = editor
            .createExcerpt(
              content,
              documentId: 'c1',
              page: 24,
              rects: const [PageRect(10, 100, 200, 88)],
              quote: quote,
              colorIndex: 0,
              parentId: 'c3',
            )
            .$1;
      }
      content = editor.setTags(content, 'c3', ['记忆规律']);
      final container = await pumpApp(
        tester,
        size: const Size(393, 852),
        prefs: {'settings.appearance': dark ? 'dark' : 'light', 'settings.language': 'zh'},
        content: InMemoryStudySetContentRepository({'demo-1': content}),
        overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(true)],
      );
      tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(StudySetCard), matching: find.textContaining('份文档')), findsNothing);
      expect(find.descendant(of: find.byType(ContinueCard), matching: find.textContaining('上次')), findsNothing);
      await evidence(tester, 'library-${dark ? 'dark' : 'light'}');
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      await tester.dragFrom(const Offset(2, 400), const Offset(190, 0));
      await tester.pumpAndSettle();
      expect(find.byType(PhoneWorkspaceSidebar), findsOneWidget);
      expect(tester.getRect(find.byKey(const ValueKey('phone-drawer-panel'))), const Rect.fromLTWH(0, 0, 328, 852));
      expect(find.text('完成').hitTestable(), findsOneWidget);
      expect(find.text('设置').hitTestable(), findsOneWidget);
      await evidence(tester, 'drawer-${dark ? 'dark' : 'light'}');
      await tester.tap(find.text('学习的底层逻辑').hitTestable());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('phone-drawer-scrim')), findsNothing);
      await tester.dragFrom(const Offset(2, 400), const Offset(190, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('完成').hitTestable());
      await tester.pumpAndSettle();
      container.read(navigationProvider.notifier).startReview('demo-1');
      await tester.pumpAndSettle();
      container.read(reviewSessionProvider('demo-1').notifier).reveal();
      await tester.pumpAndSettle();
      expect(find.byType(MMPhoneReviewProgress), findsOneWidget);
      expect(find.textContaining('剩余'), findsNothing);
      expect(find.textContaining('第 24 页'), findsNothing);
      final button = find.byKey(const ValueKey('rate-good'));
      expect(tester.getSize(button).height, 58);
      await evidence(tester, 'review-${dark ? 'dark' : 'light'}');
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(container.read(reviewSessionProvider('demo-1')).index, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('drawer search, settings and return to library', (tester) async {
    final container = await pumpApp(
      tester,
      size: const Size(393, 852),
      overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(true)],
    );
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(2, 400), const Offset(190, 0));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).hitTestable(), '论文');
    await tester.pumpAndSettle();
    expect(find.text('论文：检索练习效应').hitTestable(), findsOneWidget);
    expect(find.text('学习的底层逻辑').hitTestable(), findsNothing);
    await tester.enterText(find.byType(EditableText).hitTestable(), '');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').hitTestable());
    await tester.pumpAndSettle();
    expect(find.byType(SettingsWindow), findsOneWidget);
    expect(find.byKey(const ValueKey('phone-drawer-scrim')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(2, 400), const Offset(190, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Library').hitTestable());
    await tester.pumpAndSettle();
    expect(container.read(navigationProvider), isA<LibraryRoute>());
    expect(tester.takeException(), isNull);
  });

  for (final device in [
    (false, true, const Size(393, 852)),
    (false, false, const Size(1280, 820)),
    (true, true, const Size(852, 393)),
  ]) {
    testWidgets('legacy navigation preserved phone=${device.$1} touch=${device.$2} size=${device.$3}', (tester) async {
      final container = await pumpApp(
        tester,
        size: device.$3,
        overrides: [touchPlatformProvider.overrideWithValue(device.$2), phoneProvider.overrideWithValue(device.$1)],
      );
      expect(find.byType(MMLiquidGlass), findsNothing);
      expect(find.textContaining('docs'), findsWidgets);
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      expect(find.byType(MMPhoneDrawer), findsNothing);
      expect(find.byType(MMSidebar), findsOneWidget);
      container.read(navigationProvider.notifier).startReview('demo-1');
      await tester.pumpAndSettle();
      expect(find.byType(MMPhoneReviewProgress), findsNothing);
      expect(find.textContaining('left'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
