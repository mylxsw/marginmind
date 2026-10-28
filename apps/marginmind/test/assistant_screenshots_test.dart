/// Renders the assistant panel (light, dark, narrow window) and the
/// settings dialog to PNGs with real fonts. Skipped unless MM_SCREENSHOTS names an output directory and
/// MM_FONT a CJK font file:
///
///   MM_SCREENSHOTS=docs/evidence/gul-530 MM_FONT=~/.fonts/NotoSansSC.otf \
///     flutter test test/assistant_screenshots_test.dart
library;

import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/assistant/assistant_services.dart';
import 'package:marginmind/features/assistant/widgets/assistant_panel.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/features/assistant/assistant_controller.dart';
import 'package:marginmind/features/assistant/assistant_scope.dart';
import 'package:marginmind/features/assistant/widgets/assistant_composer.dart';
import 'package:marginmind/settings/settings_window.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_assistant/mm_assistant.dart' show AssistantServices;
import 'package:mm_design/mm_design.dart';
import 'package:mm_pdf/mm_pdf.dart';

import 'assistant_support.dart';
import 'helpers.dart';

final _out = Platform.environment['MM_SCREENSHOTS'];
final _font = Platform.environment['MM_FONT'];
const _claim = '这条先陡后平的曲线，被称为遗忘曲线。';

Future<void> _loadFonts() async {
  final bytes = ByteData.sublistView(await File(_font!).readAsBytes());
  for (final family in [
    '.AppleSystemUIFont',
    'CupertinoSystemText',
    'CupertinoSystemDisplay',
    'Roboto',
    'Songti SC',
    'SF Mono',
  ]) {
    await (FontLoader(family)..addFont(Future.value(bytes))).load();
  }
  final pub = Platform.environment['PUB_CACHE'] ?? '${Platform.environment['HOME']}/.pub-cache';
  final icons = Directory('$pub/hosted/pub.dev')
      .listSync()
      .whereType<Directory>()
      .lastWhere((d) => d.path.contains('cupertino_icons-'));
  await (FontLoader(
        'packages/cupertino_icons/CupertinoIcons',
      )..addFont(Future.value(ByteData.sublistView(File('${icons.path}/assets/CupertinoIcons.ttf').readAsBytesSync()))))
      .load();
}

MemoryConversationArchive _seed(String topic, {bool quiet = false}) {
  final archive = MemoryConversationArchive();
  final state = sdk.AgentState(sessionId: 'shot-1');
  final selection = selectionContext(documentId: 'c1', page: 24, quote: _claim);
  state.metadata['assistant.view'] = Conversation(
    id: 'shot-1',
    studySetId: 'demo-1',
    title: '解释：遗忘曲线',
    model: const AssistantModel(
      provider: AssistantProvider.claude,
      model: 'claude-opus-5-5',
      endpoint: 'https://api.anthropic.com/v1/messages',
    ),
    messages: [
      Message(
        id: '1761600000000000-1',
        requestId: 'r1',
        role: MessageRole.user,
        text: '解释一下这段话',
        contexts: [selection],
        skill: 'explain',
      ),
      Message(
        id: '1761600000000000-2',
        requestId: 'r1',
        role: MessageRole.agent,
        text: '## 要点\n遗忘曲线描述的是**刚学完时忘得最快**，之后逐渐变慢 [page:24]。\n- 学完一天内遗忘最多\n- 间隔复习能把曲线拉平\n\n所以复习要趁早，间隔逐步拉长。',
        traces: const [
          TraceStep('t1', 'read_selection', TraceStatus.done),
          TraceStep('t2', 'read_pages', TraceStatus.done),
        ],
        citations: const [Citation(marker: '[page:24]', documentId: 'c1', page: 24, quote: _claim)],
      ),
      Message(id: '1761600000000000-3', requestId: 'r2', role: MessageRole.user, text: '把这一节整理进脑图', skill: 'organize'),
      Message(
        id: '1761600000000000-4',
        requestId: 'r2',
        role: MessageRole.agent,
        text: '',
        traces: const [
          TraceStep('t3', 'read_branch', TraceStatus.done),
          TraceStep('t4', 'propose_map_edits', TraceStatus.done),
        ],
        proposals: [
          ProposalView(
            proposal: MapEditProposal(
              id: 'p1',
              studySetId: 'demo-1',
              mapId: 'main',
              baseRevision: 0,
              operations: [
                MapEditOperation(id: 'a', kind: MapEditKind.addTopic, parentId: topic, title: '遗忘的速度先快后慢'),
                const MapEditOperation(
                  id: 'b',
                  kind: MapEditKind.addReviewCard,
                  parentId: 'new:a',
                  question: '学完后哪段时间遗忘最快？',
                  answer: '学完后的第一天',
                ),
                MapEditOperation(id: 'c', kind: MapEditKind.rename, nodeId: topic, title: '遗忘曲线'),
              ],
            ),
          ),
        ],
      ),
    ],
  ).toJson();
  if (quiet) {
    final view = state.metadata['assistant.view'] as Map<String, dynamic>;
    view['title'] = '';
    final messages = (view['messages'] as List).take(2).toList();
    (messages.first as Map<String, dynamic>)['contexts'] = [
      pageContext(document: demoContent().document('c1')!, page: 24, auto: true).toJson(),
    ];
    view['messages'] = messages;
  }
  archive.save(state);
  return archive;
}

