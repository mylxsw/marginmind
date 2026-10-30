import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/widgets/annotation_color_button.dart';
import 'package:marginmind/features/workspace/widgets/annotation_line_style_picker.dart';
import 'package:marginmind/features/workspace/widgets/annotation_palette.dart';
import 'package:marginmind/features/workspace/widgets/highlight_color_button.dart';
import 'package:marginmind/features/workspace/widgets/reader_toolbar.dart';
import 'package:marginmind/features/workspace/widgets/underline_tool_button.dart';
import 'package:marginmind/features/workspace/widgets/underline_style_toolbar.dart';
import 'package:marginmind/features/workspace/widgets/selection_toolbar.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import 'assistant_quick_actions_test.dart' show screenshot;
import 'helpers.dart';
import 'selection_toolbar_test.dart' show selection;

Future<void> toolbarWithPaletteScreenshot(WidgetTester tester, String name) async {
  final output = Platform.environment['MM_SCREENSHOTS'];
  if (output == null) return;
  final bounds = tester
      .getRect(find.byType(SelectionToolbar))
      .expandToInclude(tester.getRect(find.byKey(const ValueKey('annotation-color-palette'))))
      .inflate(6);
  final image = (await tester.runAsync(
    () => (tester.binding.renderViews.first.debugLayer! as OffsetLayer).toImage(bounds, pixelRatio: 2),
  ))!;
  final bytes = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png)))!;
  await tester.runAsync(() => File('$output/$name.png').writeAsBytes(bytes.buffer.asUint8List()));
  image.dispose();
}

