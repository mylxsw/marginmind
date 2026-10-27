/// Renders the assistant panel to PNGs with real fonts (light, dark, narrow
/// window). Skipped unless MM_SCREENSHOTS names an output directory and
/// MM_FONT a CJK font file:
///
///   MM_SCREENSHOTS=docs/evidence/gul-530 MM_FONT=~/.fonts/NotoSansSC.otf \
///     flutter test test/assistant_screenshots_test.dart
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/features/assistant/assistant_controller.dart';
import 'package:marginmind/features/assistant/assistant_scope.dart';
import 'package:mm_core/mm_core.dart';
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

MemoryConversationArchive _seed(String topic) {
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
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
  final image = (await tester.runAsync(() => boundary.toImage(pixelRatio: 2)))!;
  final png = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png)))!;
  await tester.runAsync(() => File('$_out/$name.png').writeAsBytes(png.buffer.asUint8List()));
  expect(find.byType(MarginMindApp), findsOneWidget);
}

void main() {
  final skip = _out == null || _font == null;
  setUpAll(() async {
    if (skip) return;
    Directory(_out!).createSync(recursive: true);
    await _loadFonts();
  });
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);
  testWidgets('light', (tester) => _shoot(tester, 'assistant-light'), skip: skip, variant: mac);
  testWidgets('dark', (tester) => _shoot(tester, 'assistant-dark', dark: true), skip: skip, variant: mac);
  testWidgets(
    'narrow',
    (tester) => _shoot(tester, 'assistant-narrow', size: const Size(1000, 760)),
    skip: skip,
    variant: mac,
  );
}
