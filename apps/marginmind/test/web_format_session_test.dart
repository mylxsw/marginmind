import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/web_format_session.dart';
import 'package:mm_core/mm_core.dart';

/// Answers each section by id; drafts arrive in two steps so tests see streaming.
class FakeExecutor {
  FakeExecutor(this.answers);
  final Map<String, Object> answers;
  final inputs = <Map<String, dynamic>>[];
  Completer<void>? gate;
  Future<String> call(
    Map<String, dynamic> input,
    ModelReference? model,
    void Function(String) onDraft,
    CancellationToken cancel,
  ) async {
    inputs.add(input);
    final answer = answers[input['id']] ?? '正文';
    if (answer is String) onDraft(answer.substring(0, answer.length ~/ 2));
    if (gate != null) await cancel.bind(gate!.future);
    cancel.check();
    if (answer is! String) throw answer;
    return answer;
  }
}

Future<void> settled(WebFormatSession session) async {
  while (session.running) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

final source = [
  '**一、开始**\n\n${'甲' * 1300}\n\n[链接](<https://a.example>)',
  '**二、接着**\n\n${'乙' * 1300}\n\n![](<resources/image-1.png>)',
  '**三、最后**\n\n${'丙' * 1300}',
].join('\n\n');

void main() {
  test('formats sections in order, restores URLs and proposes the title', () async {
    final fake = FakeExecutor({
      's1': '# 干净标题\n\n## 开始\n\n${'甲' * 1300}\n\n[链接](⟦R1⟧)',
      's2': '## 接着\n\n${'乙' * 1300}\n\n![图](⟦R2⟧)',
      's3': '## 最后\n\n${'丙' * 1300}',
    });
    final session = WebFormatSession(executor: fake.call, pageTitle: '干净标题 - 网站')..start(source);
    await settled(session);
    expect(session.phase, WebFormatPhase.done);
    expect(session.proposedTitle, '干净标题');
    expect(session.formattedCount, 3);
    expect(session.markdown, isNot(contains('# 干净标题')));
    expect(session.markdown, contains('[链接](<https://a.example>)'));
    expect(session.markdown, contains('![图](<resources/image-1.png>)'));
    expect(fake.inputs.map((i) => i['first']), [true, false, false]);
    expect(fake.inputs.last['previousHeadings'], ['## 开始', '## 接着']);
    expect(fake.inputs.first['text'], isNot(contains('https://')), reason: 'URLs never reach the model');
    expect(session.sections.first.title, '开始');
    final check = session.check!;
    expect((check.imagesKept, check.imagesTotal, check.linksKept, check.linksTotal), (1, 1, 1, 1));
    expect(session.progress, 1);
    expect(session.outputChars, greaterThan(3900));
    session.dispose();
  });

  test('one failed section keeps the rest going and can be retried or kept as captured', () async {
    final fake = FakeExecutor({'s2': const ResearchFailure(ResearchFailureKind.rateLimited)});
    final session = WebFormatSession(executor: fake.call, pageTitle: '页')..start(source);
    await settled(session);
    expect(session.phase, WebFormatPhase.done);
    expect(session.sections[1].state, WebFormatSectionState.failed);
    expect(session.sections[1].error, isA<ResearchFailure>());
    expect(session.formattedCount, 2);
    expect(session.markdown, contains('乙'), reason: 'an unformatted section keeps its captured text');

    fake.answers['s2'] = '## 接着\n\n${'乙' * 1300}';
    session.rerun(1);
    await settled(session);
    expect(session.sections[1].state, WebFormatSectionState.done);

    session.useSource(1);
    expect(session.sections[1].state, WebFormatSectionState.source);
    expect(session.markdown, contains('**二、接着**'));
    session.dispose();
  });

  test('a connection failure stops the run, keeps finished sections and resumes', () async {
    final fake = FakeExecutor({'s2': const ResearchFailure(ResearchFailureKind.network)});
    final session = WebFormatSession(executor: fake.call, pageTitle: '页')..start(source);
    await settled(session);
    expect(session.phase, WebFormatPhase.stopped);
    expect(session.runError, isA<ResearchFailure>());
    expect(session.formattedCount, 1);
    expect(session.sections[2].state, WebFormatSectionState.waiting);

    fake.answers.remove('s2');
    session.resume();
    await settled(session);
    expect(session.phase, WebFormatPhase.done);
    expect(session.runError, isNull);
    expect(session.formattedCount, 3);
    session.dispose();
  });

  test('stopping cancels the call and discards its partial draft', () async {
    final fake = FakeExecutor({'s1': '## 开始\n\n正文正文'})..gate = Completer<void>();
    final session = WebFormatSession(executor: fake.call, pageTitle: '页')..start(source);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(session.activeIndex, 0);
    expect(session.sections.first.output, isNotEmpty);
    expect(session.progress, greaterThanOrEqualTo(0));
    session.stop();
    expect(session.phase, WebFormatPhase.stopped);
    expect(session.sections.first.state, WebFormatSectionState.waiting);
    expect(session.sections.first.output, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(fake.inputs.length, 1, reason: 'no further section starts');
    session.stop();
    session.dispose();
  });

  test('edits replace the assembled text, disable section work and can be reverted', () async {
    final session = WebFormatSession(executor: FakeExecutor({}).call, pageTitle: '页')..start(source);
    await settled(session);
    final original = session.markdown;
    session.edit('改过');
    expect(session.edited, isTrue);
    expect(session.markdown, '改过');
    session.rerun(0);
    expect(session.sections.first.state, WebFormatSectionState.done, reason: 'section reruns stop after edits');
    session.resume();
    expect(session.running, isFalse);
    session.revertEdits();
    expect(session.markdown, original);
    session.dispose();
  });

  test('flags a shrunken section until acknowledged, and handles an all-debris section', () async {
    final fake = FakeExecutor({'s1': '## 开始\n\n甲', 's3': '<!-- empty -->'});
    final session = WebFormatSession(executor: fake.call, pageTitle: '页')..start(source);
    await settled(session);
    expect(session.sections.first.needsReview, isTrue);
    expect(session.sections.first.comparison.any((row) => row.removed), isTrue);
    session.acknowledge(0);
    expect(session.sections.first.needsReview, isFalse);
    expect(session.sections[2].output, isEmpty);
    expect(session.sections[2].formatted, isTrue);
    expect(session.markdown, isNot(contains('丙')));
    session.rerun(0);
    await settled(session);
    expect(session.sections.first.acknowledged, isFalse);
    session.dispose();
  });

  test('a rerun requested during a run joins its queue; disposing stops everything', () async {
    final fake = FakeExecutor({})..gate = Completer<void>();
    final session = WebFormatSession(executor: fake.call, pageTitle: '页')..start(source);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    session.rerun(2);
    expect(session.running, isTrue);
    fake.gate!.complete();
    await settled(session);
    expect(fake.inputs.map((i) => i['id']), ['s1', 's2', 's3', 's3']);
    session.dispose();
    session.stop();
  });
}
