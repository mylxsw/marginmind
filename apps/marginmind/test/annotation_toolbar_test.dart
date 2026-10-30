import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/widgets/annotation_color_button.dart';
import 'package:marginmind/features/workspace/widgets/annotation_line_style_picker.dart';
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
    testWidgets('three controls, contextual palette, same mark and undo in $appearance', (tester) async {
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
      expect(tester.widget<MMToolbarButton>(highlight).selected, isTrue);
      await screenshot(tester, 'toolbar-$appearance', target: toolbar);

      final before = controller.content.annotations.length;
      await tester.tap(color);
      await tester.pumpAndSettle();
      final palette = find.byKey(const ValueKey('annotation-color-palette'));
      expect(tester.getRect(palette).top, greaterThan(tester.getRect(color).bottom));
      expect(find.byType(AnnotationLineStylePicker), findsNothing);
      await tester.tap(find.byTooltip('绿色'));
      await tester.pumpAndSettle();
      expect(controller.content.annotations.length, before);
      expect(container.read(provider).pending, isA<PendingSelection>());
      expect(tester.widget<MMToolbarButton>(highlight).selected, isTrue);
      await screenshot(tester, 'highlight-palette-$appearance', target: palette);
      await toolbarWithPaletteScreenshot(tester, 'highlight-settings-$appearance');

      // The palette stays usable while its sibling tool buttons switch modes.
      await tester.tap(underline);
      await tester.pumpAndSettle();
      final id = controller.content.annotations.last.id;
      expect(controller.content.annotations.length, before + 1);
      expect(tester.widget<MMToolbarButton>(underline).selected, isTrue);
      expect(find.byType(AnnotationLineStylePicker), findsOneWidget);
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

      await tester.tap(highlight);
      await tester.pumpAndSettle();
      expect(controller.content.annotations.length, before + 1);
      expect(controller.content.annotation(id)?.kind, AnnotationKind.highlight);
      expect(find.byType(AnnotationLineStylePicker), findsNothing);
      expect(tester.widget<MMToolbarButton>(highlight).selected, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(palette, findsNothing);
      expect(toolbar, findsOneWidget);
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
