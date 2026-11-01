import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/vocabulary/vocabulary_screen.dart';
import 'package:marginmind/settings/system_appearance.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import 'helpers.dart';
import 'vocabulary_screen_test.dart' show word;

class _Appearance extends SystemAppearanceController {
  @override
  SystemAppearance build() => const SystemAppearance(accentColor: Color(0xFFAF52DE));

  void change(Color color) => state = SystemAppearance(accentColor: color);
}

void main() {
  for (final dark in [false, true]) {
    testWidgets('vocabulary and AI follow live system accents; dark=$dark', (tester) async {
      final repo = InMemoryVocabularyRepository([word('cat')]);
      addTearDown(repo.dispose);
      final owner = await pumpApp(
        tester,
        vocabulary: repo,
        prefs: {'settings.appearance': dark ? 'dark' : 'light'},
        overrides: [systemAppearanceProvider.overrideWith(_Appearance.new)],
      );
      owner.read(navigationProvider.notifier).showVocabulary();
      await tester.pumpAndSettle();
      for (final (color, foreground) in [
        (const Color(0xFF007AFF), Colors.white),
        (const Color(0xFF0A84FF), Colors.white),
        (const Color(0xFF3B78F9), Colors.white),
        (const Color(0xFFAF52DE), Colors.white),
        (const Color(0xFFFF9500), Colors.black),
        (const Color(0xFFFFCC00), Colors.black),
      ]) {
        (owner.read(systemAppearanceProvider.notifier) as _Appearance).change(color);
        await tester.pumpAndSettle();
        final c = tester.element(find.byType(VocabularyScreen)).mmColors;
        expect(c.accent, color);
        expect(c.vocabulary, color);
        expect(c.research, color);
        final button = find.byKey(const ValueKey('vocabulary-toggle-status'));
        final surface = tester.widget<Container>(find.descendant(of: button, matching: find.byType(Container)).first);
        expect((surface.decoration! as BoxDecoration).color, color);
        final label = tester.widget<Text>(find.descendant(of: button, matching: find.text('Mark as known')));
        expect(label.style!.color, foreground);
        expect(contrastRatio(label.style!.color!, color), greaterThanOrEqualTo(3));
        final check = tester.widget<Icon>(find.descendant(of: button, matching: find.byIcon(MMIcons.check)));
        expect(check.color, foreground);
        expect(c.onResearch, foreground);
        expect(Theme.of(tester.element(button)).colorScheme.onPrimary, foreground);
        final row = find.byKey(const ValueKey('vocabulary-row-cat'));
        final selection = tester.widget<Container>(find.descendant(of: row, matching: find.byType(Container)).first);
        expect((selection.decoration! as BoxDecoration).color, c.selectedRow);
        expect(tester.takeException(), isNull);
      }
    });
  }
}
