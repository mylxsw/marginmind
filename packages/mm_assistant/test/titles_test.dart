import 'package:mm_core/mm_core.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:test/test.dart';

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
  test('legacy title helper never chooses a model by name', () {
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
    expect(assistantTitleModel(current, [other, small]), current);
  });
  test('title adapter selects its task and releases cancellation on success or failure', () async {
    CancellationToken? token;
    final result = await generateAssistantTitle((type, input, cancel) async {
      expect(type, TaskType.titleGenerate);
      expect(input, {'question': '解释通用电气的转型'});
      token = cancel;
      return '通用电气转型';
    }, '解释通用电气的转型');
    expect(result, '通用电气转型');
    expect(token!.isCancelled, true);
    await expectLater(
      generateAssistantTitle((_, _, cancel) async {
        token = cancel;
        throw StateError('fixture');
      }, 'question'),
      throwsStateError,
    );
    expect(token!.isCancelled, true);
  });
}
