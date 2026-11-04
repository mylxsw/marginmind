import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/phone_workspace_sidebar.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

void main() {
  for (final language in ['en', 'zh']) {
    testWidgets('320 point drawer destinations remain readable with large $language text', (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: await testOverrides(),
          child: MaterialApp(
            locale: Locale(language),
            theme: MMTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MMInput(
              phone: true,
              touchPlatform: true,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!,
              ),
            ),
            home: Material(
              child: PhoneWorkspaceSidebar(
                title: 'Study set',
                mapId: 'map',
                documents: const [],
                maps: const [],
                notes: const [],
                learning: const [],
                tags: const [],
                results: const [],
                searching: false,
                showNotes: false,
                onAddDocument: () {},
                onAddMap: () {},
                onAddNote: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final library = find.text(language == 'zh' ? '资料库' : 'Library');
      expect(tester.renderObject<RenderParagraph>(library).didExceedMaxLines, isFalse);
      final action = find.byType(MMPhoneNavigationAction);
      expect(tester.getSize(action).height, greaterThanOrEqualTo(44));
      expect(tester.getRect(action).right, lessThanOrEqualTo(320));
      await tester.tap(action);
      expect(find.byIcon(MMIcons.close), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('phone grouped commands, notes expansion and keyboard keep the library destination visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final calls = <String>[];
    final overrides = await testOverrides();
    MMPhoneNavigationRow row(String label) => MMPhoneNavigationRow(
      item: MMSidebarItem(icon: MMIcons.studyNote, label: label, onTap: () => calls.add(label)),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: MMTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MMInput(
            touchPlatform: true,
            phone: true,
            child: Material(
              child: SizedBox(
                width: 328,
                child: PhoneWorkspaceSidebar(
                  title: 'Study set',
                  mapId: 'map',
                  documents: [row('Document')],
                  maps: [row('Map')],
                  notes: [row('Note')],
                  showNotes: true,
                  learning: [row('Review')],
                  tags: [row('Tag')],
                  results: const [],
                  searching: false,
                  onAddDocument: () => calls.add('import'),
                  onAddWebPage: () => calls.add('web'),
                  onAddMap: () => calls.add('map'),
                  onGenerateMap: () => calls.add('generate'),
                  onAddNote: () => calls.add('new-note'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Back to Content'), findsNothing);
    expect(find.byIcon(MMIcons.close), findsNothing);
    final list = find.byKey(const ValueKey('phone-drawer-list'));
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Web Page…').hitTestable());
    await tester.pumpAndSettle();
    expect(calls, contains('web'));
    await tester.tap(find.byTooltip('New Mind Map…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Mind Map…').hitTestable().last);
    await tester.pumpAndSettle();
    expect(calls, contains('map'));
    await tester.scrollUntilVisible(
      find.text('Study notes'),
      150,
      scrollable: find.descendant(of: list, matching: find.byType(Scrollable)).first,
    );
    await tester.tap(find.text('Study notes'));
    await tester.pumpAndSettle();
    expect(find.text('Note').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Note').hitTestable());
    expect(calls, contains('Note'));
    await tester.tap(find.text('Organize Study Notes…').hitTestable());
    await tester.pumpAndSettle();
    expect(calls, contains('new-note'));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(find.byType(MMPhoneNavigationAction), findsOneWidget);
    expect(tester.getRect(find.byType(MMPhoneNavigationAction)).bottom, lessThan(552));
    expect(tester.takeException(), isNull);
    // Android landscape IME can leave only 126 logical points for the drawer,
    // including when it is mounted behind the assistant.
    await tester.enterText(find.byType(TextField), 'Keep search');
    tester.view.physicalSize = const Size(914, 411);
    tester.view.viewInsets = const FakeViewPadding(bottom: 285);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.byType(MMPhoneNavigationAction)).bottom, lessThanOrEqualTo(126));
    expect(find.text('Keep search'), findsOneWidget);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Tag'),
      100,
      scrollable: find.descendant(of: list, matching: find.byType(Scrollable)).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Tag'));
    await tester.pumpAndSettle();
    expect(find.text('Tag').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
