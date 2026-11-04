import 'dart:async';
import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart' as sdk;
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

import 'runtime_ports_test.dart' as ports;
import 'support.dart';

void main() {
  group('WebFormatUrls', () {
    test('tokenizes Markdown and HTML destinations and restores them', () {
      final urls = WebFormatUrls();
      final protected = urls.protect(
        '[a](<https://a.example/x_(1)>) ![](<resources/image-1.png>) [b](https://b.example)\n'
        '<table><tr><td><a href="https://a.example/x_(1)">a</a><img src="resources/image-2.png"></td></tr></table>',
      );
      expect(protected, isNot(contains('example')));
      expect(protected, isNot(contains('resources/')));
      expect(RegExp('⟦R1⟧').allMatches(protected).length, 2, reason: 'one URL, one token');
      expect(urls.restore('[a](⟦R1⟧)'), '[a](<https://a.example/x_(1)>)');
      expect(urls.restore('<img src="⟦R2⟧">'), '<img src="resources/image-1.png">');
      expect(urls.restore('see ⟦R9⟧ end'), 'see  end', reason: 'never invents a destination');
    });

    test('hides a token that is still streaming', () {
      final urls = WebFormatUrls()..protect('[a](https://a.example)');
      expect(urls.restore('[a](⟦R', partial: true), '[a](');
      expect(urls.restore('[a](⟦', partial: true), '[a](');
      expect(urls.restore('[a](⟦R1⟧)', partial: true), '[a](<https://a.example>)');
    });
  });

  group('splitWebMarkdown', () {
    test('keeps fences and HTML blocks whole', () {
      final blocks = webMarkdownBlocks(
        'a\nb\n\n```\nx\n\ny\n```\nc\n\n<table>\n<tr>\n\n</tr>\n</table>\n\n<ul><li>1</li></ul>\nd',
      );
      expect(blocks, ['a\nb', '```\nx\n\ny\n```', 'c', '<table>\n<tr>\n\n</tr>\n</table>', '<ul><li>1</li></ul>', 'd']);
    });

    test('cuts at headings once big enough and always before the limit', () {
      final body = '正文' * 600;
      final sections = splitWebMarkdown(
        '**一、开始**\n\n$body\n\n**二、接着**\n\n$body\n\n短\n\n## 三\n\n$body',
        minChars: 1000,
        maxChars: 2000,
      );
      expect(sections.map((s) => s.id), ['s1', 's2', 's3']);
      expect(sections.map((s) => s.title), ['开始', '接着', '三']);
      final long = splitWebMarkdown(List.filled(5, 'x' * 900).join('\n\n'), maxChars: 2000);
      expect(long.length, 3);
      expect(long.every((s) => s.text.length <= 2000), isTrue);
      expect(long.first.title.length, 25, reason: 'long titles are cut');
    });

    test('short pages stay one section, and empty input has none', () {
      expect(splitWebMarkdown('# 标题\n\n一段').single.title, '标题');
      expect(splitWebMarkdown('  \n\n'), isEmpty);
    });
  });

  group('validator', () {
    const validator = WebFormatValidator();
    final input = {'id': 's1', 'text': '[a](⟦R1⟧) https://kept.example/path'};
    test('allows deleted debris and kept URLs', () {
      expect(validator.validate('正文', input).complete, isTrue);
      expect(validator.validate('[a](⟦R1⟧) https://kept.example/path', input).complete, isTrue);
      expect(validator.validate('<img src="⟦R1⟧">', input).complete, isTrue);
      final code = {'id': 's1', 'text': 'a[0](b)'};
      expect(validator.validate('`a[0](b)`', code).complete, isTrue, reason: 'text already in the page is not new');
    });
    test('rejects empty output, unknown tokens and new URLs, retryably', () {
      for (final bad in [
        '  ',
        '[a](⟦R2⟧)',
        '[b](https://invented.example)',
        '[b](javascript:alert(1))',
        '[b](file.html)',
        '<a href="evil.html">b</a>',
        "<img src='x.png'>",
      ]) {
        final report = validator.validate(bad, input);
        expect(report.complete, isFalse, reason: bad);
        expect(report.issues.single.retryable, isTrue);
        expect(report.missingInputIds, {'s1'});
      }
    });
  });

  test('unwraps a fenced answer only when the fence surrounds all of it', () {
    expect(unwrapWebFormatOutput('```markdown\n## a\n```\n'), '## a');
    expect(unwrapWebFormatOutput('```\n## a\n```'), '## a');
    expect(unwrapWebFormatOutput('前\n```\ncode\n```'), '前\n```\ncode\n```');
  });

  test('splits the proposed title from the first section', () {
    expect(splitWebFormatTitle('# 标题\n\n正文'), (title: '标题', body: '正文'));
    expect(splitWebFormatTitle('# 还在写'), (title: '还在写', body: ''));
    expect(splitWebFormatTitle('## 不是\n正文'), (title: null, body: '## 不是\n正文'));
    expect(splitWebFormatTitle('# '), (title: null, body: ''));
  });

  test('collects headings for later sections', () {
    expect(webFormatHeadings('# 标题\n\n## 一\n\n文\n\n### 二'), ['## 一', '### 二']);
  });

  test('limits output by section size', () {
    expect(webFormatOutputLimit('x'), 1024);
    expect(webFormatOutputLimit('x' * 1000), 2256);
    expect(webFormatOutputLimit('x' * 9000), 8192);
  });

  group('WebFormatCheck', () {
    const source = '![](⟦R1⟧)\n\n[a](⟦R2⟧)\n\n```\ncode\n```\n\n一二三四五六七八九十';
    test('counts survivors', () {
      final check = WebFormatCheck.of(source, '![图](⟦R1⟧)\n\n[a](⟦R2⟧)\n\n```\ncode\n```\n\n一二三四五六七八九十');
      expect((check.imagesKept, check.imagesTotal, check.linksKept, check.linksTotal), (1, 1, 1, 1));
      expect((check.codeKept, check.codeTotal), (1, 1));
      expect(check.complete, isTrue);
      expect(check.needsReview, isFalse);
    });
    test('flags shrinking and growth, and missing items', () {
      final shrunk = WebFormatCheck.of(source, '一二三');
      expect(shrunk.imagesKept, 0);
      expect(shrunk.linksKept, 0);
      expect(shrunk.codeKept, 0);
      expect(shrunk.complete, isFalse);
      expect(shrunk.changePercent, lessThan(-20));
      expect(shrunk.needsReview, isTrue);
      expect(WebFormatCheck.of('一二三四', '一二三四五六七八').needsReview, isTrue);
      expect(WebFormatCheck.of('', '').changePercent, 0);
      expect(WebFormatCheck.of('<img src="⟦R1⟧">', '').imagesTotal, 1);
    });
  });

  test('comparison marks only blocks that are gone', () {
    final rows = webFormatComparison(
      '首页 分享到 微信\n\n你一定有过这样的经历\n\n![](⟦R1⟧)\n\n![](⟦R2⟧)',
      '## 标题\n\n你一定有过这样的经历。\n\n![图](⟦R1⟧)',
    );
    expect(rows.map((r) => r.removed), [true, false, false, true]);
  });

  test('builds section input and registers a tool-free contract', () {
    const section = WebFormatSource(id: 's2', title: 't', text: '正文');
    final input = webFormatInput(section, pageTitle: '页', index: 1, total: 3, previousHeadings: ['## 一']);
    expect(input['first'], isFalse);
    expect(input['position'], '2/3');
    expect(input['previousHeadings'], ['## 一']);
    expect(webFormatInput(section, pageTitle: '页', index: 0, total: 1)['first'], isTrue);

    final registry = TaskRegistry();
    registerWebFormatting(registry);
    final definition = registry.resolve<String>(webFormatSpec);
    expect(definition.spec.allowedTools, isEmpty);
    expect(definition.spec.category, TaskCategory.heavy);
    expect(definition.instructions, contains('untrusted'));
    expect(definition.validateInput(input).complete, isTrue);
    expect(definition.validateInput(const {'id': 's', 'text': ' '}).complete, isFalse);
    expect(definition.restore(definition.encode('x')), 'x');
    expect(definition.decode('```md\nx\n```'), 'x');
    expect(jsonEncode(input), contains('正文'));
    expect(standardKnowledgeRegistry().resolve(webFormatSpec, standardKnowledgeVersions(webFormatSpec)), hasLength(1));
  });

  group('runWebFormatHandle', () {
    TaskRequest<String> request() {
      final input = webFormatInput(
        const WebFormatSource(id: 's1', title: 't', text: '[a](⟦R1⟧) 正文'),
        pageTitle: '页',
        index: 0,
        total: 1,
      );
      return TaskRequest<String>(
        spec: webFormatSpec,
        input: input,
        inputFingerprint: quickInputFingerprint(input),
        maxOutputTokens: 1024,
        streamDrafts: true,
      );
    }

    RuntimeRunHandle<String> start(sdk.LLMClient client) {
      final registry = TaskRegistry();
      registerWebFormatting(registry);
      final base = ports.context(ModelProtocol.chatCompletions, category: TaskCategory.heavy);
      return SdkAgentRuntime(
        store: ports.MemoryRuns(),
        tasks: registry,
        knowledge: standardKnowledgeRegistry(),
        loadModel: ports.binding,
        testClient: client,
      ).start(
        request(),
        RunContext(
          runId: 'run',
          knowledgeVersions: standardKnowledgeVersions(webFormatSpec),
          config: base.config,
          inputRange: const {
            'ids': ['s1'],
          },
        ),
      );
    }

    sdk.StreamingMessage chunk(String text, {String? stop}) => sdk.StreamingMessage(
      modelMessage: sdk.ModelMessage(model: 'fixture-model', textOutput: text, stopReason: stop),
    );

    test('streams growing drafts and returns the validated result', () async {
      final drafts = <String>[];
      final source = Stream<sdk.StreamingMessage>.fromIterable([
        chunk('## 标题\n\n'),
        chunk('[a](⟦R1⟧) 正文', stop: 'stop'),
      ]);
      final client = StreamClient((_) => source);
      final result = await runWebFormatHandle(start(client), drafts.add, CancellationToken());
      expect(result, '## 标题\n\n[a](⟦R1⟧) 正文');
      expect(drafts.first, isEmpty, reason: 'a model start clears the draft');
      expect(drafts.last, contains('标题'));
    });

    test('invented URLs never count as formatted', () async {
      final bad = sdk.ModelMessage(model: 'fixture-model', textOutput: '[x](https://bad.example)', stopReason: 'stop');
      final client = StreamClient((_) => Stream.value(sdk.StreamingMessage(modelMessage: bad)));
      await expectLater(
        runWebFormatHandle(start(client), (_) {}, CancellationToken()),
        throwsA(isA<ResearchFailure>()),
      );
    });

    test('cancelling stops the run and reports cancellation', () async {
      final source = StreamController<sdk.StreamingMessage>();
      final client = StreamClient((_) => source.stream);
      final cancel = CancellationToken();
      final started = Completer<void>();
      final run = runWebFormatHandle(start(client), (draft) {
        if (draft.isNotEmpty && !started.isCompleted) started.complete();
      }, cancel);
      source.add(chunk('部分'));
      await started.future;
      cancel.cancel();
      await expectLater(run, throwsA(isA<ResearchFailure>()));
      await source.close();
    });
  });
}
