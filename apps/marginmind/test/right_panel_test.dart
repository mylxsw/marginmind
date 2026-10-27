import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app_commands.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/widgets/card_details.dart';
import 'package:marginmind/features/workspace/widgets/mind_map_canvas.dart';
import 'package:marginmind/features/workspace/widgets/right_panel.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:marginmind/features/workspace/workspace_layout.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:mm_design/mm_design.dart';
import 'package:marginmind/settings/app_settings.dart';
import 'package:mm_pdf/mm_pdf.dart';
import 'package:mm_platform/mm_platform.dart';

import 'card_edit_test.dart' show key;
import 'helpers.dart';

const _excerptId = 'c6';
const _quote = '这条先陡后平的曲线，被称为遗忘曲线。';

final _panel = find.byType(RightPanelView);
Finder _inPanel(Finder finder) => find.descendant(of: _panel, matching: finder);

/// Opens demo-1 in a window of [size].
Future<({ProviderContainer container, WorkspaceController controller})> _open(
  WidgetTester tester, {
  Size size = const Size(1280, 820),
  List<Override> overrides = const [],
  InMemoryStudySetContentRepository? content,
}) async {
  final container = await pumpApp(tester, size: size, overrides: overrides, content: content);
  container.read(navigationProvider.notifier).openStudySet('demo-1');
  await tester.pumpAndSettle();
  return (container: container, controller: container.read(workspaceProvider('demo-1').notifier));
}

WorkspaceState _state(ProviderContainer c) => c.read(workspaceProvider('demo-1'));

Matrix4 _mapView(WidgetTester tester) => tester.widget<MindMapCanvas>(find.byType(MindMapCanvas)).transformation.value;

bool _sidebarShown(WidgetTester tester) =>
    tester.widget<MMWindowScaffold>(find.byType(MMWindowScaffold)).sidebarVisible;

/// A study set whose excerpt is too long for its card, with a sibling below it.
InMemoryStudySetContentRepository _longExcerpt() {
  var n = 100;
  final editor = StudySetEditor(newId: () => 'x${++n}', now: () => testNow);
  final base = demoContent();
  final topic = base.cards.firstWhere((c) => c.title == '遗忘的规律');
  final (withLong, _) = editor.createExcerpt(
    base,
    documentId: 'c1',
    page: 30,
    rects: const [PageRect(10, 100, 200, 88)],
    quote: '记忆并不是一次写入就永久保存的，' * 12,
    colorIndex: 2,
    parentId: topic.id,
  );
  return InMemoryStudySetContentRepository({'demo-1': withLong});
}

String _longCardId(WorkspaceController controller) =>
    controller.content.cards.singleWhere((c) => c.kind == CardKind.excerpt && c.id != _excerptId).id;

