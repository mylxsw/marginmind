import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/features/workspace/widgets/phone_reader_appearance_sheet.dart';
import 'package:marginmind/settings/app_settings.dart';
import 'package:marginmind/shared/l10n.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

void main() {
  testWidgets('PhoneReaderAppearanceSheet renders 4 styles and updates live', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var backCalled = false;
    var closeCalled = false;

    final overrides = await testOverrides(
      prefs: {'settings.appearance': 'light', 'settings.readerStyle': 'white', 'settings.language': 'zh'},
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [...overrides, touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(true)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: PhoneReaderAppearanceSheet(
              studySetId: 'demo-1',
              onBack: () => backCalled = true,
              onClose: () => closeCalled = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final element = tester.element(find.byType(PhoneReaderAppearanceSheet));
    final container = ProviderScope.containerOf(element);

    // Verify Title
    expect(find.text('阅读外观'), findsOneWidget);

    // Verify 4 style cards exist
    final whiteCard = find.byKey(const ValueKey('phone-reader-style-white'));
    final paperCard = find.byKey(const ValueKey('phone-reader-style-paper'));
    final greenCard = find.byKey(const ValueKey('phone-reader-style-green'));
    final darkCard = find.byKey(const ValueKey('phone-reader-style-dark'));

    expect(whiteCard, findsOneWidget);
    expect(paperCard, findsOneWidget);
    expect(greenCard, findsOneWidget);
    expect(darkCard, findsOneWidget);

    // Initial state: white is selected
    expect(container.read(settingsProvider).readerStyle, MMReaderStyle.white);
    expect(find.descendant(of: whiteCard, matching: find.byIcon(MMIcons.check)), findsOneWidget);
    expect(find.descendant(of: paperCard, matching: find.byIcon(MMIcons.check)), findsNothing);

    // Tap paper card: updates immediately to paper
    await tester.tap(paperCard);
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).readerStyle, MMReaderStyle.paper);
    expect(find.descendant(of: paperCard, matching: find.byIcon(MMIcons.check)), findsOneWidget);
    expect(find.descendant(of: whiteCard, matching: find.byIcon(MMIcons.check)), findsNothing);

    // Tap green card: updates immediately to green
    await tester.tap(greenCard);
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).readerStyle, MMReaderStyle.green);
    expect(find.descendant(of: greenCard, matching: find.byIcon(MMIcons.check)), findsOneWidget);

    // Tap dark card: updates immediately to dark
    await tester.tap(darkCard);
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).readerStyle, MMReaderStyle.dark);
    expect(find.descendant(of: darkCard, matching: find.byIcon(MMIcons.check)), findsOneWidget);

    // Tap back button
    await tester.tap(find.byKey(const ValueKey('phone-appearance-back')));
    await tester.pumpAndSettle();
    expect(backCalled, isTrue);

    // Tap close button
    await tester.tap(find.byKey(const ValueKey('phone-appearance-close')));
    await tester.pumpAndSettle();
    expect(closeCalled, isTrue);
  });
}