Future<void> _shoot(WidgetTester tester, String name, {Size size = const Size(1440, 900), bool dark = false}) async {
  final topic = demoContent().cards.firstWhere((c) => c.title == '遗忘的规律').id;
  final app = await openAssistantApp(
    tester,
    archive: _seed(topic),
    size: size,
    prefs: {if (dark) 'settings.appearance': 'dark'},
  );
  await tester.tap(
    find.byKey(const ValueKey('sidebar-conversation-shot-1')).hitTestable().evaluate().isEmpty
        ? find.byKey(const ValueKey('toolbar-assistant'))
        : find.byKey(const ValueKey('sidebar-conversation-shot-1')),
  );
  await pumpFor(tester, 20);
  if (conversationOf(tester).id != 'shot-1') {
    await assistantOf(tester).openConversation('shot-1');
    await pumpFor(tester, 10);
  }
  await app.workspace.onSelectionCommitted(
    'c1',
    MMPdfSelection(
      page: 24,
      rects: const [PageRect(10, 100, 200, 88)],
      text: _claim,
      viewportRect: const Rect.fromLTWH(100, 200, 200, 20),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('selection-assistant')));
  await pumpFor(tester, 10);
  await _save(tester, name);
  await _save(tester, '$name-composer', bounds: tester.getRect(find.byType(AssistantComposer)));
  await tester.tap(find.byKey(const ValueKey('assistant-context-summary')));
  await tester.pumpAndSettle();
  await _save(tester, '$name-references');
  await tester.tap(find.byKey(const ValueKey('assistant-context-summary')));
  await tester.enterText(find.byKey(const ValueKey('assistant-input')), '这段话和前面的观点有什么关系？');
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('quick-more')), findsOneWidget);
  await _save(tester, '$name-typing');
  await tester.enterText(find.byKey(const ValueKey('assistant-input')), '');
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('quick-more')));
  await tester.pumpAndSettle();
  await _save(tester, '$name-more', overlays: true);
  expect(find.byType(MarginMindApp), findsOneWidget);
}

/// Saves the app, or with [overlays] the whole view including dialogs.
Future<void> _save(WidgetTester tester, String name, {bool overlays = false, Rect? bounds}) async {
  final image = overlays || bounds != null
      ? (await tester.runAsync(() {
          final view = tester.binding.renderViews.first;
          return (view.debugLayer! as OffsetLayer).toImage(bounds ?? Offset.zero & view.size, pixelRatio: 2);
        }))!
      : (await tester.runAsync(
          () => tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first).toImage(pixelRatio: 2),
        ))!;
  final png = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png)))!;
  await tester.runAsync(() => File('$_out/$name.png').writeAsBytes(png.buffer.asUint8List()));
}

