import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:mm_core/mm_core.dart';

import 'citations.dart';
import 'hooks.dart';

class AssistantTools {
  AssistantTools({
    required this.reader,
    required this.scope,
    required this.cancel,
    required this.citations,
    required this.budget,
    this.network,
  });
  final StudySetReader reader;
  final ReadScope scope;
  final CancellationToken cancel;
  final CitationRegistry citations;
  final RunBudget budget;
  final AssistantNetwork? network;
  static const readNames = {'read_selection', 'read_pages', 'search_study_set', 'read_branch'};
  String str(Map<String, dynamic> a, String k, {int max = 200}) {
    final v = a[k];
    if (v is! String || v.trim().isEmpty || v.length > max) throw const FormatException('Invalid argument');
    return v;
  }

  Future<Object> execute(String name, Map<String, dynamic> a) async {
    cancel.check();
    Object out;
    switch (name) {
      case 'read_selection':
        final id = str(a, 'selectionId');
        if (!scope.selections.contains(id)) throw const FormatException('Selection not authorized');
        final pages = await cancel.bind(reader.readSelection(id, scope, cancel));
        budget.pages += pages.length;
        if (budget.pages > budget.limits.pages) throw const ResearchFailure(ResearchFailureKind.budget);
        out = _pages(pages, selection: true);
      case 'read_pages':
        final doc = str(a, 'documentId');
        final from = a['from'] as int, to = a['to'] as int;
        if (from < 1 ||
            to < from ||
            to - from >= budget.limits.pages ||
            [for (var p = from; p <= to; p++) p].any((p) => !scope.allowsPage(doc, p))) {
          throw const FormatException('Pages not authorized');
        }
        final pages = await cancel.bind(reader.readPages(doc, from, to, scope, cancel));
        if (pages.length > to - from + 1 || pages.any((p) => p.documentId != doc || p.page < from || p.page > to)) {
          throw const FormatException('Invalid reader result');
        }
        out = _pages(pages);
      case 'search_study_set':
        final query = str(a, 'query');
        final limit = a['limit'] as int? ?? 10;
        if (limit < 1 || limit > 20) throw const FormatException('Invalid limit');
        out = [
          for (final h in (await cancel.bind(reader.searchStudySet(query, limit, scope, cancel))).take(limit))
            h.toJson(),
        ];
      case 'read_branch':
        final map = str(a, 'mapId'), node = str(a, 'nodeId');
        if (!scope.allowsBranch(map, node)) throw const FormatException('Branch not authorized');
        final nodes = await cancel.bind(reader.readBranch(map, node, scope, cancel));
        if (nodes.length > 200) throw const ResearchFailure(ResearchFailureKind.budget);
        out = [for (final n in nodes) n.toJson()];
      case 'web_search':
        out = [for (final r in await cancel.bind(_network.search(str(a, 'query'), cancel))) r.toJson()];
      case 'search_papers':
        out = [for (final s in await cancel.bind(_network.papers(str(a, 'query'), cancel))) _source(s)];
      case 'fetch_source':
        out = _source(await cancel.bind(_network.fetch(Uri.parse(str(a, 'url', max: 2048)), cancel)));
      default:
        throw const FormatException('Unknown tool');
    }
    cancel.check();
    return out;
  }

  AssistantNetwork get _network {
    if (!citations.online || network == null) throw const ResearchFailure(ResearchFailureKind.unavailable);
    return network!;
  }

  Object _pages(List<ReadPage> pages, {bool selection = false}) {
    if (pages.any((p) => p.page < 1 || (!selection && !scope.allowsPage(p.documentId, p.page)))) {
      throw const FormatException('Invalid page');
    }
    return [
      for (final p in pages) {...p.toJson(), 'citation': citations.page(p)},
    ];
  }

