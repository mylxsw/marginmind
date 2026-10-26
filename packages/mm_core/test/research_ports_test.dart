import 'dart:async';

import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

void main() {
  test('cancellation interrupts pending port work and is idempotent', () async {
    final token = CancellationToken();
    final pending = Completer<int>();
    final result = token.bind(pending.future);
    final expectation = expectLater(
      result,
      throwsA(isA<ResearchFailure>().having((e) => e.kind, 'kind', ResearchFailureKind.cancelled)),
    );
    token.cancel();
    token.cancel();
    await expectation;
    pending.complete(1);
    expect(token.isCancelled, isTrue);
  });

  test('request and extracted paragraphs cannot be changed by their caller', () {
    const document = ResearchDocument(sourceId: 's', version: 1, paragraphId: 'p', title: 't', text: 'text');
    final documents = [document];
    final request = AiRequest(
      sessionId: 's',
      requestId: 'r',
      question: 'q',
      mode: ResearchMode.sources,
      documents: documents,
    );
    documents.clear();
    expect(request.documents, [document]);
    expect(request.documents.clear, throwsUnsupportedError);
    final paragraphs = {'p': 'original'};
    final content = ExtractedContent(url: Uri.parse('https://example.com'), title: 't', paragraphs: paragraphs);
    paragraphs['p'] = 'changed';
    expect(content.paragraphs['p'], 'original');
    expect(() => content.paragraphs['p'] = 'changed', throwsUnsupportedError);
  });
}