Future<void> _shootSettings(
  WidgetTester tester,
  String name,
  SettingsTab tab, {
  bool dark = false,
  bool providers = false,
}) async {
  await openAssistantApp(tester, size: const Size(1440, 900), prefs: {if (dark) 'settings.appearance': 'dark'});
  showSettings(tester.element(find.byType(MMWindowScaffold)), tab: tab, showsGallery: false);
  await pumpFor(tester, 20);
  if (providers) {
    await tester.tap(find.byKey(const ValueKey('settings-add-service')));
    await tester.pumpAndSettle();
  }
  await _save(tester, name, overlays: true);
  expect(find.byType(SettingsWindow), findsOneWidget);
}

Future<void> _quiet(WidgetTester tester, String state, {bool dark = false, Size size = const Size(1440, 720)}) async {
  final topic = demoContent().cards.firstWhere((c) => c.title == '遗忘的规律').id;
  final populated = state == 'answer' || state == 'recovery';
  final app = await openAssistantApp(
    tester,
    key: state != 'setup',
    size: size,
    archive: populated ? _seed(topic, quiet: true) : null,
    prefs: {
      if (dark) 'settings.appearance': 'dark',
      if (state == 'setup') AssistantServicesStore.settingsKey: jsonEncode(AssistantServices().toJson()),
    },
    overrides: [
      if (state == 'recovery')
        assistantCredentialStateProvider.overrideWith((ref) async => AssistantCredentialState.unavailable),
    ],
  );
  app.workspace.recordPage('c1', 24);
  await tester.tap(find.byKey(const ValueKey('toolbar-assistant')));
  await pumpFor(tester, 10);
  if (populated) {
    final scope = ProviderScope.containerOf(tester.element(find.byType(AssistantPanel)));
    await scope.read(assistantControllerProvider.notifier).openConversation('shot-1');
    await pumpFor(tester, 10);
    FocusManager.instance.primaryFocus?.unfocus();
  }
  await tester.pumpAndSettle();
  final name = 'quiet-$state${dark ? '-dark' : ''}${size.width < 1440 ? '-narrow' : ''}';
  await _save(tester, name);
  await _save(tester, '$name-panel', bounds: tester.getRect(find.byType(AssistantPanel)));
  expect(tester.takeException(), isNull);
  if (state == 'setup' || state == 'recovery') expect(find.byKey(const ValueKey('assistant-input')), findsNothing);
  if (state == 'recovery') expect(find.byKey(const ValueKey('assistant-messages')), findsOneWidget);
  // Keep the owning container alive until capture completes.
  expect(app.workspace.content.documents, isNotEmpty);
}

void main() {
  final skip = _out == null || _font == null;
  setUpAll(() async {
    if (skip) return;
    Directory(_out!).createSync(recursive: true);
    await _loadFonts();
  });
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);
  for (final state in ['setup', 'empty', 'answer', 'recovery']) {
    testWidgets('quiet $state', (tester) => _quiet(tester, state), skip: skip, variant: mac);
  }
  testWidgets('quiet dark', (tester) => _quiet(tester, 'answer', dark: true), skip: skip, variant: mac);
  testWidgets(
    'quiet narrow',
    (tester) => _quiet(tester, 'answer', size: const Size(1000, 760)),
    skip: skip,
    variant: mac,
  );
  testWidgets('light', (tester) => _shoot(tester, 'assistant-light'), skip: skip, variant: mac);
  testWidgets('dark', (tester) => _shoot(tester, 'assistant-dark', dark: true), skip: skip, variant: mac);
  testWidgets(
    'narrow',
    (tester) => _shoot(tester, 'assistant-narrow', size: const Size(1000, 760)),
    skip: skip,
    variant: mac,
  );
  for (final dark in [false, true]) {
    testWidgets(
      'settings providers ${dark ? 'dark' : 'light'}',
      (tester) => _shootSettings(
        tester,
        'settings-providers-${dark ? 'dark' : 'light'}',
        SettingsTab.models,
        dark: dark,
        providers: true,
      ),
      skip: skip,
      variant: mac,
    );
  }
  for (final (tab, dark) in [
    (SettingsTab.general, false),
    (SettingsTab.models, false),
    (SettingsTab.webSearch, true),
  ]) {
    testWidgets(
      'settings ${tab.name}${dark ? ' dark' : ''}',
      (tester) => _shootSettings(tester, 'settings-${tab.name}${dark ? '-dark' : ''}', tab, dark: dark),
      skip: skip,
      variant: mac,
    );
  }
}
