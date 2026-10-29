import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/widgets/browser_pane.dart';
import 'package:marginmind/features/workspace/workspace_browser.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
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
    await tester.tap(find.text('Add Web Page…').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MMButton, 'Open'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a URL'), findsOneWidget);
    final field = find.byType(TextField).last;
    await tester.enterText(field, 'file:///a');
    await tester.tap(find.widgetWithText(MMButton, 'Open'));
    await tester.pumpAndSettle();
    expect(find.text('Only http and https are supported'), findsOneWidget);
    await tester.enterText(field, 'example.com');
    await tester.tap(find.widgetWithText(MMButton, 'Open'));
    await tester.pump();
    final owner = container.read(workspaceBrowserProvider('demo-1').notifier);
    expect(container.read(workspaceBrowserProvider('demo-1')).visible, isTrue);
    owner.hide();
    await tester.pump();
    expect(container.read(workspaceBrowserProvider('demo-1')).visible, isFalse);
    owner.show();
    await tester.pump();
    final s = container.read(workspaceBrowserProvider('demo-1')).session!;
    owner.close();
    await tester.pump();
    expect(s.disposed, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('toolbar loading, ready, validation, history and failure states', (tester) async {
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
    await s.attach();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      'marginmind/browser/${s.id}',
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('event', {'kind': 'loaded', 'navigationId': 1, 'url': s.url.toString()}),
      ),
      (_) {},
    );
    await tester.pump(const Duration(milliseconds: 200));
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
    expect(find.text('Unable to Open Page'), findsOneWidget);
    unawaited(previewBrowserCapture(previewContext, 'demo-1', s));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.widgetWithText(MMButton, 'Retry'));
    await tester.pump();
    expect(calls, contains('reload'));
    s.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}
