import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/widgets/workspace_sidebar.dart';
import 'package:marginmind/features/workspace/widgets/browser_pane.dart';
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';
import 'package:marginmind/features/workspace/workspace_browser.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/workspace/document_import.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:marginmind/settings/settings_window.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import 'helpers.dart';

void main() {
  testWidgets('address dialog validates, opens and closes a workspace browser', (tester) async {
    // Windows method-channel surface avoids native platform-view test stubs.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final container = await pumpApp(tester);
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();
    expect(find.text('Add Web Page…'), findsNothing);
    final sidebar = tester.element(find.byType(WorkspaceSidebar));
    unawaited(showAddWebPage(sidebar, sidebar as WidgetRef, 'demo-1'));
    await tester.pumpAndSettle();
    expect(find.text('Web address'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField).last).decoration!.hintText, 'https://');
    await tester.tap(find.widgetWithText(MMButton, 'Open'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a URL'), findsOneWidget);
    final field = find.byType(TextField).last;
    await tester.enterText(field, 'file:///a');
    await tester.tap(find.widgetWithText(MMButton, 'Open'));
    await tester.pumpAndSettle();
    expect(find.text('Only http and https are supported'), findsOneWidget);
    await tester.enterText(field, 'example.com');
    await tester.pump();
    expect(find.text('Only http and https are supported'), findsNothing);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    final owner = container.read(workspaceBrowserProvider('demo-1').notifier);
    expect(container.read(workspaceBrowserProvider('demo-1')).visible, isTrue);
    final browserReader = find.byType(ReaderPane);
    expect(
      find.descendant(of: browserReader, matching: find.byKey(const ValueKey('map-more'))).hitTestable(),
      findsNothing,
    );
    final imports = container.read(documentImportsProvider('demo-1').notifier);
    final task = imports.add('Pending.epub');
    await tester.pump();
    expect(find.text('Pending.epub'), findsOneWidget);
    final browserRow = find.widgetWithText(MMSidebarItem, 'example.com');
    expect(tester.widget<MMSidebarItem>(browserRow).labelColor, tester.element(browserRow).mmColors.secondaryLabel);
    final document = container.read(workspaceProvider('demo-1').notifier).content.documents.first;
    await tester.tap(find.widgetWithText(MMSidebarItem, document.title));
    await tester.pump();
    expect(container.read(workspaceBrowserProvider('demo-1')).visible, isFalse);
    expect(container.read(workspaceProvider('demo-1')).activeDocumentId, document.id);
    expect(container.read(workspaceBrowserProvider('demo-1')).session!.disposed, isFalse);
    imports.remove(task);
    owner.show();
    await tester.pump();
    final s = container.read(workspaceBrowserProvider('demo-1')).session!;
    var backs = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      MethodChannel('marginmind/browser/${s.id}'),
      (call) async {
        if (call.method == 'back') backs++;
        return null;
      },
    );
    s.canGoBack = true;
    expect(MMBackHandler.dispatch(), isTrue);
    await tester.pump();
    expect(backs, 1);
    s.canGoBack = false;
    expect(MMBackHandler.dispatch(), isTrue);
    await tester.pump();
    expect(s.disposed, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('compact add panel reserves errors and puts Open in its header', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: MMTheme.light(),
          builder: (context, child) => MMInput(touchPlatform: true, child: child!),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) =>
                  MMButton(label: 'Add', onPressed: () => showAddWebPage(context, ref, 'demo-1')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.byType(MMBottomSheet), findsOneWidget);
    expect(find.byIcon(MMIcons.web), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode!.hasFocus, isTrue);
    final sheet = tester.widget<MMSheet>(find.byType(MMSheet));
    expect((sheet.titleTrailing! as MMButton).label, 'Open');
    final before = tester.getSize(find.byType(MMSheet));
    await tester.tap(find.widgetWithText(MMButton, 'Open'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a URL'), findsOneWidget);
    expect(tester.getSize(find.byType(MMSheet)), before);
    await tester.tap(find.widgetWithText(MMButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(MMSheet), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('website data has a destructive clear action and concise confirmation', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    var clears = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('marginmind/browser'),
      (call) async {
        if (call.method == 'clearData') clears++;
        return null;
      },
    );
    await pumpApp(tester);
    unawaited(showSettings(tester.element(find.byType(MMWindowScaffold))));
    await tester.pumpAndSettle();
    expect(find.text('In-App Browser'), findsOneWidget);
    expect(find.text('Website Data'), findsOneWidget);
    final button = tester.widget<MMButton>(find.widgetWithText(MMButton, 'Clear…'));
    expect(button.variant, MMButtonVariant.plain);
    expect(button.color, tester.element(find.byType(SettingsWindow)).mmColors.critical);
    await tester.tap(find.widgetWithText(MMButton, 'Clear…'));
    await tester.pumpAndSettle();
    expect(find.text('Clear all website data?'), findsOneWidget);
    await tester.tap(find.widgetWithText(MMButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(clears, 0);
    await tester.tap(find.widgetWithText(MMButton, 'Clear…'));
    await tester.pumpAndSettle();
    final confirm = tester.widget<MMButton>(find.widgetWithText(MMButton, 'Clear'));
    expect(confirm.color, tester.element(find.byType(SettingsWindow)).mmColors.critical);
    await tester.tap(find.widgetWithText(MMButton, 'Clear'));
    await tester.pumpAndSettle();
    expect(clears, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  for (final size in [const Size(900, 600), const Size(390, 700)]) {
    testWidgets('toolbar loading, ready, validation, history and failure states at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      var elapsed = Duration.zero;
      final s = BrowserSession(Uri.parse('https://example.com/'), elapsed: () => elapsed);
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel('marginmind/browser/${s.id}'),
        (call) async {
          calls.add(call.method);
          if (call.method == 'evaluate') {
            if (((call.arguments as Map)['script'] as String).contains('outerHTML')) {
              return jsonEncode({
                'url': s.url.toString(),
                'title': 'Captured Title',
                'dom': '<html>page</html>',
                'resources': <String>[],
              });
            }
            return jsonEncode({'url': s.url.toString(), 'title': 'Title', 'dom': 0, 'network': 0, 'complete': true});
          }
          return null;
        },
      );
      var converted = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            browserConverterProvider.overrideWithValue((_, _, _) async {
              converted++;
            }),
          ],
          child: MaterialApp(
            theme: MMTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(
              body: BrowserPane(
                studySetId: 'demo-1',
                session: s,
                visible: true,
                documentSwitcher: const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      );
      expect(tester.widget<MMButton>(find.byKey(const ValueKey('browser-convert'))).onPressed, isNull);
      expect(find.byIcon(MMIcons.lock), findsOneWidget);
      expect(find.byKey(const ValueKey('browser-load-progress')), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        size.width < MMSizes.readerMinWidth ? 'example.com' : 'https://example.com/',
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'https://example.com/');
      await s.attach();
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        'marginmind/browser/${s.id}',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('event', {'kind': 'loaded', 'navigationId': 1, 'url': s.url.toString()}),
        ),
        (_) {},
      );
      await tester.pump(const Duration(milliseconds: 200));
      elapsed += const Duration(seconds: 15);
      // A new navigation with a finished main frame but no quiet window yet.
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        'marginmind/browser/${s.id}',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('event', {'kind': 'loaded', 'navigationId': 1, 'url': s.url.toString()}),
        ),
        (_) {},
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Keep Waiting'), findsOneWidget);
      await tester.tap(find.widgetWithText(MMButton, 'Keep Waiting'));
      await tester.pump();
      elapsed += const Duration(seconds: 1);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey('browser-ready-prompt')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('browser-convert')));
      await tester.pump();
      expect(converted, 1);
      final previewContext = tester.element(find.byType(BrowserPane));
      final preview = previewBrowserCapture(previewContext, 'demo-1', s);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Captured Title'), findsOneWidget);
      await tester.tap(find.widgetWithText(MMButton, 'Done'));
      await tester.pump(const Duration(seconds: 1));
      await preview;
      await tester.enterText(find.byType(TextField), 'file:///a');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text('Only http and https are supported'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'example.org');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(calls.where((method) => method == 'navigate').length, 2);
      await s.stop();
      expect(s.canCapture, isFalse);
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        'marginmind/browser/${s.id}',
        const StandardMethodCodec().encodeMethodCall(const MethodCall('event', {'kind': 'failed', 'navigationId': 1})),
        (_) {},
      );
      await tester.pump();
      expect(find.text('Can’t Open Page'), findsOneWidget);
      expect(find.byIcon(MMIcons.warning), findsOneWidget);
      for (final reason in {
        'timeout': 'The connection timed out',
        'host': 'Server not found',
        'certificate': 'Invalid certificate',
        'offline': 'You’re offline',
        'other': null,
      }.entries) {
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
          'marginmind/browser/${s.id}',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('event', {'kind': 'failed', 'navigationId': 1, 'error': reason.key}),
          ),
          (_) {},
        );
        await tester.pump();
        if (reason.value != null) expect(find.text(reason.value!), findsOneWidget);
      }
      unawaited(previewBrowserCapture(previewContext, 'demo-1', s));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.widgetWithText(MMButton, 'Try Again'));
      await tester.pump();
      expect(calls, contains('reload'));
      s.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