  Object _source(AssistantSource s) => {
    'title': s.title,
    'kind': s.kind,
    'url': s.url.toString(),
    'paragraphs': s.paragraphs,
    'citations': citations.source(s),
  };
  List<Tool> build() => [
    _tool('read_selection', {'selectionId': 'string'}),
    _tool('read_pages', {'documentId': 'string', 'from': 'integer', 'to': 'integer'}),
    _tool('search_study_set', {'query': 'string'}),
    _tool('read_branch', {'mapId': 'string', 'nodeId': 'string'}),
    if (citations.online) ...[
      _tool('web_search', {'query': 'string'}),
      _tool('search_papers', {'query': 'string'}),
      _tool('fetch_source', {'url': 'string'}),
    ],
    Tool(
      name: 'propose_map_edits',
      description: 'Submit edits for user confirmation. Never executes writes.',
      parameters: {
        'type': 'object',
        'properties': {
          'ops': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'id': {'type': 'string'},
                'kind': {'type': 'string', 'enum': MapEditKind.values.map((k) => k.name).toList()},
                for (final key in ['nodeId', 'parentId', 'title', 'body', 'question', 'answer'])
                  key: {'type': 'string'},
              },
              'required': ['id', 'kind'],
              'additionalProperties': false,
            },
          },
        },
        'required': ['ops'],
        'additionalProperties': false,
      },
      parameterMode: ToolParameterMode.object,
      executable: (_) => throw StateError('Writes require confirmation'),
    ),
  ];
  Tool _tool(String name, Map<String, String> fields) => Tool(
    name: name,
    description: name,
    parameters: {
      'type': 'object',
      'properties': fields.map((k, v) => MapEntry(k, {'type': v})),
      'required': fields.keys.toList(),
      'additionalProperties': false,
    },
    parameterMode: ToolParameterMode.object,
    executable: (Map<String, dynamic> a) async {
      try {
        return await execute(name, a);
      } on ResearchFailure catch (e) {
        return AgentToolResult(content: TextPart(e.kind.name), metadata: {'failure': e.kind.name});
      } catch (_) {
        return AgentToolResult(
          content: TextPart('Invalid or unauthorized request'),
          metadata: {'failure': 'invalidRequest'},
        );
      }
    },
    resultIsError: (r) => r is AgentToolResult && r.metadata?['failure'] != null,
  );
}

class AssistantSkill extends Skill {
  AssistantSkill(String name, String prompt, List<Tool> tools)
    : super(name: name, description: prompt, systemPrompt: '$prompt\n$assistantAnswerStyle', tools: tools);
}

const assistantAnswerStyle =
    '先一句加粗结论，再用小标题或列表组织 2–3 个要点；对比用表格，引用原文用 >。'
    '解释或是谁类默认约 150 字以内。引用 [page:N] / [source:N] 只放句末标点前，不把 p.N 当名词。'
    '联网时涉及书外事实必须先 web_search 再 fetch_source；不联网时不补充书外事实，只说明未联网核对。'
    '结尾不反问“需要我……吗”。说明和正文都使用用户提问的语言，不输出英文元话语。';

const skillPrompts = {
  'explain': '解释：先读选区或相关页面，区分原文和你的解释。',
  'translate': '翻译：忠实保留语义与术语，不编造出处。',
  'verify': '查证：对照真实读取的来源，没有联网证据时明确未核对。',
  'summarize': '总结：摘要只覆盖实际读取的范围。',
  'quiz': '出题：基于原文生成复习卡提议，不能直接写入。',
  'organize': '整理：先读取分支，保留用户内容，通过提议修改脑图。',
  'papers': '找论文：使用 OpenAlex 元数据，元数据不等于论文全文。',
  'videos': '找视频：只给具体视频链接，没有字幕不能声称看过视频。',
};
List<Skill> assistantSkills(List<Tool> tools) => [
  for (final e in skillPrompts.entries)
    AssistantSkill(
      e.key,
      e.value,
      tools
          .where(
            (t) => switch (e.key) {
              'quiz' || 'organize' => AssistantTools.readNames.contains(t.name) || t.name == 'propose_map_edits',
              'verify' || 'papers' || 'videos' => t.name != 'propose_map_edits',
              _ => AssistantTools.readNames.contains(t.name),
            },
          )
          .toList(),
    ),
];
