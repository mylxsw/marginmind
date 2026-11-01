import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:mm_core/mm_core.dart';

import 'citations.dart';
import 'hooks.dart';
import 'permissions.dart';

const mapEditProposalInstructions = '''Submit edits for user confirmation. Never executes writes.
Each operation has a unique id and ONLY the fields listed for its kind:
addTopic: id, kind, parentId, title (no body; use addNote for details).
addNote: id, kind, parentId, title, body.
addReviewCard: id, kind, parentId, question, answer.
move: id, kind, nodeId, parentId. rename: id, kind, nodeId, title.
Use existing node IDs from the supplied graph. To reference a node added earlier
in the SAME ops array, use new:<opId>, never the bare operation ID.
Example: {"ops":[{"id":"topic1","kind":"addTopic","parentId":"<existing-node-id>","title":"Topic"},
{"id":"note1","kind":"addNote","parentId":"new:topic1","title":"Details","body":"Content"}]}''';

class AssistantTools {
  AssistantTools({
    required this.reader,
    required this.scope,
    required this.cancel,
    required this.citations,
    required this.budget,
    this.network,
    this.permissions,
  });
  final StudySetReader reader;
  ReadScope scope;
  final CancellationToken cancel;
  final CitationRegistry citations;
  final RunBudget budget;
  final AssistantNetwork? network;
  final AssistantPermissions? permissions;
  // Pagination bounds work per tool call, not the total pages a run may read.
  static const pageBatchSize = 20;
  static const readNames = {
    'read_selection',
    'read_pages',
    'search_study_set',
    'read_branch',
    'read_more',
    'read_history',
  };
  String str(Map<String, dynamic> a, String k, {int max = 200}) {
    final v = a[k];
    if (v is! String || v.trim().isEmpty || v.length > max) throw const FormatException('Invalid argument');
    return v;
  }

  final _continuations = <String, Object Function()>{};
  int _cursor = 0;
  String _continue(Object Function() read) {
    final cursor = 'read-${++_cursor}';
    _continuations[cursor] = read;
    return cursor;
  }

  Object _bounded(Object value) {
    final encoded = jsonEncode(value);
    final available = (budget.remainingReadCharacters - 1024).clamp(0, 12000);
    if (jsonEncode(encoded).length <= available) {
      budget.takeContextSpace(jsonEncode(encoded).length + 512);
      return value;
    }
    Object fragment(int start) {
      final remaining = (budget.remainingReadCharacters - 1024).clamp(0, 12000);
      var end = start;
      // Encoded text fragments retain every character and can be requested in
      // order. The cursor is scoped to this tool instance and permissions.
      var low = start, high = encoded.length;
      while (low < high) {
        final mid = (low + high + 1) ~/ 2;
        if (jsonEncode(encoded.substring(start, mid)).length <= remaining) {
          low = mid;
        } else {
          high = mid - 1;
        }
      }
      end = low;
      if (end > start &&
          end < encoded.length &&
          encoded.codeUnitAt(end - 1) >= 0xd800 &&
          encoded.codeUnitAt(end - 1) <= 0xdbff) {
        end--;
      }
      if (end == start) budget.contextFull = true;
      final next = end;
      final out = <String, Object?>{
        'dataFragment': encoded.substring(start, end),
        'offset': start,
        'complete': end == encoded.length,
        if (end < encoded.length) 'nextCursor': _continue(() => fragment(next)),
        'notice': 'Fragment of JSON data; omitted content has not been read.',
      };
      budget.takeContextSpace(jsonEncode(jsonEncode(out)).length);
      return out;
    }

    return fragment(0);
  }