void main() {
  group('layout rules', () {
    test('without the panel the window keeps the existing split rules', () {
      final r = resolveWorkspaceLayout(
        windowWidth: 1000,
        sidebarVisible: true,
        layout: MMSplitMode.split,
        panelOpen: false,
      );
      expect(r, (sidebarVisible: true, mode: MMSplitMode.primary, panelWidth: 0.0));
      expect(
        resolveWorkspaceLayout(windowWidth: 1400, sidebarVisible: true, layout: MMSplitMode.split, panelOpen: false),
        (sidebarVisible: true, mode: MMSplitMode.split, panelWidth: 0.0),
      );
    });

    test('a wide window shows the 400 pt panel beside the sidebar', () {
      for (final layout in [MMSplitMode.primary, MMSplitMode.secondary]) {
        expect(resolveWorkspaceLayout(windowWidth: 1280, sidebarVisible: true, layout: layout, panelOpen: true), (
          sidebarVisible: true,
          mode: layout,
          panelWidth: MMSizes.rightPanelWidth,
        ));
      }
      expect(
        resolveWorkspaceLayout(windowWidth: 1800, sidebarVisible: true, layout: MMSplitMode.split, panelOpen: true),
        (sidebarVisible: true, mode: MMSplitMode.split, panelWidth: MMSizes.rightPanelWidth),
      );
    });

    test('a narrow window collapses the sidebar first and narrows the panel to 360 pt', () {
      expect(
        resolveWorkspaceLayout(windowWidth: 960, sidebarVisible: true, layout: MMSplitMode.primary, panelOpen: true),
        (sidebarVisible: false, mode: MMSplitMode.primary, panelWidth: MMSizes.rightPanelNarrowWidth),
      );
      // Split still fits once the sidebar is gone…
      expect(
        resolveWorkspaceLayout(windowWidth: 1280, sidebarVisible: true, layout: MMSplitMode.split, panelOpen: true),
        (sidebarVisible: false, mode: MMSplitMode.split, panelWidth: MMSizes.rightPanelNarrowWidth),
      );
      // …or falls back to the source alone, by the split view's own rule.
      expect(
        resolveWorkspaceLayout(windowWidth: 1000, sidebarVisible: true, layout: MMSplitMode.split, panelOpen: true),
        (sidebarVisible: false, mode: MMSplitMode.primary, panelWidth: MMSizes.rightPanelNarrowWidth),
      );
      // A hidden sidebar leaves room for the full panel.
      expect(
        resolveWorkspaceLayout(windowWidth: 800, sidebarVisible: false, layout: MMSplitMode.secondary, panelOpen: true),
        (sidebarVisible: false, mode: MMSplitMode.secondary, panelWidth: MMSizes.rightPanelWidth),
      );
      // The reader's own sidebar raises what the source pane needs.
      expect(
        resolveWorkspaceLayout(
          windowWidth: 1100,
          sidebarVisible: true,
          layout: MMSplitMode.primary,
          panelOpen: true,
          minReader: 488,
        ).panelWidth,
        MMSizes.rightPanelNarrowWidth,
      );
    });
  });

  group('right panel', () {
    testWidgets('details from the map hide the source; closing restores layout, sidebar, view and focus', (
      tester,
    ) async {
      final app = await _open(tester);
      app.controller.selectCard(_excerptId);
      await tester.pumpAndSettle();
      final view = _mapView(tester).clone();
      expect(_state(app.container).layout, MMSplitMode.split);

      app.controller.showDetails();
      await tester.pumpAndSettle();
      expect(_state(app.container).panel, RightPanel.details);
      expect(
        _state(app.container).layout,
        MMSplitMode.secondary,
        reason: 'opened from the map: the source steps aside',
      );
      expect(_sidebarShown(tester), isTrue);
      expect(tester.getSize(_panel).width, MMSizes.rightPanelWidth);
      expect(_inPanel(find.text(_quote)), findsOneWidget);
      expect(_inPanel(find.text('Excerpt')), findsOneWidget);
      expect(_mapView(tester), view, reason: 'opening the panel leaves the map view alone');

      await tester.tap(_inPanel(find.byTooltip('Close')));
      await tester.pumpAndSettle();
      expect(_panel, findsNothing);
      final state = _state(app.container);
      expect(state.panel, isNull);
      expect(state.layout, MMSplitMode.split);
      expect(state.sidebarVisible, isTrue);
      expect(state.selectedCardId, _excerptId);
      expect(_mapView(tester), view, reason: 'closing the details does not pan or zoom the map');
      final focus = FocusManager.instance.primaryFocus!.context!;
      expect(Actions.maybeFind<MindMapIntent>(focus), isNotNull, reason: 'the keyboard is back on the map');
      await settleHud(tester);
    });

    testWidgets('origin decides which pane steps aside; switching content keeps the restore point', (tester) async {
      final app = await _open(tester);
      app.controller.openPanel(RightPanel.assistant, origin: PanelOrigin.reader);
      await tester.pumpAndSettle();
      expect(_state(app.container).layout, MMSplitMode.primary, reason: 'from the source: the map steps aside');
      expect(_inPanel(find.text('Connect an AI service')), findsOneWidget);
      expect(_inPanel(find.text('Assistant')), findsOneWidget);

      // Another content in the open panel does not move the panes again.
      app.controller.selectCard(_excerptId);
      app.controller.showDetails();
      await tester.pumpAndSettle();
      expect(_state(app.container).layout, MMSplitMode.primary);
      expect(_inPanel(find.text('Excerpt')), findsOneWidget);
      app.controller.toggleAssistantPanel();
      await tester.pumpAndSettle();
      expect(_state(app.container).panel, RightPanel.assistant);
      app.controller.toggleAssistantPanel();
      await tester.pumpAndSettle();
      expect(_state(app.container).panel, isNull);
      expect(_state(app.container).layout, MMSplitMode.split);

      // From the toolbar, and outside split layout, the panes stay as they are.
      app.controller.openPanel(RightPanel.assistant);
      await tester.pumpAndSettle();
      expect(_state(app.container).layout, MMSplitMode.split);
      // A research started from a pane while the panel is open beside both
      // still puts the other pane aside; closing restores the split.
      app.controller.openPanel(RightPanel.assistant, origin: PanelOrigin.map);
      await tester.pumpAndSettle();
      expect(_state(app.container).layout, MMSplitMode.secondary);
      app.controller.closePanel();
      await tester.pumpAndSettle();
      expect(_state(app.container).layout, MMSplitMode.split);
      app.controller.setLayout(MMSplitMode.secondary);
      app.controller.openPanel(RightPanel.assistant, origin: PanelOrigin.reader);
      await tester.pumpAndSettle();
      expect(_state(app.container).layout, MMSplitMode.secondary);
      // Layout changes while open are undone on close, like the sidebar.
      app.controller.setLayout(MMSplitMode.primary);
      app.controller.toggleSidebar();
      app.controller.closePanel();
      await tester.pumpAndSettle();
      expect(_state(app.container).layout, MMSplitMode.secondary);
      expect(_state(app.container).sidebarVisible, isTrue);
      app.controller.closePanel(); // Closing twice is harmless.
      await settleHud(tester);
    });

    testWidgets('a narrow window collapses the sidebar beside a 360 pt panel and brings it back', (tester) async {
      final app = await _open(tester, size: const Size(1000, 720));
      expect(_sidebarShown(tester), isTrue);
      app.controller.selectCard(_excerptId);
      app.controller.showDetails();
      await tester.pumpAndSettle();
      expect(_sidebarShown(tester), isFalse);
      expect(_state(app.container).sidebarVisible, isTrue, reason: 'the user’s choice is kept');
      expect(_state(app.container).sidebarAutoCollapsed, isTrue);
      expect(tester.getSize(_panel).width, MMSizes.rightPanelNarrowWidth);
      expect(tester.takeException(), isNull);

      app.controller.closePanel();
      await tester.pumpAndSettle();
      expect(_sidebarShown(tester), isTrue);
      expect(_state(app.container).sidebarAutoCollapsed, isFalse);

      // Asking for the sidebar while there is no room for both gives it the
      // panel's place.
      app.controller.showDetails();
      await tester.pumpAndSettle();
      expect(_sidebarShown(tester), isFalse);
      app.controller.toggleSidebar();
      await tester.pumpAndSettle();
      expect(_state(app.container).panel, isNull);
      expect(_sidebarShown(tester), isTrue);
      expect(_state(app.container).layout, MMSplitMode.split);
      await settleHud(tester);
    });

    testWidgets('dark appearance renders the panel with the assistant and details', (tester) async {
      final app = await _open(tester);
      await app.container.read(settingsProvider.notifier).setAppearance(AppearancePreference.dark);
      await tester.pumpAndSettle();
      app.controller.toggleAssistantPanel();
      await tester.pumpAndSettle();
      final colors = MMColors.dark;
      final header = tester.widget<Text>(_inPanel(find.text('Assistant')));
      expect(header.style!.color, colors.label);
      expect(tester.takeException(), isNull);
      app.controller.selectCard(_excerptId);
      app.controller.showDetails();
      await tester.pumpAndSettle();
      expect(_inPanel(find.text(_quote)), findsOneWidget);
      expect(tester.takeException(), isNull);
      await settleHud(tester);
    });
  });

  group('commands', () {
    testWidgets('the assistant does not depend on research being available', (tester) async {
      final app = await _open(tester, overrides: [researchAvailableProvider.overrideWithValue(false)]);
      expect(find.byTooltip(RegExp('^Research')), findsNothing);
      expect(find.byKey(const ValueKey('toolbar-assistant')), findsOneWidget);
      await _press(tester, AppShortcuts.assistantPanel);
      expect(_state(app.container).panel, RightPanel.assistant);
    });

    testWidgets('the toolbar button and shortcut toggle the assistant panel', (tester) async {
      final app = await _open(tester);
      final button = find.byTooltip('Assistant（${describeShortcut(AppShortcuts.assistantPanel)}）');
      expect(button, findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(_state(app.container).panel, RightPanel.assistant);
      await _press(tester, AppShortcuts.assistantPanel);
      expect(_state(app.container).panel, isNull);
      await _press(tester, AppShortcuts.assistantPanel);
      expect(_state(app.container).panel, RightPanel.assistant);
    });

    test('new shortcuts avoid the commands they sit beside', () {
      for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
        debugDefaultTargetPlatformOverride = platform;
        final taken = [
          AppShortcuts.review,
          AppShortcuts.toggleAreaTool,
          AppShortcuts.toggleSidebar,
          ...mindMapShortcuts.entries.where((e) => e.value != MindMapCommand.expand).map((e) => e.key),
        ];
        for (final shortcut in [AppShortcuts.assistantPanel, AppShortcuts.cardDetails, AppShortcuts.toggleCardText]) {
          expect(taken.map(describeShortcut), isNot(contains(describeShortcut(shortcut))), reason: '$platform');
        }
      }
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(describeShortcut(AppShortcuts.assistantPanel), '⌃⌘R');
      expect(describeShortcut(AppShortcuts.cardDetails), '⌘I');
      expect(describeShortcut(AppShortcuts.toggleCardText), '⌥Space');
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('⌘I shows and hides the selected card’s details; the details follow the selection', (tester) async {
      final app = await _open(tester);
      await _press(tester, AppShortcuts.cardDetails);
      expect(_state(app.container).panel, isNull, reason: 'nothing selected');
      app.controller.selectCard(_excerptId);
      await tester.pumpAndSettle();
      await _press(tester, AppShortcuts.cardDetails);
      expect(_state(app.container).panel, RightPanel.details);

      app.controller.selectCard('c3');
      await tester.pumpAndSettle();
      expect(_inPanel(find.text('Topic')), findsOneWidget);
      app.controller.selectCard(null);
      await tester.pumpAndSettle();
      expect(_inPanel(find.text('Topic')), findsOneWidget, reason: 'the last card stays shown');

      await _press(tester, AppShortcuts.cardDetails);
      expect(_state(app.container).panel, isNull);
      expect(_state(app.container).selectedCardId, 'c3', reason: 'focus returns to the card the details showed');
      await settleHud(tester);
    });

    testWidgets('double-click and the context menu open an excerpt’s details', (tester) async {
      final app = await _open(tester);
      await showWholeMap(tester);
      await doubleTap(tester, find.text(_quote));
      expect(_state(app.container).panel, RightPanel.details);
      expect(_state(app.container).editingCardId, isNull, reason: 'double-click no longer edits an excerpt');
      app.controller.closePanel();
      await tester.pumpAndSettle();

      // Topics still edit in place on double-click.
      await doubleTap(tester, find.text('遗忘的规律'));
      expect(_state(app.container).editingCardId, 'c3');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_state(app.container).panel, isNull);

      await tester.tap(find.text(_quote), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show Details'));
      await tester.pumpAndSettle();
      expect(_state(app.container).panel, RightPanel.details);
      expect(_state(app.container).detailsCardId, _excerptId);
      await settleHud(tester);
    });
  });

  group('card details', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    String? clipboard;
    var failClipboard = false;
    setUp(() {
      clipboard = null;
      failClipboard = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            if (failClipboard) throw PlatformException(code: 'unavailable');
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    Finder titleField() => _inPanel(find.byType(MMInlineTextField));

    testWidgets('the title is edited in the panel: Enter saves one undo step, Esc restores', (tester) async {
      final app = await _open(tester);
      app.controller.selectCard(_excerptId);
      app.controller.showDetails();
      await tester.pumpAndSettle();
      expect(_inPanel(find.text('Add Title')), findsOneWidget, reason: 'an untitled excerpt shows the placeholder');

      await tester.tap(titleField());
      await tester.pumpAndSettle();
      await tester.enterText(titleField(), '  遗忘曲线  ');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(app.controller.content.card(_excerptId)!.title, '遗忘曲线');
      expect(find.descendant(of: find.byType(MindMapCanvas), matching: find.text('遗忘曲线')), findsOneWidget);
      expect(_state(app.container).panel, RightPanel.details, reason: 'Enter keeps the panel open');

      await tester.tap(titleField());
      await tester.pumpAndSettle();
      await tester.enterText(titleField(), 'discarded');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(app.controller.content.card(_excerptId)!.title, '遗忘曲线');
      expect(tester.widget<MMInlineTextField>(titleField()).controller.text, '遗忘曲线');
      expect(_state(app.container).panel, RightPanel.details, reason: 'Esc in the field belongs to the field');

      await app.controller.undo();
      await tester.pumpAndSettle();
      expect(app.controller.content.card(_excerptId)!.title, '');
      expect(tester.widget<MMInlineTextField>(titleField()).controller.text, '', reason: 'follows undo');

      // A topic keeps its title when it is cleared.
      app.controller.selectCard('c3');
      await tester.pumpAndSettle();
      await tester.tap(titleField());
      await tester.enterText(titleField(), '   ');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(app.controller.content.card('c3')!.title, '遗忘的规律');
      expect(tester.widget<MMInlineTextField>(titleField()).controller.text, '遗忘的规律');

      // Typing and then moving to another card keeps the text.
      await tester.tap(titleField());
      await tester.enterText(titleField(), '遗忘的规律（改）');
      app.controller.selectCard(_excerptId);
      await tester.pumpAndSettle();
      expect(app.controller.content.card('c3')!.title, '遗忘的规律（改）');
      await settleHud(tester);
    });

    testWidgets('Esc elsewhere in the panel closes it', (tester) async {
      final app = await _open(tester);
      app.controller.selectCard(_excerptId);
      app.controller.showDetails();
      await tester.pumpAndSettle();
      final copy = _inPanel(find.text('Copy'));
      Focus.of(tester.element(copy)).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_state(app.container).panel, isNull);
    });

    testWidgets('quote: copy, back to the source; tags and review state', (tester) async {
      final app = await _open(tester);
      app.controller.selectCard(_excerptId);
      app.controller.showDetails();
      await tester.pumpAndSettle();

      await tester.tap(_inPanel(find.text('Copy')));
      await tester.pumpAndSettle();
      expect(clipboard, _quote);
      failClipboard = true;
      await tester.tap(_inPanel(find.text('Copy')));
      await tester.pumpAndSettle();
      expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
      await settleHud(tester);

      expect(_inPanel(find.text('Not reviewed yet')), findsOneWidget);
      await tester.tap(_inPanel(find.text('Suspend Card')));
      await tester.pumpAndSettle();
      expect(app.controller.content.card(_excerptId)!.suspended, isTrue);
      expect(_inPanel(find.text('Suspended')), findsOneWidget);
      await tester.tap(_inPanel(find.text('Resume Card')));
      await tester.pumpAndSettle();
      expect(app.controller.content.card(_excerptId)!.suspended, isFalse);

      await app.controller.setTags(_excerptId, ['考试重点']);
      await tester.pumpAndSettle();
      expect(_inPanel(find.text('考试重点')), findsOneWidget);
      await tester.tap(_inPanel(find.byTooltip('Tags…')));
      await tester.pumpAndSettle();
      expect(find.byType(MMSheet), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await tester.tap(_inPanel(find.text('Reveal in Source · Page 24')));
      await tester.pumpAndSettle();
      final state = _state(app.container);
      expect(state.reveal?.documentId, 'c1');
      expect(state.layout, MMSplitMode.split, reason: 'the source comes back to show the excerpt');
      await settleHud(tester);
    });

    testWidgets('review state of a scheduled card; topics have none; a removed card leaves the header', (tester) async {
      final content = demoContent();
      final scheduled = content.copyWith(
        reviews: [
          ReviewState(
            cardId: _excerptId,
            due: DateTime(2026, 10, 29),
            intervalDays: 4,
            ease: 2.5,
            reps: 3,
            lapses: 0,
            lastReviewedAt: testNow,
          ),
        ],
      );
      final app = await _open(tester, content: InMemoryStudySetContentRepository({'demo-1': scheduled}));
      app.controller.selectCard(_excerptId);
      app.controller.showDetails();
      await tester.pumpAndSettle();
      expect(_inPanel(find.text('Next Oct 29 · reviewed 3 times')), findsOneWidget);

      app.controller.selectCard('c3');
      await tester.pumpAndSettle();
      expect(_inPanel(find.text('Review')), findsNothing);
      expect(_inPanel(find.text('Tags')), findsOneWidget);

      await app.controller.removeCards(['c3']);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_inPanel(find.byType(MMInlineTextField)), findsNothing);
      expect(find.byType(CardDetails), findsOneWidget);
      await settleHud(tester);
    });

    testWidgets('a research card without its note keeps a plain header', (tester) async {
      final base = demoContent();
      final content = base.copyWith(
        cards: [
          ...base.cards,
          Card(id: 'r1', kind: CardKind.research, title: '结论', createdAt: testNow),
        ],
        nodes: [
          ...base.nodes,
          const MapNode(cardId: 'r1', order: 99),
        ],
      );
      final app = await _open(tester, content: InMemoryStudySetContentRepository({'demo-1': content}));
      app.controller.showDetails('r1');
      await tester.pumpAndSettle();
      expect(_inPanel(find.text('Research Note')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await settleHud(tester);
    });

    testWidgets('a note’s text is edited with line breaks; an image shows its picture', (tester) async {
      final app = await _open(tester);
      await app.controller.addNote('第一行');
      await tester.pumpAndSettle();
      final note = _state(app.container).selectedCardId!;
      app.controller.showDetails();
      await tester.pumpAndSettle();
      expect(_inPanel(find.text('Note')), findsOneWidget);
      expect(tester.widget<MMInlineTextField>(titleField()).multiline, isTrue);
      await tester.tap(titleField());
      await tester.enterText(titleField(), '第一行\n第二行');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(app.controller.content.card(note)!.title, '第一行\n第二行');

      final image = await app.controller.excerptArea(
        'c1',
        const MMPdfArea(page: 3, rect: PageRect(10, 200, 110, 100), viewportRect: Rect.fromLTWH(0, 0, 100, 100)),
        () async => Uint8List.fromList(_png),
      );
      expect(image, isNot(isA<AreaFailedNotice>()));
      await tester.pumpAndSettle();
      final imageCard = app.controller.content.cards.singleWhere((c) => c.kind == CardKind.image);
      app.controller.selectCard(imageCard.id);
      await tester.pumpAndSettle();
      expect(_inPanel(find.text('Image')), findsOneWidget);
      expect(tester.getSize(_inPanel(find.byKey(const ValueKey('details-image')))).height, greaterThan(0));
      expect(_inPanel(find.byKey(const ValueKey('details-image'))), findsOneWidget);
      expect(_inPanel(find.text('Reveal in Source · Page 3')), findsOneWidget);
      expect(_inPanel(find.text('Copy')), findsNothing);
      await settleHud(tester);
    });
  });

  group('C01 full text on the map', () {
    testWidgets('a cut card expands in place, neighbors make way, and it collapses again', (tester) async {
      final app = await _open(tester, content: _longExcerpt());
      await showWholeMap(tester);
      final id = _longCardId(app.controller);
      final card = find.byKey(ValueKey(id));
      final below = find.byKey(const ValueKey(_excerptId));
      final cut = tester.getRect(card);
      final belowBefore = tester.getRect(below);
      expect(find.text('Show Full Text'), findsOneWidget);
      expect(find.text('Show Full Text', skipOffstage: false), findsOneWidget, reason: 'the short excerpt is whole');

      await _tapCard(tester, find.text('Show Full Text'));
      expect(_state(app.container).expandedCardIds, {id});
      expect(_state(app.container).selectedCardId, id);
      final open = tester.getRect(card);
      expect(open.height, greaterThan(cut.height));
      expect(find.text('Show Less'), findsOneWidget);
      expect((tester.getRect(below).center - belowBefore.center).distance, greaterThan(0), reason: 'neighbors move');
      expect(tester.takeException(), isNull);

      await _tapCard(tester, find.text('Show Less'));
      expect(_state(app.container).expandedCardIds, isEmpty);
      expect(tester.getRect(card).height, cut.height);
      await settleHud(tester);
    });

    testWidgets('⌥Space toggles the selected cards; the view choice is not saved', (tester) async {
      final repo = _longExcerpt();
      final app = await _open(tester, content: repo);
      await showWholeMap(tester);
      final id = _longCardId(app.controller);
      final before = (await repo.load('demo-1')).toJson().toString();
      final card = find.byKey(ValueKey(id));
      await tester.tap(card);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      final cut = tester.getSize(card).height;

      await key(tester, LogicalKeyboardKey.space, alt: true);
      expect(_state(app.container).expandedCardIds, {id});
      expect(tester.getSize(card).height, greaterThan(cut));
      expect(_state(app.container).editingCardId, isNull, reason: '⌥Space never starts editing');

      // Two cards, one open: the first press opens both, the next closes both.
      app.controller.selectCards({id, _excerptId});
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.space, alt: true);
      expect(_state(app.container).expandedCardIds, {id, _excerptId});
      await key(tester, LogicalKeyboardKey.space, alt: true);
      expect(_state(app.container).expandedCardIds, isEmpty);
      expect(tester.getSize(card).height, cut);
      expect((await repo.load('demo-1')).toJson().toString(), before);

      app.controller.selectCard(null);
      app.controller.toggleSelectedExpanded(); // Nothing selected: nothing happens.
      expect(_state(app.container).expandedCardIds, isEmpty);
      await settleHud(tester);
    });

    testWidgets('⌥Space as macOS delivers it (a no-break space) expands instead of editing', (tester) async {
      final app = await _open(tester, content: _longExcerpt());
      await showWholeMap(tester);
      final id = _longCardId(app.controller);
      await _tapCard(tester, find.byKey(ValueKey(id)));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space, platform: 'macos', character: '\u00a0');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space, platform: 'macos');
      await tester.pumpAndSettle();
      expect(_state(app.container).editingCardId, isNull);
      expect(_state(app.container).expandedCardIds, {id});
      await settleHud(tester);
    });

    testWidgets('an expanded card opens its details without moving the map', (tester) async {
      final app = await _open(tester, content: _longExcerpt());
      await showWholeMap(tester);
      final id = _longCardId(app.controller);
      app.controller.toggleExpanded(id);
      app.controller.selectCard(id);
      await tester.pumpAndSettle();
      final view = _mapView(tester).clone();
      await key(tester, LogicalKeyboardKey.keyI, primary: true);
      expect(_state(app.container).panel, RightPanel.details);
      final quote = app.controller.content.annotation(app.controller.content.card(id)!.annotationId!)!.quote;
      expect(_inPanel(find.text(quote)), findsOneWidget, reason: 'the whole quote, not the preview');
      await key(tester, LogicalKeyboardKey.keyI, primary: true);
      expect(_state(app.container).panel, isNull);
      expect(_mapView(tester), view);
      expect(_state(app.container).expandedCardIds, {id});
      await settleHud(tester);
    });
  });
}

/// Taps inside a map node: the node waits for a possible double click.
Future<void> _tapCard(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

Future<void> _press(WidgetTester tester, SingleActivator shortcut) async {
  final held = [
    if (shortcut.control) LogicalKeyboardKey.controlLeft,
    if (shortcut.meta) LogicalKeyboardKey.metaLeft,
    if (shortcut.alt) LogicalKeyboardKey.altLeft,
    if (shortcut.shift) LogicalKeyboardKey.shiftLeft,
  ];
  for (final k in held) {
    await tester.sendKeyDownEvent(k);
  }
  await tester.sendKeyEvent(shortcut.trigger);
  for (final k in held.reversed) {
    await tester.sendKeyUpEvent(k);
  }
  await tester.pumpAndSettle();
}

/// A 1×1 PNG.
const _png = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
  0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
  0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];
