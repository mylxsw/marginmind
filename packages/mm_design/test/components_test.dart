import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_design/mm_design.dart';

import 'harness.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('window scaffold renders sidebar, toolbar and body (${brightness.name})', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: brightness == Brightness.light ? MMTheme.light() : MMTheme.dark(),
          home: MMWindowScaffold(
            sidebar: MMSidebar(
              children: [
                MMSidebarSection(
                  title: 'Library',
                  children: [
                    MMSidebarItem(
                      icon: MMIcons.grid,
                      label: 'All',
                      selected: true,
                      trailing: const MMCount(6),
                      onTap: () {},
                    ),
                    MMSidebarItem(icon: MMIcons.review, label: 'Due', trailing: const MMBadge('5'), onTap: () {}),
                  ],
                ),
              ],
            ),
            toolbar: MMToolbar(
              title: 'Title',
              subtitle: 'Subtitle',
              actions: [
                MMToolbarGroup(
                  children: [
                    MMToolbarButton(icon: MMIcons.grid, tooltip: 'Icons', selected: true, onPressed: () {}),
                    const MMToolbarDivider(),
                    MMToolbarButton(icon: MMIcons.list, tooltip: 'List', onPressed: null),
                  ],
                ),
                const MMToolbarSearchField(placeholder: 'Search'),
              ],
            ),
            body: const MMEmptyState(title: 'Empty', message: 'Nothing here', dropZone: true),
          ),
        ),
      );
      expect(find.text('Title'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Empty'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('hiding the sidebar animates it away and shifts the toolbar', (tester) async {
    Widget build(bool visible) => MaterialApp(
      theme: MMTheme.light(),
      home: MMWindowScaffold(
        sidebarVisible: visible,
        sidebar: MMSidebar(
          children: [MMSidebarItem(icon: MMIcons.grid, label: 'Row', onTap: () {})],
        ),
        toolbar: const MMToolbar(title: 'T'),
        body: const SizedBox(),
      ),
    );
    await tester.pumpWidget(build(true));
    final open = tester.getTopLeft(find.text('T')).dx;
    await tester.pumpWidget(build(false));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('T')).dx, lessThan(open));
  });

  testWidgets('segmented control reports taps', (tester) async {
    String value = 'a';
    await tester.pumpWidget(
      harness(
        StatefulBuilder(
          builder: (context, setState) => MMSegmentedControl<String>(
            value: value,
            onChanged: (v) => setState(() => value = v),
            segments: const [
              MMSegment(value: 'a', label: 'Map'),
              MMSegment(value: 'b', label: 'Outline'),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Outline'));
    await tester.pumpAndSettle();
    expect(value, 'b');
  });

  testWidgets('search field clears on Esc and reports changes', (tester) async {
    final changes = <String>[];
    await tester.pumpWidget(
      harness(
        SizedBox(
          width: 240,
          child: MMSearchField(placeholder: 'Search', onChanged: changes.add),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'memory');
    await tester.pump();
    expect(find.byIcon(MMIcons.clear), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('memory'), findsNothing);
    expect(changes, ['memory', '']);
  });

  testWidgets('sheet opens from the top and closes on Esc', (tester) async {
    await tester.pumpWidget(
      harness(
        Builder(
          builder: (context) => MMButton(
            label: 'Open',
            onPressed: () => showMMSheet<void>(
              context: context,
              builder: (_) => const MMSheet(
                title: 'New Study Set',
                child: MMTextField(placeholder: 'Name', autofocus: true),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('New Study Set'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('New Study Set'), findsNothing);
  });

  testWidgets('HUD shows a message and hides it again', (tester) async {
    await tester.pumpWidget(
      harness(
        Builder(
          builder: (context) => MMButton(label: 'Go', onPressed: () => MMHud.show(context, 'Saved')),
        ),
      ),
    );
    await tester.tap(find.text('Go'));
    await tester.pump();
    expect(find.text('Saved'), findsOneWidget);
    final opacity = tester.widget<AnimatedOpacity>(
      find.ancestor(of: find.text('Saved'), matching: find.byType(AnimatedOpacity)),
    );
    expect(opacity.opacity, 1);
    await tester.pump(MMMotion.hud);
    await tester.pumpAndSettle();
    final hidden = tester.widget<AnimatedOpacity>(
      find.ancestor(of: find.text('Saved'), matching: find.byType(AnimatedOpacity)),
    );
    expect(hidden.opacity, 0);
  });

  testWidgets('color picker selects by name and disabled buttons ignore taps', (tester) async {
    var picked = MMAnnotationColor.yellow;
    var tapped = false;
    await tester.pumpWidget(
      harness(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MMColorPicker(selected: picked, onChanged: (c) => picked = c, labelOf: (c) => c.name),
            MMButton(label: 'Disabled', onPressed: null),
            MMButton(label: 'Enabled', onPressed: () => tapped = true),
          ],
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('green'));
    expect(picked, MMAnnotationColor.green);
    await tester.tap(find.text('Disabled'));
    expect(tapped, isFalse);
    await tester.tap(find.text('Enabled'));
    expect(tapped, isTrue);
  });

  testWidgets('color picker draws a card-colored gap inside the selection ring', (tester) async {
    await tester.pumpWidget(
      harness(MMColorPicker(selected: MMAnnotationColor.green, onChanged: (_) {}, labelOf: (c) => c.name)),
    );
    await tester.pumpAndSettle();
    final dot = find.byWidgetPredicate(
      (w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).boxShadow != null,
    );
    final (gap, ring) = await dotRingColors(tester, dot);
    expect(gap, sameColor(MMColors.light.card));
    expect(ring, sameColor(MMAnnotationColor.green.color));
  });

  testWidgets('reduce transparency removes the blur', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: MMTheme.light(),
        home: const MMAppearance(reduceTransparency: true, child: MMGlass(child: Text('glass'))),
      ),
    );
    expect(find.byType(BackdropFilter), findsNothing);
    await tester.pumpWidget(
      MaterialApp(
        theme: MMTheme.light(),
        home: const MMGlass(child: Text('glass')),
      ),
    );
    expect(find.byType(BackdropFilter), findsOneWidget);
  });
}