void main() {
  setUpAll(() async {
    if (Platform.environment['MM_SCREENSHOTS'] == null) return;
    final font = ByteData.sublistView(File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf').readAsBytesSync());
    for (final family in [
      '.AppleSystemUIFont',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      'Roboto',
      'PingFang SC',
    ]) {
      await (FontLoader(family)..addFont(Future.value(font))).load();
    }
    await (FontLoader(
      'packages/lucide_icons_flutter/Lucide',
    )..addFont(rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'))).load();
    final cache = Platform.environment['PUB_CACHE'] ?? '${Platform.environment['HOME']}/.pub-cache';
    final icons = Directory('$cache/hosted/pub.dev')
        .listSync()
        .whereType<Directory>()
        .lastWhere((d) => d.path.contains('cupertino_icons-'));
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
          Future.value(ByteData.sublistView(File('${icons.path}/assets/CupertinoIcons.ttf').readAsBytesSync())),
        ))
        .load();
  });

  test('color never changes any active tool and is shared across workspaces and restart', () async {
    final overrides = await testOverrides();
    var container = ProviderContainer(overrides: overrides);
    final provider = workspaceProvider('demo-1');
    container.listen(provider, (_, _) {});
    container.listen(workspaceProvider('other'), (_, _) {});
    await container.read(contentProvider('demo-1').future);
    final controller = container.read(provider.notifier);
    for (final tool in AnnotationTool.values) {
      await controller.setTool(tool);
      await controller.setColor(MMAnnotationColor.purple);
      expect(container.read(provider).tool, tool);
      expect(container.read(workspaceProvider('other')).color, MMAnnotationColor.purple);
    }
    await controller.setTool(AnnotationTool.underline);
    await controller.styleUnderline(style: AnnotationLineStyle.dashed);
    container.dispose();
    container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    expect(container.read(provider).color, MMAnnotationColor.purple);
    expect(container.read(provider).underlineStyle, AnnotationLineStyle.dashed);
    expect(container.read(provider).tool, AnnotationTool.underline);
  });

  for (final appearance in ['light', 'dark']) {
    testWidgets('page toolbar retains its original brush buttons and popups in $appearance', (tester) async {
      final container = await pumpApp(tester, prefs: {'settings.appearance': appearance});
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      final top = find.byType(ReaderToolbar);
      expect(find.descendant(of: top, matching: find.byType(AnnotationColorButton)), findsNothing);
      await screenshot(tester, 'page-toolbar-$appearance', target: top);
      expect(find.descendant(of: top, matching: find.byType(HighlightColorButton)), findsOneWidget);
      expect(find.descendant(of: top, matching: find.byType(UnderlineToolButton)), findsOneWidget);
      await tester.tap(find.descendant(of: top, matching: find.byType(HighlightColorButton)));
      await tester.pumpAndSettle();
      final colors = find.byKey(const ValueKey('highlight-color-palette'));
      expect(colors, findsOneWidget);
      expect(find.descendant(of: colors, matching: find.byType(MMFloatingToolbarColor)), findsNWidgets(3));
      expect(container.read(workspaceProvider('demo-1')).tool, AnnotationTool.highlight);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: top, matching: find.byType(UnderlineToolButton)));
      await tester.pumpAndSettle();
      expect(find.byType(UnderlineStyleToolbar), findsOneWidget);
      await screenshot(tester, 'page-underline-palette-$appearance', target: find.byType(UnderlineStyleToolbar));
      expect(find.byKey(const ValueKey('annotation-color-palette')), findsNothing);
      await tester.tap(find.byTooltip('Green'));
      await tester.pumpAndSettle();
      expect(container.read(workspaceProvider('demo-1')).underlineColor, MMAnnotationColor.green);
      expect(container.read(workspaceProvider('demo-1')).color, MMAnnotationColor.yellow);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(container.read(workspaceProvider('demo-1')).tool, AnnotationTool.select);
    });
  }

  for (final appearance in ['light', 'dark']) {
    testWidgets('neutral actions dismiss after applying; saved marks retain editable settings in $appearance', (
      tester,
    ) async {
      final container = await pumpApp(tester, prefs: {'settings.appearance': appearance, 'settings.language': 'zh'});
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      final provider = workspaceProvider('demo-1');
      final controller = container.read(provider.notifier);
      await controller.onSelectionCommitted('c1', selection);
      await tester.pumpAndSettle();
      final toolbar = find.byType(SelectionToolbar);
      final color = find.descendant(of: toolbar, matching: find.byType(AnnotationColorButton));
      final highlight = find.byKey(const ValueKey('selection-highlight'));
      final underline = find.byKey(const ValueKey('selection-underline'));
      expect(tester.getCenter(color).dx, lessThan(tester.getCenter(highlight).dx));
      expect(tester.getCenter(highlight).dx, lessThan(tester.getCenter(underline).dx));
      expect(tester.widget<MMToolbarButton>(highlight).selected, isFalse);
      await screenshot(tester, 'toolbar-$appearance', target: toolbar);

      final before = controller.content.annotations.length;
      await tester.tap(color);
      await tester.pumpAndSettle();
      final palette = find.byKey(const ValueKey('annotation-color-palette'));
      expect(tester.getRect(palette).top, greaterThan(tester.getRect(color).bottom));
      final swatches = find.descendant(of: palette, matching: find.byType(MMFloatingToolbarColor));
      expect(swatches, findsNWidgets(4));
      final entries = tester
          .widget<MMFloatingToolbar>(find.descendant(of: palette, matching: find.byType(MMFloatingToolbar)))
          .children;
      expect(entries.take(4).every((w) => w is MMFloatingToolbarColor), isTrue);
      expect(entries[4], isA<AnnotationMoreColorsButton>());
      expect(entries, hasLength(5));
      expect(find.descendant(of: palette, matching: find.byType(Text)), findsNothing);
      final more = find.descendant(of: palette, matching: find.byType(AnnotationMoreColorsButton));
      for (final swatch in swatches.evaluate()) {
        expect(tester.getCenter(find.byWidget(swatch.widget)).dy, tester.getCenter(more).dy);
      }
      expect(find.byType(AnnotationLineStylePicker), findsNothing);
      await tester.tap(find.byTooltip('绿色'));
      await tester.pumpAndSettle();
      expect(controller.content.annotations.length, before);
      expect(container.read(provider).pending, isA<PendingSelection>());
      expect(tester.widget<MMToolbarButton>(highlight).selected, isFalse);
      await screenshot(tester, 'highlight-palette-$appearance', target: palette);
      await toolbarWithPaletteScreenshot(tester, 'highlight-settings-$appearance');

      // Applying a marker closes both toolbars; clicking the saved mark opens its settings again.
      await tester.tap(underline);
      await tester.pumpAndSettle();
      final id = controller.content.annotations.last.id;
      expect(controller.content.annotations.length, before + 1);
      expect(container.read(provider).pending, isNull);
      expect(toolbar, findsNothing);
      expect(palette, findsNothing);
      controller.tapHighlight(id, selection.viewportRect!);
      await tester.pumpAndSettle();
      await tester.tap(color);
      await tester.pumpAndSettle();
      expect(tester.widget<MMToolbarButton>(underline).selected, isTrue);
      expect(find.byType(AnnotationLineStylePicker), findsOneWidget);
      expect(
        tester
            .widget<MMFloatingToolbar>(find.descendant(of: palette, matching: find.byType(MMFloatingToolbar)))
            .children,
        hasLength(7),
      );
      expect(tester.getCenter(find.byType(AnnotationLineStylePicker)).dy, tester.getCenter(more).dy);
      await tester.tap(find.byKey(const ValueKey('line-style-wavy')));
      await tester.pumpAndSettle();
      expect(controller.content.annotation(id)?.lineStyle, AnnotationLineStyle.wavy);
      await tester.tap(find.byTooltip('蓝色'));
      await tester.pumpAndSettle();
      expect(controller.content.annotation(id)?.colorIndex, MMAnnotationColor.blue.index);
      expect(tester.widget<MMToolbarButton>(underline).selected, isTrue);
      expect(container.read(provider).color, MMAnnotationColor.blue);
      await screenshot(tester, 'underline-palette-$appearance', target: palette);
      await toolbarWithPaletteScreenshot(tester, 'underline-settings-$appearance');

      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(palette, findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('highlight-color-hex')), '#12A4B8');
      await tester.pumpAndSettle();
      expect(container.read(provider).color, MMAnnotationColor.blue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('highlight-custom-color-picker')), findsNothing);
      expect(tester.widget<MMToolbarButton>(underline).selected, isTrue);
      await tester.tap(more);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('highlight-color-hex')), '#12A4B8');
      await tester.tap(find.byKey(const ValueKey('highlight-color-apply')));
      await tester.pumpAndSettle();
      expect(controller.content.annotation(id)?.colorIndex, MMAnnotationColor.tryParse('#12A4B8')!.index);
      expect(container.read(provider).color.hex, '#12A4B8');
      expect(
        find.descendant(
          of: palette,
          matching: find.byWidgetPredicate((w) => w is MMFloatingToolbarColor && w.color.hex == '#12A4B8'),
        ),
        findsOneWidget,
      );
      expect(tester.widget<MMToolbarButton>(underline).selected, isTrue);
      expect(controller.content.annotations.length, before + 1);

      await tester.tap(highlight);
      await tester.pumpAndSettle();
      expect(controller.content.annotations.length, before + 1);
      expect(controller.content.annotation(id)?.kind, AnnotationKind.highlight);
      expect(find.byType(AnnotationLineStylePicker), findsNothing);
      expect(palette, findsNothing);
      expect(toolbar, findsNothing);
      expect(container.read(provider).pending, isNull);
      await controller.undo();
      await tester.pumpAndSettle();
      expect(controller.content.annotation(id)?.kind, AnnotationKind.underline);
      expect(controller.content.annotation(id)?.lineStyle, AnnotationLineStyle.wavy);
      controller.tapHighlight(id, selection.viewportRect!);
      await tester.pumpAndSettle();
      expect(tester.widget<MMToolbarButton>(underline).selected, isTrue);
      await settleHud(tester);
    });
  }

  test('changing tool and color on an existing mark preserves linked cards and undo', () async {
    final container = ProviderContainer(overrides: await testOverrides());
    addTearDown(container.dispose);
    final provider = workspaceProvider('demo-1');
    container.listen(provider, (_, _) {});
    await container.read(contentProvider('demo-1').future);
    final controller = container.read(provider.notifier);
    final annotation = controller.content.annotations.single;
    final card = controller.content.cardForAnnotation(annotation.id)!;
    controller.tapHighlight(annotation.id);
    await controller.applyPendingTextAnnotation(AnnotationTool.underline);
    await controller.setAnnotationColor(MMAnnotationColor.blue, annotationId: annotation.id);
    expect(controller.content.annotations, hasLength(1));
    expect(controller.content.cardForAnnotation(annotation.id)?.id, card.id);
    expect(
      controller.content.annotation(controller.content.card(card.id)!.annotationId!)?.colorIndex,
      MMAnnotationColor.blue.index,
    );
    expect(container.read(provider).pending, isA<PendingHighlight>());
    await controller.undo();
    await controller.undo();
    expect(controller.content.annotation(annotation.id)?.kind, AnnotationKind.highlight);
    expect(
      controller.content.annotation(controller.content.card(card.id)!.annotationId!)?.colorIndex,
      annotation.colorIndex,
    );
  });

  for (final size in [const Size(834, 1194), const Size(1194, 834)]) {
    for (final pointer in [PointerDeviceKind.touch, PointerDeviceKind.stylus, PointerDeviceKind.mouse]) {
      for (final tool in [AnnotationTool.highlight, AnnotationTool.underline]) {
        testWidgets('iPad $size ${pointer.name}: ${tool.name} applies without opening color settings', (tester) async {
          final container = await pumpApp(
            tester,
            size: size,
            overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(false)],
          );
          container.read(navigationProvider.notifier).openStudySet('demo-1');
          await tester.pumpAndSettle();
          final provider = workspaceProvider('demo-1');
          final controller = container.read(provider.notifier);
          await controller.setTool(AnnotationTool.select);
          await controller.onSelectionCommitted('c1', selection);
          await tester.pumpAndSettle();
          final before = controller.content.annotations.length;
          final action = find.byKey(
            ValueKey('selection-${tool == AnnotationTool.highlight ? 'highlight' : 'underline'}'),
          );
          final palette = find.byKey(const ValueKey('annotation-color-palette'));
          final gesture = await tester.startGesture(tester.getCenter(action), kind: pointer);
          await tester.pump();
          expect(palette, findsNothing);
          expect(find.byType(UnderlineStyleToolbar), findsNothing);
          expect(find.byKey(const ValueKey('highlight-color-palette')), findsNothing);
          await gesture.up();
          await tester.pumpAndSettle();
          expect(controller.content.annotations.length, before + 1);
          expect(
            controller.content.annotations.last.kind,
            tool == AnnotationTool.highlight ? AnnotationKind.highlight : AnnotationKind.underline,
          );
          expect(find.byType(SelectionToolbar), findsNothing);
          expect(palette, findsNothing);
          expect(find.byType(UnderlineStyleToolbar), findsNothing);
          expect(find.byKey(const ValueKey('highlight-color-palette')), findsNothing);
          expect(container.read(provider).tool, AnnotationTool.select);

          controller.tapHighlight(controller.content.annotations.last.id, selection.viewportRect!);
          await tester.pumpAndSettle();
          final color = find.descendant(
            of: find.byType(SelectionToolbar),
            matching: find.byType(AnnotationColorButton),
          );
          final colorTap = await tester.startGesture(tester.getCenter(color), kind: pointer);
          await colorTap.up();
          await tester.pumpAndSettle();
          expect(palette, findsOneWidget);
          expect(
            find.byType(AnnotationLineStylePicker),
            tool == AnnotationTool.underline ? findsOneWidget : findsNothing,
          );
          expect(tester.takeException(), isNull);
          await settleHud(tester);
        }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
      }
    }
  }

  for (final width in [320.0, 768.0]) {
    testWidgets('text markers and settings fit a touch screen of width $width', (tester) async {
      final container = await pumpApp(
        tester,
        size: Size(width, 900),
        overrides: [touchPlatformProvider.overrideWithValue(true), phoneProvider.overrideWithValue(width < 600)],
      );
      container.read(navigationProvider.notifier).openStudySet('demo-1');
      await tester.pumpAndSettle();
      final controller = container.read(workspaceProvider('demo-1').notifier);
      await controller.onSelectionCommitted('c1', selection);
      await tester.pumpAndSettle();
      final toolbar = find.byType(SelectionToolbar);
      expect(tester.getRect(toolbar).left, greaterThanOrEqualTo(0));
      expect(tester.getRect(toolbar).right, lessThanOrEqualTo(width));
      await tester.tap(find.byKey(const ValueKey('selection-underline')));
      await tester.pumpAndSettle();
      expect(toolbar, findsNothing);
      controller.tapHighlight(controller.content.annotations.last.id, selection.viewportRect!);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: toolbar, matching: find.byType(AnnotationColorButton)));
      await tester.pumpAndSettle();
      final palette = find.byKey(const ValueKey('annotation-color-palette'));
      expect(tester.getRect(palette).left, greaterThanOrEqualTo(0));
      expect(tester.getRect(palette).right, lessThanOrEqualTo(width));
      expect(find.byType(AnnotationLineStylePicker), findsOneWidget);
      expect(tester.takeException(), isNull);
      await settleHud(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  }
}
