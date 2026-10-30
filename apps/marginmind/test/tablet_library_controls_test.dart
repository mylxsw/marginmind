import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/library/widgets/study_set_card.dart';
import 'package:marginmind/features/library/widgets/study_set_list.dart';
import 'package:mm_core/mm_core.dart';
import 'package:marginmind/shared/l10n.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';

void main() {
  for (final touch in [false, true]) {
    for (final list in [false, true]) {
      testWidgets('${touch ? 'tablet' : 'Mac'} ${list ? 'list' : 'grid'} opens with the platform gesture', (t) async {
        final now = DateTime(2026, 10, 30);
        final set = DemoLibrary.studySets(now).first;
        var opened = 0;
        await t.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            theme: MMTheme.light(),
            home: MMInput(
              touchPlatform: touch,
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 700,
                    child: list
                        ? StudySetList(
                            sets: [set],
                            folders: const [],
                            sort: LibrarySort.recent,
                            selectedId: null,
                            now: now,
                            onSort: (_) {},
                            onSelect: (_) {},
                            onOpen: (_) => opened++,
                          )
                        : SizedBox(
                            width: 200,
                            child: StudySetCard(
                              set: set,
                              selected: false,
                              now: now,
                              onSelect: () {},
                              onOpen: () => opened++,
                              onToggleStar: () {},
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        final item = find.text(set.title).first;
        await t.tap(item);
        await t.pump(const Duration(milliseconds: 50));
        expect(opened, touch ? 1 : 0);
        if (!touch) {
          await t.tap(item);
          await t.pumpAndSettle();
          expect(opened, 1);
        }
        expect(t.takeException(), isNull);
      });
    }
  }
}