  Future<Object> execute(String name, Map<String, dynamic> a) async {
    cancel.check();
    Object out;
    switch (name) {
      case 'read_more':
        final next = _continuations[str(a, 'cursor')];
        if (next == null) throw const FormatException('Invalid continuation');
        return next();
      case 'read_selection':
        final id = str(a, 'selectionId');
        if (!scope.selections.contains(id)) await _authorize(name, a);
        final pages = await cancel.bind(reader.readSelection(id, scope, cancel));
        out = _pages(pages, selection: true);
      case 'read_pages':
        final doc = str(a, 'documentId');
        final from = a['from'] as int, to = a['to'] as int;
        if (from < 1 || to < from) {
          throw const FormatException('Invalid page range');
        }
        out = await _readPages(doc, from, to);
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
        if (!scope.allowsBranch(map, node)) await _authorize(name, a);
        final nodes = await cancel.bind(reader.readBranch(map, node, scope, cancel));
        out = [for (final n in nodes) n.toJson()];
      case 'web_search':
        out = [for (final r in await cancel.bind(_network.search(str(a, 'query'), cancel))) r.toJson()];
      case 'search_papers':
        out = _sources(await cancel.bind(_network.papers(str(a, 'query'), cancel)));
      case 'fetch_source':
        out = _source(await cancel.bind(_network.fetch(Uri.parse(str(a, 'url', max: 2048)), cancel)));
      default:
        throw const FormatException('Unknown tool');
    }
    cancel.check();
    return {'read_selection', 'read_pages', 'fetch_source', 'search_papers'}.contains(name) ? out : _bounded(out);
  }

  Future<void> _authorize(String name, Map<String, dynamic> arguments) async {
    final request = switch (reader) {
      ReadPermissionResolver resolver => resolver.describeReadPermission(name, arguments),
      _ => null,
    };
    if (request == null || permissions == null) throw const FormatException('Invalid or unavailable read target');
    if (!await permissions!.request(request)) throw const ReadPermissionDenied();
    cancel.check();
    scope = request.grant(scope);
  }

  AssistantNetwork get _network {
    if (!citations.online || network == null) throw const ResearchFailure(ResearchFailureKind.unavailable);
    return network!;
  }

  Map<String, Object?> _readResult(
    List<Map<String, Object?>> pages, {
    bool complete = true,
    int? nextPage,
    bool capacityReached = false,
  }) => {
    'pages': pages,
    'complete': complete,
    'nextPage': ?nextPage,
    if (!complete)
      'notice': capacityReached
          ? '上下文容量接近上限，仅返回实际容纳的内容。未返回的文字和页面尚未读取；请据此回答，必要时明确说明资料不完整。'
          : '本次仅返回一批页面，可从 nextPage 继续读取；后续页面尚未读取。',
  };

  bool _beginRead() {
    // Reserve the result wrapper and SDK tool-message metadata separately.
    if (budget.takeContextSpace(512)) return true;
    budget.contextFull = true;
    return false;
  }

  Future<Object> _readPages(String doc, int from, int to) async {
    final end = to - from < pageBatchSize ? to : from + pageBatchSize - 1;
    final arguments = {'documentId': doc, 'from': from, 'to': end};
    if ([for (var p = from; p <= end; p++) p].any((p) => !scope.allowsPage(doc, p))) {
      await _authorize('read_pages', arguments);
    }
    final out = <Map<String, Object?>>[];
    if (!_beginRead()) return _readResult(out, complete: false, capacityReached: true);
    for (var page = from; page <= end; page++) {
      cancel.check();
      if (!scope.allowsPage(doc, page)) throw const FormatException('Unauthorized page');
      final read = await cancel.bind(reader.readPages(doc, page, page, scope, cancel));
      if (read.length > 1 || read.any((p) => p.documentId != doc || p.page != page)) {
        throw const FormatException('Invalid reader result');
      }
      if (read.isEmpty) continue;
      final row = _fitPage(read.single);
      if (row != null) {
        out.add(row);
        budget.pages++;
      }
      if (row == null || row['textComplete'] == false) {
        budget.contextFull = true;
        return _readResult(out, complete: false, capacityReached: true);
      }
    }
    return _readResult(out, complete: end == to, nextPage: end < to ? end + 1 : null);
  }

  Object _pages(List<ReadPage> pages, {bool selection = false}) {
    if (pages.any((p) => p.page < 1 || (!selection && !scope.allowsPage(p.documentId, p.page)))) {
      throw const FormatException('Invalid page');
    }
    final out = <Map<String, Object?>>[];
    if (!_beginRead()) return _readResult(out, complete: false, capacityReached: true);
    for (final p in pages) {
      final row = _fitPage(p);
      if (row != null) out.add(row);
      if (row == null || row['textComplete'] == false) {
        budget.contextFull = true;
        return _readResult(out, complete: false, capacityReached: true);
      }
    }
    return _readResult(out);
  }

