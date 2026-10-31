import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/workspace/document_import.dart';
import 'package:marginmind/features/workspace/widgets/phone_workspace_sidebar.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

Future<ProviderContainer> openPhoneSidebar(WidgetTester tester) async {
  final container = await pumpApp(
    tester,
    // Keep the full tag preview visible while retaining the phone compact path.
    size: const Size(393, 1700),
    overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(true)],
  );
  container.read(navigationProvider.notifier).openStudySet('demo-1');
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Show Sidebar').hitTestable().first);
  await tester.pumpAndSettle();
  return container;
}

Finder phoneRow(String label) => find.ancestor(of: find.text(label), matching: find.byType(MMPhoneNavigationRow));
Finder tag(String label) => find.byKey(ValueKey('sidebar-tag-$label'));
const expandKey = ValueKey('sidebar-tags-expand');

List<String> groups(WidgetTester tester) =>
    tester.widgetList<MMPhoneNavigationGroup>(find.byType(MMPhoneNavigationGroup)).map((group) => group.title).toList();

void main() {
  testWidgets('phone drawer preserves imported document flash and scene 8 learning hierarchy', (tester) async {
    final container = await openPhoneSidebar(tester);
    final context = tester.element(find.byType(PhoneWorkspaceSidebar));
    final colors = context.mmColors;
    const documentKey = ValueKey('document-row-c1');
    expect(find.byKey(documentKey), findsOneWidget);
    expect((tester.widget<DecoratedBox>(find.byKey(documentKey)).decoration as BoxDecoration).color, isNull);
    container.read(importedDocumentsProvider('demo-1').notifier).flash('c1');
    await tester.pump();
    expect((tester.widget<DecoratedBox>(find.byKey(documentKey)).decoration as BoxDecoration).color, colors.accentTint);
    expect(find.descendant(of: find.byKey(documentKey), matching: find.byType(MMPhoneNavigationRow)), findsOneWidget);

    final notes = tester.widget<MMPhoneNavigationRow>(phoneRow('Study notes'));
    expect(notes.item.trailing, isA<Icon>().having((icon) => icon.icon, 'chevron', MMIcons.chevronRight));
    expect(find.descendant(of: phoneRow('Study notes'), matching: find.byType(MMBadge)), findsNothing);
    final cards = tester.widget<MMPhoneNavigationRow>(phoneRow('Cards'));
    final review = tester.widget<MMPhoneNavigationRow>(phoneRow('Review'));
    expect(cards.cautionCount, isFalse);
    expect(review.cautionCount, isTrue);
    final cardCount = find.descendant(
      of: phoneRow('Cards'),
      matching: find.text((cards.item.trailing! as MMBadge).value),
    );
    final reviewCount = find.descendant(
      of: phoneRow('Review'),
      matching: find.text((review.item.trailing! as MMBadge).value),
    );
    expect(tester.widget<Text>(cardCount).style!.color, colors.secondaryLabel);
    expect(tester.widget<Text>(reviewCount).style!.color, colors.caution);
    final learningGroup = tester
        .widgetList<MMPhoneNavigationGroup>(find.byType(MMPhoneNavigationGroup))
        .singleWhere((group) => group.title == 'Learn');
    expect(learningGroup.trailing, isNull);
    expect(tester.widget<Text>(find.text('Learn')).style!.color, colors.secondaryLabel);

    await tester.pump(MMMotion.flash);
    expect((tester.widget<DecoratedBox>(find.byKey(documentKey)).decoration as BoxDecoration).color, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone search hides unmatched groups and exposes the no matches state', (tester) async {
    final container = await openPhoneSidebar(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    await controller.setTags('c3', ['Science']);
    controller.setSidebarQuery('no possible sidebar match');
    await tester.pumpAndSettle();
    expect(groups(tester), isEmpty);
    expect(find.text('No matches').hitTestable(), findsOneWidget);

    controller.setSidebarQuery('Review');
    await tester.pumpAndSettle();
    expect(groups(tester), ['Learn']);
    expect(phoneRow('Review'), findsOneWidget);
    expect(phoneRow('Study notes'), findsNothing);
    expect(phoneRow('Cards'), findsNothing);

    controller.setSidebarQuery('Cards');
    await tester.pumpAndSettle();
    expect(groups(tester), ['Learn']);
    expect(phoneRow('Cards'), findsOneWidget);
    expect(phoneRow('Review'), findsNothing);

    controller.setSidebarQuery('论文');
    await tester.pumpAndSettle();
    expect(groups(tester), ['Documents']);
    expect(phoneRow('论文：检索练习效应'), findsOneWidget);
    controller.setSidebarQuery('');
    await tester.pumpAndSettle();
    expect(groups(tester), ['Documents', 'Mind Maps', 'Learn', 'Tags']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone tags preview ten, expand, retain selection, filter and reset for another map', (tester) async {
    final container = await openPhoneSidebar(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    final originalMap = container.read(workspaceProvider('demo-1')).activeMapId;
    final names = [for (var i = 1; i <= 12; i++) 'Tag ${i.toString().padLeft(2, '0')}'];
    await controller.setTags('c3', names.take(10).toList());
    await tester.pumpAndSettle();
    expect(find.byKey(expandKey), findsNothing);
    await controller.setTags('c3', names);
    await tester.pumpAndSettle();
    expect(tag(names[9]), findsOneWidget);
    expect(tag(names[10]), findsNothing);
    expect(find.descendant(of: find.byKey(expandKey), matching: find.text('2')), findsOneWidget);
    final tagsGroup = tester
        .widgetList<MMPhoneNavigationGroup>(find.byType(MMPhoneNavigationGroup))
        .singleWhere((group) => group.title == 'Tags');
    expect(tagsGroup.trailing, isNull);
    await tester.tap(find.byKey(expandKey));
    await tester.pumpAndSettle();
    expect(tag(names[11]), findsOneWidget);
    await tester.tap(tag(names[11]));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show Sidebar').hitTestable().first);
    await tester.pumpAndSettle();
    // Switching to tag content can remount the drawer with its default preview.
    if (tester.widget<MMPhoneNavigationRow>(find.byKey(expandKey)).item.label == 'Expand') {
      await tester.tap(find.byKey(expandKey));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(expandKey));
    await tester.pumpAndSettle();
    expect(names.where((name) => tag(name).evaluate().isNotEmpty), hasLength(10));
    expect(tester.widget<MMPhoneNavigationRow>(tag(names[11])).item.selected, isTrue);

    controller.setSidebarQuery('Tag 11');
    await tester.pumpAndSettle();
    expect(tag(names[10]), findsOneWidget);
    expect(tag(names[11]), findsNothing);
    expect(find.byKey(expandKey), findsNothing);
    controller.setSidebarQuery('no possible sidebar match');
    await tester.pumpAndSettle();
    expect(groups(tester), isEmpty);
    controller.setSidebarQuery('');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(expandKey));
    await tester.pumpAndSettle();
    await controller.addMap('Empty map');
    await tester.pumpAndSettle();
    expect(groups(tester), isNot(contains('Tags')));
    await controller.selectMap(originalMap);
    await tester.pumpAndSettle();
    expect(tester.widget<MMPhoneNavigationRow>(find.byKey(expandKey)).item.label, 'Expand');
    // Reset only the tag preview: changing maps must retain the search field.
    await tester.enterText(find.byType(EditableText).hitTestable(), 'Empty map');
    await tester.pumpAndSettle();
    final emptyMap = controller.content.maps.singleWhere((map) => map.title == 'Empty map');
    await controller.selectMap(emptyMap.id);
    await tester.pumpAndSettle();
    expect(tester.widget<EditableText>(find.byType(EditableText).hitTestable()).controller.text, 'Empty map');
    expect(tester.takeException(), isNull);
  });
}
