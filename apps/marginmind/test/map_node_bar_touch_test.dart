import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/widgets/map_selection_bar.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:mm_design/mm_design.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('tablet icons expose every action and long press only explains (dark: $dark)', (tester) async {
      final invoked = <String>[];
      await _pumpBar(tester, dark: dark, invoked: invoked);
      final l = AppLocalizations.of(tester.element(find.byType(MapNodeBar)));
      final labels = {
        'child': l.addChildTopic,
        'sibling': l.addSiblingAfter,
        'edit': l.renameTitle,
        'relation': l.addRelation,
        'note': l.addNote,
        'image': l.insertImage,
        'delete': l.removeFromMap,
        'assistant': l.askAssistant,
      };
      expect(find.byKey(const ValueKey('node-bar-more')), findsNothing);
      expect(find.byType(Text), findsNothing);
      expect(tester.getSize(find.byType(MapNodeBar)).width, lessThanOrEqualTo(360));
      Rect? previous;
      for (final entry in labels.entries) {
        final button = find.byKey(ValueKey('node-bar-${entry.key}'));
        final bounds = tester.getRect(button);
        expect(bounds.width, greaterThanOrEqualTo(44));
        expect(bounds.height, greaterThanOrEqualTo(44));
        if (previous != null) expect(bounds.left, greaterThanOrEqualTo(previous.right));
        previous = bounds;
        expect(find.bySemanticsLabel(entry.value), findsOneWidget);

        await tester.longPress(button);
        await tester.pumpAndSettle();
        expect(find.text(entry.value), findsOneWidget);
        expect(invoked, isEmpty, reason: 'reading a tip must not run ${entry.key}, even on release');
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
      }
      for (final action in labels.keys) {
        await tester.tap(find.byKey(ValueKey('node-bar-$action')));
        await tester.pumpAndSettle();
      }
      expect(invoked, labels.keys.toList());
    });
  }

  testWidgets('tablet root shows only applicable icons', (tester) async {
    await _pumpBar(tester, invoked: [], root: true);
    for (final action in ['child', 'image', 'assistant']) {
      expect(find.byKey(ValueKey('node-bar-$action')), findsOneWidget);
    }
    for (final action in ['sibling', 'edit', 'relation', 'note', 'delete', 'more']) {
      expect(find.byKey(ValueKey('node-bar-$action')), findsNothing);
    }
  });
}

Future<void> _pumpBar(
  WidgetTester tester, {
  required List<String> invoked,
  bool dark = false,
  bool root = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? MMTheme.dark() : MMTheme.light(),
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MMInput(
        touchPlatform: true,
        child: Scaffold(
          body: Center(
            child: MapNodeBar(
              root: root,
              onChild: () => invoked.add('child'),
              onSibling: () => invoked.add('sibling'),
              onEdit: root ? null : () => invoked.add('edit'),
              onRelation: () => invoked.add('relation'),
              onNote: () => invoked.add('note'),
              onImage: () => invoked.add('image'),
              onDelete: () => invoked.add('delete'),
              onAssistant: (_) => invoked.add('assistant'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
