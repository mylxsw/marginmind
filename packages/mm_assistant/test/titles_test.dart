import 'package:dart_agent_core/eval.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  const current = AssistantModel(
    provider: AssistantProvider.compatible,
    model: 'coding/auto',
    endpoint: 'https://example.com/v1',
  );
  test('short selection replaces pronouns; long or missing selections use bounded placeholder', () {
    const selection = ContextItem(id: 's', kind: ContextKind.selection, displayText: '伊梅尔特');
    expect(assistantTitlePlaceholder('他是谁', [selection]), '伊梅尔特是谁');
    expect(assistantSelectionTitle('解释概念', [selection]), null);
    expect(assistantTitlePlaceholder('😀' * 30, []), '😀' * 24);
    expect(
      assistantSelectionTitle('这段讲什么', [
        const ContextItem(id: 's', kind: ContextKind.selection, displayText: '过长的选区内容不能当作一个人名或者术语'),
      ]),
      null,
    );
    expect(assistantTitlePlaceholder('  一个\n问题  ', []), '一个 问题');
  });
  test('title uses available faster model from same service, otherwise current', () {
    const small = AssistantModel(
      provider: AssistantProvider.compatible,
      model: 'mini',
      endpoint: 'https://example.com/v1',
    );
    const other = AssistantModel(
      provider: AssistantProvider.compatible,
      model: 'flash',
      endpoint: 'https://other.example/v1',
    );
    expect(assistantTitleModel(current, [other]), current);
    expect(assistantTitleModel(current, [other, small]), small);
  });
  test('title recording/replay is separate, bounded and language instructed', () async {
    final store = InMemoryRecordingStore();
    final fake = ScriptClient([answer('通用电气转型')]);
    for (final client in [RecordingLLMClient(inner: fake, store: store), ReplayLLMClient(store: store)]) {
      expect(await generateAssistantTitle(client, current.model, '解释通用电气的转型'), '通用电气转型');
    }
    expect(fake.requests.single.first.toJson().toString(), contains('24'));
    expect(fake.calls, 1);
  });
  test('empty and failed title generation leave caller a recoverable result', () async {
    expect(await generateAssistantTitle(ScriptClient([answer('')]), 'fake', 'question'), '');
    await expectLater(generateAssistantTitle(ScriptClient([]), 'fake', 'question'), throwsRangeError);
  });
}