  Map<String, Object?>? _fitPage(ReadPage page) {
    Map<String, Object?> candidate(int length) => {
      'documentId': page.documentId,
      'page': page.page,
      'text': page.text.substring(0, length),
      'textComplete': length == page.text.length,
      // A conservative marker length; register evidence only after admission.
      'citation': '[source:9999999999999999999]',
    };
    // Tool JSON is embedded in a text part, so account for both JSON layers
    // (including quotes, slashes and newlines), not just raw text length.
    int size(Map<String, Object?> row) => jsonEncode(jsonEncode(row)).length;
    var length = page.text.length;
    if (size(candidate(length)) > budget.remainingReadCharacters) {
      var low = 0;
      var high = length < budget.remainingReadCharacters ? length : budget.remainingReadCharacters;
      while (low < high) {
        final mid = (low + high + 1) ~/ 2;
        if (size(candidate(mid)) <= budget.remainingReadCharacters) {
          low = mid;
        } else {
          high = mid - 1;
        }
      }
      length = low;
      if (length == 0) return null;
      // Never split a UTF-16 surrogate pair, such as an emoji.
      final last = page.text.codeUnitAt(length - 1);
      if (last >= 0xd800 && last <= 0xdbff) length--;
      if (length == 0) return null;
    }
    final row = candidate(length);
    if (!budget.takeContextSpace(size(row))) return null;
    row['citation'] = citations.page(ReadPage(page.documentId, page.page, row['text'] as String));
    if (length < page.text.length) {
      final remainder = page.text.substring(length);
      row['nextCursor'] = _continue(() => _pages([ReadPage(page.documentId, page.page, remainder)], selection: true));
    }
    return row;
  }

  Object _sources(List<AssistantSource> sources, [int index = 0]) {
    if (index >= sources.length) return {'complete': true};
    return {
      'source': _source(sources[index]),
      'complete': index + 1 == sources.length,
      if (index + 1 < sources.length) 'nextCursor': _continue(() => _sources(sources, index + 1)),
    };
  }

  Object _source(AssistantSource source, {int paragraphIndex = 0, int offset = 0}) {
    final entries = source.paragraphs.entries.toList();
    if (paragraphIndex >= entries.length) return {'complete': true, 'paragraphs': <String, String>{}};
    final p = entries[paragraphIndex];
    final length = (budget.remainingReadCharacters - 2048).clamp(0, 8000) ~/ 4;
    var end = (offset + length).clamp(0, p.value.length);
    if (end > offset &&
        end < p.value.length &&
        p.value.codeUnitAt(end - 1) >= 0xd800 &&
        p.value.codeUnitAt(end - 1) <= 0xdbff) {
      end--;
    }
    final text = p.value.substring(offset, end);
    final nextParagraph = end == p.value.length ? paragraphIndex + 1 : paragraphIndex;
    final nextOffset = end == p.value.length ? 0 : end;
    final complete = nextParagraph == entries.length;
    final admitted = AssistantSource(
      id: source.id,
      version: source.version,
      kind: source.kind,
      title: source.title,
      url: source.url,
      paragraphs: {p.key: text},
      fetchedAt: source.fetchedAt,
      snapshotFile: source.snapshotFile,
    );
    final out = {
      'title': source.title.substring(0, source.title.length.clamp(0, 200)),
      'kind': source.kind,
      'paragraphs': {p.key: text},
      'offset': offset,
      'citations': text.isEmpty ? <String>[] : citations.source(admitted),
      'complete': complete,
      if (!complete) 'nextCursor': _continue(() => _source(source, paragraphIndex: nextParagraph, offset: nextOffset)),
    };
    if (text.isEmpty) budget.contextFull = true;
    budget.takeContextSpace(jsonEncode(jsonEncode(out)).length + 256);
    return out;
  }

