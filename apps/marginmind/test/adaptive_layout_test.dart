import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/phone_tabs.dart';
import 'package:marginmind/features/library/library_screen.dart';
import 'package:marginmind/features/review/review_screen.dart';
import 'package:marginmind/features/review/stats_screen.dart';
import 'package:marginmind/features/workspace/widgets/map_pane.dart';
import 'package:marginmind/features/workspace/widgets/reader_pane.dart';
import 'package:marginmind/features/workspace/widgets/workspace_sidebar.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/workspace/workspace_layout.dart';
import 'package:marginmind/features/library/library_controller.dart';
import 'package:marginmind/settings/app_settings.dart';
import 'package:mm_design/mm_design.dart';

import 'helpers.dart';

/// A device window: logical size and safe area insets.
typedef Device = ({String name, Size size, EdgeInsets safe, bool touch});

const iphone = (name: 'iPhone 402×874', size: Size(402, 874), safe: EdgeInsets.fromLTRB(0, 62, 0, 34), touch: true);
const iphoneLandscape = (
  name: 'iPhone landscape 874×402',
  size: Size(874, 402),
  safe: EdgeInsets.fromLTRB(62, 0, 62, 21),
  touch: true,
);
const ipadTwoThirds = (
  name: 'iPad ⅔ 684×1032',
  size: Size(684, 1032),
  safe: EdgeInsets.fromLTRB(0, 24, 0, 20),
  touch: true,
);
const ipadMini = (
  name: 'iPad mini 744×1133',
  size: Size(744, 1133),
  safe: EdgeInsets.fromLTRB(0, 24, 0, 20),
  touch: true,
);
const ipadPortrait = (
  name: 'iPad Pro 13" portrait 1032×1376',
  size: Size(1032, 1376),
  safe: EdgeInsets.fromLTRB(0, 32, 0, 20),
  touch: true,
);
const ipadLandscape = (
  name: 'iPad Pro 13" landscape 1376×1032',
  size: Size(1376, 1032),
  safe: EdgeInsets.fromLTRB(0, 32, 0, 20),
  touch: true,
);
const desktop = (name: 'desktop 1280×800', size: Size(1280, 800), safe: EdgeInsets.zero, touch: false);
const desktopMin = (name: 'desktop 960×600', size: Size(960, 600), safe: EdgeInsets.zero, touch: false);

const devices = <Device>[
  (name: 'small iPhone 320×568', size: Size(320, 568), safe: EdgeInsets.fromLTRB(0, 20, 0, 0), touch: true),
  iphone,
  iphoneLandscape,
  ipadTwoThirds,
  ipadMini,
  ipadPortrait,
  ipadLandscape,
  desktop,
  desktopMin,
];

Future<ProviderContainer> pumpDevice(WidgetTester tester, Device device) async {
  final container = await pumpApp(
    tester,
    size: device.size,
    overrides: [
      touchPlatformProvider.overrideWithValue(device.touch),
      phoneProvider.overrideWithValue(device.touch && device.size.shortestSide < 600),
    ],
  );
  tester.view.padding = FakeViewPadding(
    left: device.safe.left,
    top: device.safe.top,
    right: device.safe.right,
    bottom: device.safe.bottom,
  );
  await tester.pumpAndSettle();
  return container;
}

Future<ProviderContainer> openWorkspace(WidgetTester tester, Device device) async {
  final container = await pumpDevice(tester, device);
  container.read(navigationProvider.notifier).openStudySet('demo-1');
  await tester.pumpAndSettle();
  container.read(workspaceProvider('demo-1').notifier).openDocument('c1');
  await tester.pumpAndSettle();
  return container;
}

Rect rectOf(WidgetTester tester, Type type) => tester.getRect(find.byType(type));

