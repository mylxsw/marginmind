import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/features/review/review_controller.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

const _quote = '这条先陡后平的曲线，被称为遗忘曲线。';

Future<ProviderContainer> _openSet(WidgetTester tester) async {
  final container = await pumpApp(tester);
  await tester.tap(find.text('Starred'));
  await tester.pumpAndSettle();
  await doubleTap(tester, find.text('认知科学入门'));
  return container;
}

Iterable<PlatformMenuItem> _flatten(Iterable<PlatformMenuItem> items) sync* {
  for (final item in items) {
    yield item;
    if (item is PlatformMenu) yield* _flatten(item.menus);
    if (item is PlatformMenuItemGroup) yield* _flatten(item.members);
  }
}

void main() {
  Finder faded(Finder of) =>
      find.ancestor(of: of, matching: find.byWidgetPredicate((w) => w is Opacity && w.opacity < 1 && w.opacity > .35));
  Finder sidebarDue(String count) =>
      find.descendant(of: find.byType(MMSidebar), matching: find.widgetWithText(MMBadge, count));

  Future<void> openNodeMenu(WidgetTester tester, String text) async {
    await showWholeMap(tester);
    await tester.tap(find.text(text), buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
  }

  testWidgets('the node menu suspends and resumes a card, faded on the map and out of the count', (tester) async {
    final container = await _openSet(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    final excerpt = controller.content.cardForAnnotation(controller.content.annotations.single.id)!;
    expect(sidebarDue('1'), findsOneWidget);
    expect(faded(find.text(_quote)), findsNothing);

    // Topics are never reviewed, so they have nothing to suspend.
    await openNodeMenu(tester, '对策一：间隔重复');
    expect(find.text('Suspend Card'), findsNothing);
    expect(find.text('Review Branch'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await openNodeMenu(tester, _quote);
    // A leaf is a single card, not a branch.
    expect(find.text('Review Branch'), findsNothing);
    await tester.tap(find.text('Suspend Card'));
    await tester.pumpAndSettle();
    expect(controller.content.card(excerpt.id)!.suspended, isTrue);
    expect(faded(find.text(_quote)), findsOneWidget);
    expect(sidebarDue('1'), findsNothing);
    expect(find.descendant(of: find.byType(MMSidebar), matching: find.byType(MMBadge)), findsNothing);
    expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.value == 'Suspended'), findsOneWidget);

    // The branch above it has nothing left to review.
    await openNodeMenu(tester, '遗忘的规律');
    expect(find.text('Review Branch'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await openNodeMenu(tester, _quote);
    expect(find.text('Suspend Card'), findsNothing);
    await tester.tap(find.text('Resume Card'));
    await tester.pumpAndSettle();
    expect(controller.content.card(excerpt.id)!.suspended, isFalse);
    expect(faded(find.text(_quote)), findsNothing);
    expect(sidebarDue('1'), findsOneWidget);

    // Each change is one undo step.
    await controller.undo();
    await tester.pumpAndSettle();
    expect(controller.content.card(excerpt.id)!.suspended, isTrue);
    await controller.undo();
    await tester.pumpAndSettle();
    expect(controller.content.card(excerpt.id)!.suspended, isFalse);
    await settleHud(tester);
  });

  testWidgets('the outline shows a suspended card in the secondary color', (tester) async {
    final container = await _openSet(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    final excerpt = controller.content.cardForAnnotation(controller.content.annotations.single.id)!;
    await controller.setSuspended(excerpt.id, suspended: true);
    controller.setMapView(MapViewMode.outline);
    await tester.pumpAndSettle();
    final colors = tester.element(find.byType(MMSidebar)).mmColors;
    Color colorOf(String text) => tester.widget<Text>(find.text(text).last).style!.color!;
    expect(colorOf(_quote), colors.secondaryLabel);
    expect(colorOf('遗忘的规律'), colors.label);
    await settleHud(tester);
  });

  testWidgets('the node menu reviews just that branch', (tester) async {
    final container = await _openSet(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    final excerpt = controller.content.cardForAnnotation(controller.content.annotations.single.id)!;
    final other = await controller.addNote('Elsewhere');
    await tester.pumpAndSettle();
    expect(sidebarDue('2'), findsOneWidget);

    await openNodeMenu(tester, '遗忘的规律');
    expect(find.text('Suspend Card'), findsNothing);
    await tester.tap(find.text('Review Branch'));
    await tester.pumpAndSettle();
    final route = container.read(navigationProvider) as ReviewRoute;
    expect(route.branchId, 'c3');
    expect(route.mapId, MindMap.defaultId);
    expect(container.read(reviewSessionProvider('demo-1')).queue, [excerpt.id]);
    expect(container.read(reviewSessionProvider('demo-1')).queue, isNot(contains(other.id)));
    // The session is named by the branch it covers.
    expect(find.text('遗忘的规律 · 1 left'), findsOneWidget);
    await settleHud(tester);
  });

  testWidgets('a sidebar tag reviews the cards carrying it', (tester) async {
    final container = await _openSet(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    final excerpt = controller.content.cardForAnnotation(controller.content.annotations.single.id)!;
    final note = await controller.addNote('Spacing');
    await controller.setTags(excerpt.id, ['Memory']);
    await controller.setTags(note.id, ['memory']);
    await controller.setTags('c4', ['Plan']);
    await tester.pumpAndSettle();

    // Nothing to review under a tag carried only by a topic: no menu.
    await tester.tap(
      find.byKey(const ValueKey('sidebar-tag-Plan')),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(find.text('Review Tag'), findsNothing);

    await controller.setSuspended(note.id, suspended: true);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('sidebar-tag-Memory')),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review Tag'));
    await tester.pumpAndSettle();
    final route = container.read(navigationProvider) as ReviewRoute;
    expect(route.tag, 'Memory');
    expect(container.read(reviewSessionProvider('demo-1')).queue, [excerpt.id]);
    expect(find.text('Memory · 1 left'), findsOneWidget);
    await settleHud(tester);
  });

  testWidgets('menu bar: review branch, review tag and suspend follow the selection', (tester) async {
    final container = await _openSet(tester);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    final excerpt = controller.content.cardForAnnotation(controller.content.annotations.single.id)!;
    PlatformMenuItem command(String label) =>
        _flatten(tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar)).menus)
            .singleWhere((item) => item.label == label);

    expect(command('Review Branch').onSelected, isNull);
    expect(command('Review Tag').onSelected, isNull);
    expect(command('Suspend Card').onSelected, isNull);

    controller.selectCard('c4');
    await tester.pumpAndSettle();
    expect(command('Review Branch').onSelected, isNull);
    expect(command('Suspend Card').onSelected, isNull);

    controller.selectCard(excerpt.id);
    await tester.pumpAndSettle();
    expect(command('Review Branch').onSelected, isNull);
    command('Suspend Card').onSelected!();
    await tester.pumpAndSettle();
    expect(controller.content.card(excerpt.id)!.suspended, isTrue);
    expect(command('Review Branch').onSelected, isNull);
    command('Resume Card').onSelected!();
    await tester.pumpAndSettle();
    expect(controller.content.card(excerpt.id)!.suspended, isFalse);

    await controller.setTags(excerpt.id, ['Memory']);
    controller.filterTag('Memory');
    await tester.pumpAndSettle();
    command('Review Tag').onSelected!();
    await tester.pumpAndSettle();
    expect((container.read(navigationProvider) as ReviewRoute).tag, 'Memory');
    container.read(navigationProvider.notifier).openStudySet('demo-1');
    await tester.pumpAndSettle();

    controller.selectCard('c3');
    await tester.pumpAndSettle();
    command('Review Branch').onSelected!();
    await tester.pumpAndSettle();
    expect((container.read(navigationProvider) as ReviewRoute).branchId, 'c3');
    await settleHud(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
