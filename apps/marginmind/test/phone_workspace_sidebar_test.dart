import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/phone_workspace_sidebar.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

void main() {
  testWidgets('phone grouped commands, notes expansion and keyboard retain fixed footer', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final focus = FocusNode();
    addTearDown(focus.dispose);
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
                  searchFocus: focus,
                  onSearch: (_) {},
                  onDismiss: () => calls.add('done'),
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
    expect(find.text('Done').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Done').hitTestable());
    expect(calls, contains('done'));
    expect(tester.getRect(find.text('Done')).bottom, lessThan(552));
    expect(tester.takeException(), isNull);
  });
}