void main() {
  for (final device in devices) {
    testWidgets('${device.name}: every screen lays out without overflow', (tester) async {
      final container = await openWorkspace(tester, device);
      expect(tester.takeException(), isNull);
      expect(find.byType(ReaderPane), findsOneWidget);
      final controller = container.read(workspaceProvider('demo-1').notifier);
      for (final layout in MMSplitMode.values) {
        controller.setLayout(layout);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$layout');
      }
      controller.setLayout(MMSplitMode.split);
      controller.toggleReaderPanel();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'reader sidebar');
      controller.toggleReaderPanel();
      controller.showDetails('c3');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'details');
      controller.openPanel(RightPanel.assistant);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'assistant');
      controller.closePanel();
      await tester.pumpAndSettle();

      final nav = container.read(navigationProvider.notifier);
      nav.showLibrary();
      await tester.pumpAndSettle();
      expect(find.byType(LibraryScreen), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'library');
      container.read(libraryViewProvider.notifier).setViewMode(LibraryViewMode.list);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'library list');
      nav.startReview('demo-1');
      await tester.pumpAndSettle();
      expect(find.byType(ReviewScreen), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'review');
      nav.showStats('demo-1');
      await tester.pumpAndSettle();
      expect(find.byType(StatsScreen), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'stats');
      await settleHud(tester);
    });
  }

  group('layout rules', () {
    test('size classes follow the logical size, not the device', () {
      expect(MMSizeClass.fromSize(const Size(402, 874)), MMSizeClass.compact);
      expect(MMSizeClass.fromSize(const Size(599, 400)), MMSizeClass.compact);
      expect(MMSizeClass.fromSize(const Size(600, 400)), MMSizeClass.medium);
      expect(MMSizeClass.fromSize(const Size(1032, 1376)), MMSizeClass.medium);
      expect(MMSizeClass.fromSize(const Size(1179, 800)), MMSizeClass.medium);
      expect(MMSizeClass.fromSize(const Size(1180, 1181)), MMSizeClass.medium);
      expect(MMSizeClass.fromSize(const Size(1180, 800)), MMSizeClass.regular);
      expect(MMSizeClass.fromSize(const Size(1376, 1032)), MMSizeClass.regular);
    });

    test('regular keeps the desktop rules whatever the size class argument', () {
      for (final width in [960.0, 1000.0, 1280.0, 1400.0]) {
        for (final layout in MMSplitMode.values) {
          for (final panel in [false, true]) {
            expect(
              resolveWorkspaceLayout(
                windowWidth: width,
                sidebarVisible: true,
                layout: layout,
                panelOpen: panel,
                sizeClass: MMSizeClass.regular,
                windowHeight: 300,
              ),
              resolveWorkspaceLayout(windowWidth: width, sidebarVisible: true, layout: layout, panelOpen: panel),
            );
          }
        }
      }
    });

    test('medium stacks both panes while they fit and floats the panel', () {
      expect(
        resolveWorkspaceLayout(
          windowWidth: 744,
          sidebarVisible: true,
          layout: MMSplitMode.split,
          panelOpen: true,
          sizeClass: MMSizeClass.medium,
          windowHeight: 1000,
        ),
        (sidebarVisible: false, mode: MMSplitMode.split, panelWidth: MMSizes.rightPanelWidth),
      );
      // A landscape phone has no height for two panes.
      expect(
        resolveWorkspaceLayout(
          windowWidth: 750,
          sidebarVisible: false,
          layout: MMSplitMode.split,
          panelOpen: false,
          sizeClass: MMSizeClass.medium,
          windowHeight: 300,
        ),
        (sidebarVisible: false, mode: MMSplitMode.primary, panelWidth: 0.0),
      );
      expect(
        resolveWorkspaceLayout(
          windowWidth: 744,
          sidebarVisible: true,
          layout: MMSplitMode.secondary,
          panelOpen: false,
          sizeClass: MMSizeClass.medium,
          windowHeight: 300,
        ).mode,
        MMSplitMode.secondary,
      );
    });

    test('compact shows one pane and a panel almost as wide as the window', () {
      expect(
        resolveWorkspaceLayout(
          windowWidth: 402,
          sidebarVisible: true,
          layout: MMSplitMode.split,
          panelOpen: true,
          sizeClass: MMSizeClass.compact,
        ),
        (sidebarVisible: false, mode: MMSplitMode.primary, panelWidth: 402 - MMSpacing.s * 2),
      );
      expect(
        resolveWorkspaceLayout(
          windowWidth: 402,
          sidebarVisible: false,
          layout: MMSplitMode.secondary,
          panelOpen: false,
          sizeClass: MMSizeClass.compact,
        ),
        (sidebarVisible: false, mode: MMSplitMode.secondary, panelWidth: 0.0),
      );
    });
  });

  group('touch windows', () {
    testWidgets('iPad portrait: source above map, sidebar drawer and companion panel', (tester) async {
      final container = await openWorkspace(tester, ipadPortrait);
      final controller = container.read(workspaceProvider('demo-1').notifier);
      final reader = rectOf(tester, ReaderPane);
      final map = rectOf(tester, MapPane);
      expect(reader.bottom, lessThanOrEqualTo(map.top));
      expect(reader.width, map.width);
      expect(reader.width, ipadPortrait.size.width);
      // The toolbar starts below the status bar.
      expect(tester.getRect(find.byType(MMToolbar).first).top, ipadPortrait.safe.top);
      // The map runs on beneath the home indicator; its controls keep clear.
      expect(tester.getRect(find.byType(MapPane)).bottom, ipadPortrait.size.height - ipadPortrait.safe.bottom);
      expect(
        tester.getRect(find.byTooltip('Zoom In').last).bottom,
        lessThanOrEqualTo(ipadPortrait.size.height - ipadPortrait.safe.bottom),
      );

      // The divider is a 44 pt target that moves vertically and resets on double tap.
      final divider = find.bySemanticsLabel('Divider');
      expect(tester.getSize(divider).height, MMSizes.touchTarget);
      await tester.drag(divider, const Offset(0, 120));
      await tester.pumpAndSettle();
      final moved = container.read(workspaceProvider('demo-1')).splitFraction;
      expect(moved, greaterThan(.5));
      expect(rectOf(tester, ReaderPane).height, greaterThan(reader.height));
      await tester.tap(divider);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(divider);
      await tester.pumpAndSettle();
      expect(container.read(workspaceProvider('demo-1')).splitFraction, .5);

      // Either pane can take the whole window.
      await tester.tap(find.byKey(const ValueKey('toolbar-layout-map')));
      await tester.pumpAndSettle();
      expect(rectOf(tester, MapPane).height, greaterThan(map.height * 1.5));
      await tester.tap(find.byKey(const ValueKey('toolbar-layout-split')));
      await tester.pumpAndSettle();

      // The sidebar is a drawer, closed at first.
      expect(find.byType(WorkspaceSidebar).hitTestable(), findsNothing);
      await tester.tap(find.byTooltip('Show Sidebar'));
      await tester.pumpAndSettle();
      expect(find.byType(WorkspaceSidebar).hitTestable(), findsOneWidget);
      expect(rectOf(tester, ReaderPane).width, ipadPortrait.size.width, reason: 'the drawer floats over the panes');
      await tester.tapAt(Offset(ipadPortrait.size.width - 20, ipadPortrait.size.height / 2));
      await tester.pumpAndSettle();
      expect(find.byType(WorkspaceSidebar).hitTestable(), findsNothing);
      // Its own hide button and opening a document put it away.
      await tester.tap(find.byTooltip('Show Sidebar'));
      await tester.pumpAndSettle();
      controller.toggleSidebar();
      await tester.pumpAndSettle();
      expect(find.byType(WorkspaceSidebar).hitTestable(), findsNothing);
      await tester.tap(find.byTooltip('Show Sidebar'));
      await tester.pumpAndSettle();
      controller.openDocument('c2');
      await tester.pumpAndSettle();
      expect(find.byType(WorkspaceSidebar).hitTestable(), findsNothing);
      container.read(focusRequestsProvider.notifier).request(FocusTarget.search);
      await tester.pumpAndSettle();
      expect(find.byType(WorkspaceSidebar).hitTestable(), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mm-drawer-scrim')).first, warnIfMissed: false);
      await tester.pumpAndSettle();

      // Details occupy their own area and leave the saved layout alone.
      controller.showDetails('c3');
      await tester.pumpAndSettle();
      expect(container.read(workspaceProvider('demo-1')).layout, MMSplitMode.split);
      final panel = find.byKey(const ValueKey('workspace-right-sidebar'));
      expect(panel, findsOneWidget);
      expect(tester.getRect(panel).width, 348);
      expect(tester.getRect(panel).right, ipadPortrait.size.width - MMSpacing.s);
      expect(rectOf(tester, ReaderPane).right, lessThanOrEqualTo(tester.getRect(panel).left));
      await tester.tapAt(const Offset(40, 400));
      await tester.pumpAndSettle();
      expect(container.read(workspaceProvider('demo-1')).panel, RightPanel.details);
      controller.closePanel();
      await tester.pumpAndSettle();
      expect(panel, findsNothing);

      // Touch-sized toolbar buttons.
      expect(tester.getSize(find.byKey(const ValueKey('toolbar-assistant'))), const Size.square(MMSizes.touchTarget));
      // The reader tools stay on one line; zoom and appearance are under More.
      expect(find.byKey(const ValueKey('reader-more')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reader-more')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reader-zoom-slider')), findsOneWidget);
      expect(find.text('Fit Width'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reader-appearance')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).readerStyle, MMReaderStyle.dark);
      await tester.tap(find.byKey(const ValueKey('reader-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fit Width'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('iPad landscape keeps the desktop split with the sidebar in a drawer', (tester) async {
      final container = await openWorkspace(tester, ipadLandscape);
      final reader = rectOf(tester, ReaderPane);
      final map = rectOf(tester, MapPane);
      expect(reader.right, lessThanOrEqualTo(map.left));
      expect(reader.left, 0);
      expect(find.byType(WorkspaceSidebar).hitTestable(), findsNothing);
      expect(find.byKey(const ValueKey('reader-more')), findsOneWidget);
      container.read(workspaceProvider('demo-1').notifier).openPanel(RightPanel.assistant);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('workspace-floating-panel')), findsNothing);
      expect(
        rectOf(tester, MapPane).overlaps(tester.getRect(find.byKey(const ValueKey('workspace-right-sidebar')))),
        isFalse,
      );
    });

    testWidgets('iPhone: one pane at a time with a top switch and thumb dock', (tester) async {
      final container = await openWorkspace(tester, iphone);
      WorkspaceState state() => container.read(workspaceProvider('demo-1'));
      final pane = find.byType(PhoneTabBar);
      expect(pane, findsNothing);
      expect(find.byTooltip('Split'), findsNothing);
      expect(
        tester.getRect(find.byKey(const ValueKey('workspace-pane-switch'))).top,
        greaterThanOrEqualTo(iphone.safe.top),
      );
      expect(find.byType(ReaderPane).hitTestable(), findsOneWidget);
      expect(find.byType(MapPane).hitTestable(), findsNothing);
      await tester.tap(find.text('Map').first);
      await tester.pumpAndSettle();
      expect(state().layout, MMSplitMode.secondary);
      expect(find.byType(MapPane).hitTestable(), findsOneWidget);
      expect(rectOf(tester, MapPane).width, iphone.size.width);
      expect(rectOf(tester, MapPane).bottom, iphone.size.height - iphone.safe.bottom);
      expect(
        tester.getRect(find.byTooltip('Zoom In').last).bottom,
        lessThanOrEqualTo(iphone.size.height - iphone.safe.bottom),
      );
      // The phone reader switch names the source pane "Reading".
      await tester.tap(
        find.descendant(of: find.byKey(const ValueKey('workspace-pane-switch')), matching: find.text('Reading')),
      );
      await tester.pumpAndSettle();
      expect(state().layout, MMSplitMode.primary);
      container.read(workspaceProvider('demo-1').notifier).openPanel(RightPanel.assistant);
      await tester.pumpAndSettle();
      // A compact window raises the panel from the bottom (GUL-542).
      expect(find.byKey(const ValueKey('workspace-floating-panel')), findsNothing);
      expect(tester.getRect(find.byKey(const ValueKey('mm-bottom-sheet'))).width, iphone.size.width);
      expect(tester.takeException(), isNull);
      await settleHud(tester);
    });

    testWidgets('a landscape phone shows one pane without split controls', (tester) async {
      final container = await openWorkspace(tester, iphoneLandscape);
      expect(container.read(workspaceProvider('demo-1')).layout, MMSplitMode.split);
      expect(find.byType(ReaderPane).hitTestable(), findsOneWidget);
      expect(find.byType(MapPane).hitTestable(), findsNothing);
      expect(find.byTooltip('Split'), findsNothing);
      expect(find.byKey(const ValueKey('workspace-pane-switch')), findsOneWidget);
      await tester.tap(find.text('Map').first);
      await tester.pumpAndSettle();
      expect(find.byType(MapPane).hitTestable(), findsOneWidget);
      expect(rectOf(tester, MapPane).left, iphoneLandscape.safe.left);
      expect(rectOf(tester, MapPane).right, iphoneLandscape.size.width - iphoneLandscape.safe.right);
    });

    testWidgets('a tablet keeps stable target sizes while switching between trackpad and finger', (tester) async {
      await openWorkspace(tester, ipadLandscape);
      final assistant = find.byKey(const ValueKey('toolbar-assistant'));
      expect(tester.getSize(assistant), const Size.square(MMSizes.touchTarget));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(600, 500));
      await mouse.moveTo(const Offset(610, 500));
      await tester.pumpAndSettle();
      expect(tester.getSize(assistant), const Size.square(MMSizes.touchTarget));
      await mouse.removePointer();
      await tester.tapAt(const Offset(610, 500));
      await tester.pumpAndSettle();
      expect(tester.getSize(assistant), const Size.square(MMSizes.touchTarget));
    });

    testWidgets('library on a phone: drawer sidebar and a narrow toolbar', (tester) async {
      final container = await pumpDevice(tester, iphone);
      expect(find.byIcon(MMIcons.list), findsNothing);
      final search = tester.getRect(find.byType(MMToolbarSearchField));
      expect(search.width, iphone.size.width - 2 * MMSpacing.l);
      expect(search.top, greaterThanOrEqualTo(tester.getRect(find.byType(MMToolbar).first).bottom));
      await tester.tap(find.byTooltip('Show Sidebar'));
      await tester.pumpAndSettle();
      expect(find.text('Starred').hitTestable(), findsOneWidget);
      expect(
        tester.getSize(find.ancestor(of: find.text('Starred'), matching: find.byType(MMSidebarItem))).height,
        MMSizes.touchTarget,
      );
      await tester.tap(find.text('Starred'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(MMSidebarItem, 'Starred').hitTestable(),
        findsNothing,
        reason: 'picking a filter closes the drawer',
      );
      container.read(libraryViewProvider.notifier).toggleSidebar();
      await tester.pumpAndSettle();
      expect(find.widgetWithText(MMSidebarItem, 'Starred').hitTestable(), findsOneWidget);
      container.read(libraryViewProvider.notifier).toggleSidebar();
      await tester.pumpAndSettle();
      expect(find.widgetWithText(MMSidebarItem, 'Starred').hitTestable(), findsNothing);
    });

    testWidgets('library on iPad portrait: sort without its label', (tester) async {
      await pumpDevice(tester, ipadPortrait);
      expect(find.byIcon(MMIcons.list), findsOneWidget);
      expect(find.byTooltip('By Recent'), findsOneWidget);
    });
  });

  group('desktop windows', () {
    testWidgets('a narrow desktop window keeps the desktop layout', (tester) async {
      final container = await openWorkspace(tester, desktopMin);
      expect(find.byType(WorkspaceSidebar).hitTestable(), findsOneWidget);
      expect(find.byKey(const ValueKey('mm-drawer-scrim')), findsNothing);
      expect(find.byKey(const ValueKey('workspace-pane-switch')), findsNothing);
      expect(find.byKey(const ValueKey('reader-more')), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('toolbar-assistant'))), const Size.square(28));
      container.read(workspaceProvider('demo-1').notifier).showDetails('c3');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('workspace-floating-panel')), findsNothing);
      // Touch input does not resize desktop controls.
      await tester.tapAt(const Offset(600, 300));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(const ValueKey('toolbar-assistant'))), const Size.square(28));
    });

    testWidgets('a wide desktop window aligns content with the flat sidebar', (tester) async {
      await openWorkspace(tester, desktop);
      final reader = rectOf(tester, ReaderPane);
      expect(reader.left, MMSizes.sidebarWidth);
      expect(reader.right, lessThanOrEqualTo(rectOf(tester, MapPane).left));
      expect(tester.getRect(find.byType(MMToolbar).first).top, 0);
    });
  });
}
