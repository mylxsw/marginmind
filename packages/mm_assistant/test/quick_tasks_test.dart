import 'dart:convert';

import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

import 'support.dart';
import 'task_runtime_test.dart' as fixture;
import 'model_policy_test.dart' as policy;
import 'word_lookup_test.dart' as words;

Future<RunResult<String>> run(TaskType type, Map<String, dynamic> input, ScriptClient client) =>
    SdkAgentRuntime(
          store: fixture.Store(),
          tasks: quickTaskRegistry(),
          knowledge: standardKnowledgeRegistry(),
          testClient: client,
          loadModel: (_) async =>
              RuntimeModelBinding(model: policy.model(ModelProtocol.chatCompletions), key: '', serviceRevision: 1),
        )
        .start(
          TaskRequest<String>(spec: quickTaskSpec(type), input: input, inputFingerprint: quickInputFingerprint(input)),
          fixture.context(),
        )
        .result;

void main() {
  test('title validates empty, Unicode length and single line with one off repair', () async {
    for (final bad in ['😀' * 25, 'one\ntwo', 'one\rtwo']) {
      final client = ScriptClient([answer(bad), answer('😀' * 24)]);
      final result = await run(TaskType.titleGenerate, {'question': 'question'}, client);
      expect(result.status, RunStatus.completed);
      expect(result.value!.runes, hasLength(24));
      expect(result.usage.repairs, 1);
      expect(client.modelConfigs.every((c) => c.extra?['reasoning_effort'] == 'none'), true);
      expect(client.toolRequests.every((t) => t.isEmpty), true);
    }
  });
  test('translation preserves placeholders and structure without summary style', () async {
    final input = {
      'text': '# Hello {name}\n\nRead `id` at https://example.org',
      'sourceLanguage': 'en',
      'targetLanguage': 'zh',
    };
    const translated = '# 你好 {name}\n\n查看 https://example.org 的 `id`';
    final client = ScriptClient([answer('摘要'), answer(translated)]);
    final result = await run(TaskType.selectionTranslate, input, client);
    expect(result.status, RunStatus.completed);
    expect(result.value, translated);
    expect(client.calls, 2);
    final prompt = jsonEncode(client.requests.first.map((m) => m.toJson()).toList());
    expect(prompt, isNot(contains('加粗结论')));
    expect(prompt, isNot(contains('read_pages')));
    final failure = await run(TaskType.selectionTranslate, input, ScriptClient([answer('bad'), answer('still bad')]));
    expect(failure.status, isNot(RunStatus.completed));
  });
  test('format changes and missing numeric placeholders never complete', () async {
    for (final pair in [
      ('# Hello', '## 你好'),
      ('- Hello', '你好'),
      ('> Hello', '你好'),
      ('Hello {0} %1\$s', '你好'),
      ('```dart\nfinal x = 1;\n```', '```dart\nfinal x = 2;\n```'),
    ]) {
      final result = await run(TaskType.selectionTranslate, {
        'text': pair.$1,
        'sourceLanguage': null,
        'targetLanguage': 'zh',
      }, ScriptClient([answer(pair.$2), answer(pair.$2)]));
      expect(result.status, isNot(RunStatus.completed), reason: pair.toString());
    }
  });
  test('word and context schema repairs enter SDK lifecycle', () async {
    for (final contextOnly in [false, true]) {
      final client = ScriptClient([answer('{}'), answer(jsonEncode(words.value()))]);
      final result = await run(TaskType.wordLookup, {
        'term': 'pain',
        'sentence': 'pain',
        'sourceLanguage': 'fr',
        'targetLanguage': 'zh',
        'contextOnly': contextOnly,
      }, client);
      expect(result.status, RunStatus.completed);
      expect(result.usage.modelCalls, 2);
      expect(result.usage.repairs, 1);
    }
  });
  test('empty or truncated output never succeeds', () async {
    for (final response in [answer(''), answer('Title', stop: 'length')]) {
      final result = await run(TaskType.titleGenerate, {'question': 'question'}, ScriptClient([response]));
      expect(result.status, RunStatus.failed);
    }
  });
  test('pain cache separates source language, auto detection, target and aliases', () async {
    var calls = 0;
    final lookup = WordLookup.tasks((type, input, cancel) async {
      calls++;
      expect(type, TaskType.wordLookup);
      return jsonEncode(words.value()..['lemma'] = 'pain');
    });
    for (final source in ['en', 'fr', null]) {
      await lookup.lookup(
        term: 'pains',
        sentence: 'pain',
        sourceLanguage: source,
        targetLanguage: 'zh',
        model: null,
        cancel: CancellationToken(),
      );
      await lookup.lookup(
        term: 'pain',
        sentence: 'pain',
        sourceLanguage: source,
        targetLanguage: 'zh',
        model: null,
        cancel: CancellationToken(),
      );
      await lookup.lookupContext(
        lemma: 'pain',
        sentence: 'pain',
        sourceLanguage: source,
        targetLanguage: 'zh',
        model: null,
        cancel: CancellationToken(),
      );
    }
    expect(calls, 3);
    await lookup.lookup(
      term: 'pain',
      sentence: 'pain',
      sourceLanguage: 'fr',
      targetLanguage: 'en',
      model: null,
      cancel: CancellationToken(),
    );
    expect(calls, 4);
  });
}