  List<Tool> build() => [
    _tool('read_more', {'cursor': 'string'}),
    _tool('read_selection', {'selectionId': 'string'}),
    _tool('read_pages', {'documentId': 'string', 'from': 'integer', 'to': 'integer'}),
    _tool('search_study_set', {'query': 'string'}),
    if (scope.maps.isNotEmpty ||
        scope.branches.values.any((nodes) => nodes.isNotEmpty) ||
        (permissions != null && reader is ReadPermissionResolver))
      _tool('read_branch', {'mapId': 'string', 'nodeId': 'string'}),
    if (citations.online) ...[
      _tool('web_search', {'query': 'string'}),
      _tool('search_papers', {'query': 'string'}),
      _tool('fetch_source', {'url': 'string'}),
    ],
    Tool(
      name: 'propose_map_edits',
      description: mapEditProposalInstructions,
      parameters: {
        'type': 'object',
        'properties': {
          'ops': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'id': {'type': 'string'},
                'kind': {
                  'type': 'string',
                  'enum': [
                    MapEditKind.addTopic,
                    MapEditKind.addNote,
                    MapEditKind.addReviewCard,
                    MapEditKind.move,
                    MapEditKind.rename,
                  ].map((k) => k.name).toList(),
                },
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
    description: switch (name) {
      'read_pages' =>
        'Read document pages using documentId and inclusive 1-based from/to. There is no total page quota. Returns {pages, complete, nextPage?, notice?}, at most $pageBatchSize pages per batch within available context space. If complete=false, follow notice/nextPage; textComplete=false means only a prefix of that page was read. Never treat omitted content as read. If extra read permission is needed, the tool waits for the user to allow or deny it.',
      'read_selection' => 'Read selected text using selectionId. Returns {pages, complete, notice?}; textComplete=false means only a prefix fits. Selected text does not consume a page quota.',
      'read_branch' => 'Read a mind-map branch using mapId and nodeId (__root__ for the map root). The tool asks the user before reading an additional branch.',
      'read_more' => 'Continue an earlier bounded result using its nextCursor. Only returned content is read.',
      'web_search' => 'Discover URLs using short keywords; search snippets are not evidence. Fetch a source before citing it. Follow nextCursor with read_more for omitted results.',
      'search_papers' =>
        'Discover scholarly metadata. Metadata is not full paper text. Follow nextCursor with read_more.',
      'fetch_source' => 'Fetch an immutable source snapshot as evidence. Returns bounded paragraphs and citations; follow nextCursor with read_more. Omitted text has not been read.',
      _ => name,
    },
    parameters: {
      'type': 'object',
      'properties': fields.map((k, v) => MapEntry(k, {'type': v})),
      'required': fields.keys.toList(),
      'additionalProperties': false,
    },
    parameterMode: ToolParameterMode.object,
    executable: (Map<String, dynamic> a) async {
      try {
        // The SDK otherwise calls Map.toString(), which is not JSON and
        // obscures page completeness and continuation fields from the model.
        return AgentToolResult(content: TextPart(jsonEncode(await execute(name, a))));
      } on ReadPermissionRequired {
        return AgentToolResult(
          content: TextPart(
            'Read permission is required, but no user decision handler is available. Use already available content.',
          ),
          metadata: {'failure': 'permissionRequired', 'reason': '读取此内容需要用户授权'},
        );
      } on ReadPermissionDenied {
        return AgentToolResult(
          content: TextPart(
            'User declined permission. Continue with already available content; do not repeat this request.',
          ),
          metadata: {'failure': 'permissionDenied', 'reason': '用户未允许读取此内容'},
        );
      } on ResearchFailure catch (e) {
        return AgentToolResult(content: TextPart(e.kind.name), metadata: {'failure': e.kind.name});
      } catch (_) {
        return AgentToolResult(
          content: TextPart(
            'Invalid arguments or unavailable target. Check the supplied resource IDs and page ranges.',
          ),
          metadata: {'failure': 'invalidRequest', 'reason': '工具参数无效或读取目标不存在'},
        );
      }
    },
    resultIsError: (r) => r is AgentToolResult && r.metadata?['failure'] != null,
  );
}

class AssistantSkill extends Skill {
  AssistantSkill(String name, String prompt, List<Tool> tools)
    : super(
        name: name,
        description: prompt,
        systemPrompt: '$prompt\n${name == 'translate' ? '只输出完整译文，保留原文结构，不加结论或总结。' : assistantAnswerStyle}',
        tools: tools,
      );
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
  'organize':
      '整理：先读取原文。需要读取额外脑图分支时可调用 read_branch 请求用户授权；拒绝后使用已读内容及当前可编辑脑图的节点父子关系生成提议。保留用户内容，通过 propose_map_edits 提议修改脑图。',
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
