import 'dart:convert';

import 'package:mm_core/mm_core.dart';
import 'package:test/test.dart';

final now = DateTime.utc(2026, 10, 31);
TranslationJob job({
  TranslationJobState state = TranslationJobState.running,
  Map<String, TranslationFailure> failures = const {},
}) => TranslationJob(
  id: 'job',
  documentId: 'doc',
  targetLang: 'zh',
  sourceLang: 'en',
  range: TranslationRange(1, 20),
  mode: TranslationMode.batch,
  batchSize: 10,
  model: 'model',
  state: state,
  batch: TranslationBatch(index: 1, range: TranslationRange(1, 10)),
  estimateTokens: 100,
  failures: failures,
  createdAt: now,
  updatedAt: now,
);
TranslationParagraph paragraph({String text = 'Hello world', String fp = 'fp', int page = 1, double top = 790}) =>
    TranslationParagraph(
      documentId: 'doc',
      page: page,
      index: 0,
      text: text,
      fingerprint: fp,
      rects: [PageRect(20, top, 100, top - 10)],
    );
TranslationSegment segment() => TranslationSegment(
  key: textKey('Hello world', 'zh'),
  fingerprint: 'fp',
  page: 1,
  index: 0,
  text: '你好',
  model: 'model',
  profile: 'profile',
  origin: TranslationOrigin.ai,
  at: now,
);

void main() {
  test('NFC and Unicode whitespace are stable; language and split version differ', () {
    expect(normalizeTranslationText(' \tCafe\u0301\u00a0\u2003hello\r\nworld　'), 'Café hello world');
    expect(textKey('Cafe\u0301\n world', 'zh'), textKey('Café world', 'zh'));
    expect(textKey('same', 'zh'), isNot(textKey('same', 'ja')));
    expect(textKey('same', 'zh'), isNot(textKey('same', 'zh', splitVersion: 2)));
    expect(translationProfile(' x\n y ', promptVersion: 1), translationProfile('x y', promptVersion: 1));
    expect(translationProfile('x', promptVersion: 1), isNot(translationProfile('x', promptVersion: 2)));
    expect(textKey(paragraph(page: 1, fp: 'old').text, 'zh'), textKey(paragraph(page: 9, fp: 'new').text, 'zh'));
    expect(normalizeTranslationText('\u1100\u1161'), '가');
  });
  test('margin threshold counts distinct pages and excludes body text', () {
    final heights = {for (var i = 1; i <= 10; i++) i: 800.0};
    final ps = [
      for (var i = 1; i <= 3; i++) paragraph(page: i, fp: '$i'),
      paragraph(page: 1, fp: 'dup'),
      paragraph(page: 4, fp: 'body', top: 400),
      paragraph(page: 5, fp: 'other', text: 'Different'),
    ];
    expect(translationMarginFingerprints(ps, pageHeights: heights), {'1', '2', '3', 'dup'});
    expect(translationMarginFingerprints(ps.take(2), pageHeights: heights), isEmpty);
    expect(translationMarginFingerprints([ps.first, ps[3]], pageHeights: {1: 800}), isEmpty);
    expect(
      translationMarginFingerprints(
        [paragraph(top: 40, page: 1, fp: 'a'), paragraph(top: 42, page: 2, fp: 'b')],
        pageHeights: {1: 800, 2: 800},
      ),
      {'a', 'b'},
    );
    expect(translationMarginFingerprints(ps, pageHeights: {}), isEmpty);
  });
  test('no-send rules and conservative language recognition', () {
    TranslationSkipReason? skip(String s, {String? detected, String target = 'zh'}) =>
        translationSkipReason(paragraph(text: s), target, detectedLanguage: detected);
    for (final text in ['12', 'Page 12 of 20', '第 12 页', '3/20']) {
      expect(skip(text), TranslationSkipReason.pageNumber);
    }
    for (final text in ['', '3.14159 ± 2', '———', 'https://example.com/a', 'www.example.com']) {
      expect(skip(text), TranslationSkipReason.nonLinguistic);
    }
    expect(skip('Read https://example.com'), isNull);
    expect(skip('This is ordinary text'), isNull);
    expect(skip('This is the text with words', target: 'en'), TranslationSkipReason.targetLanguage);
    expect(skip('这是已经翻译的中文段落'), TranslationSkipReason.targetLanguage);
    expect(skip('這是已經翻譯的中文段落', target: 'zh-Hant'), TranslationSkipReason.targetLanguage);
    expect(skip('中文内容', detected: 'zh'), TranslationSkipReason.targetLanguage);
    expect(skip('中文内容', detected: 'zh-Hant'), isNull);
    for (final language in TranslationLanguage.values) {
      expect(
        skip('Text with trusted detection', target: language.code, detected: language.code),
        TranslationSkipReason.targetLanguage,
      );
    }
    expect(skip('これは日本語です', target: 'ja'), TranslationSkipReason.targetLanguage);
    expect(skip('한국어 문장입니다', target: 'ko'), TranslationSkipReason.targetLanguage);
    expect(detectTranslationLanguage('a'), isNull);
    expect(detectTranslationLanguage('中文内容'), isNull);
    expect(detectTranslationLanguage('한국어 and English mixed'), isNull);
    expect(translationSkipReason(paragraph(), 'zh', marginFingerprints: {'fp'}), TranslationSkipReason.repeatedMargin);
  });
  test('job JSON round trip ignores unknown fields and protects failures', () {
    final failures = {'fp': TranslationFailure(kind: 'protocol', attempts: 3, at: now)};
    final original = job(failures: failures).copyWith(
      note: 'attention 注意',
      usage: TranslationUsage(inputTokens: 3, outputTokens: 4, requests: 1),
      budgetAcknowledged: true,
      state: TranslationJobState.paused,
      pauseReason: TranslationPauseReason.quit,
    );
    failures.clear();
    final decoded = TranslationJob.fromJson(
      (jsonDecode(jsonEncode({...original.toJson(), 'future': 42})) as Map).cast(),
    );
    expect(decoded.toJson(), original.toJson());
    expect(decoded.failures, hasLength(1));
    expect(() => decoded.failures.clear(), throwsUnsupportedError);
    expect(decoded.usage.totalTokens, 7);
    expect(decoded.copyWith(state: TranslationJobState.running).pauseReason, isNull);
    expect(decoded.copyWith(note: 'new').pauseReason, TranslationPauseReason.quit);
    expect(job(state: TranslationJobState.stopped).isActive, isFalse);
    expect(job(state: TranslationJobState.done).isActive, isFalse);
    for (final state in TranslationJobState.values) {
      expect(TranslationJob.fromJson(job(state: state).toJson()).state, state);
    }
    final changed = job().copyWith(
      mode: TranslationMode.all,
      batchSize: 5,
      model: 'other',
      promptVersion: 2,
      batch: TranslationBatch(index: 2, range: TranslationRange(11, 15)),
      estimateTokens: 200,
      updatedAt: now.add(Duration(days: 1)),
    );
    expect(TranslationJob.fromJson(changed.toJson()).toJson(), changed.toJson());
    expect(() => TranslationJob.fromJson({...job().toJson(), 'v': 2}), throwsFormatException);
    expect(() => job().copyWith(batchSize: 0), throwsArgumentError);
    expect(() => TranslationRange(0, 1), throwsArgumentError);
    expect(() => TranslationBatch(index: 0, range: TranslationRange(1, 2)), throwsArgumentError);
    expect(() => TranslationUsage(requests: -1), throwsArgumentError);
    expect(() => TranslationFailure(kind: '', attempts: 0, at: now), throwsArgumentError);
  });
  test('segment codec, validation and snapshot thresholds', () {
    final value = segment();
    expect(TranslationSegment.fromJson({...value.toJson(), 'future': true}).toJson(), value.toJson());
    expect(() => TranslationSegment.fromJson({...value.toJson(), 'v': 2}), throwsFormatException);
    expect(() => TranslationSegment.fromJson({...value.toJson(), 'text': ' '}), throwsArgumentError);
    final snapshot = TranslationSnapshot(
      segments: {value.key: value},
      lineCount: 100,
      corruptLines: 1,
      overwrittenLines: 30,
    );
    expect(snapshot.needsCompaction, isFalse);
    expect(snapshot.needsCorruptionWarning, isFalse);
    expect(() => snapshot.segments.clear(), throwsUnsupportedError);
    expect(TranslationSnapshot(lineCount: 100, corruptLines: 2, overwrittenLines: 31).needsCorruptionWarning, isTrue);
    expect(TranslationSnapshot(lineCount: 100, overwrittenLines: 31).needsCompaction, isTrue);
    expect(TranslationSnapshot().needsCompaction, isFalse);
  });
  test('recovery derives progress from results before failures and range', () {
    final p = paragraph(),
        s = segment(),
        j = job(
          failures: {'fp': TranslationFailure(kind: 'protocol', attempts: 3, at: now)},
        );
    TranslationSegmentState state({
      Map<String, TranslationSegment> saved = const {},
      TranslationJob? task,
      bool skipped = false,
      Set<String> done = const {},
      Set<String> running = const {},
      TranslationParagraph? para,
    }) => deriveTranslationSegmentState(
      para ?? p,
      'zh',
      segments: saved,
      job: task,
      skipped: skipped,
      completedKeys: done,
      runningKeys: running,
    );
    expect(state(saved: {s.key: s}, task: j), TranslationSegmentState.reused);
    expect(state(saved: {s.key: s}, task: j, done: {s.key}), TranslationSegmentState.done);
    expect(state(task: j), TranslationSegmentState.failed);
    expect(state(skipped: true, task: j), TranslationSegmentState.skipped);
    expect(state(), TranslationSegmentState.none);
    expect(state(task: job()), TranslationSegmentState.queued);
    expect(state(task: job(state: TranslationJobState.paused)), TranslationSegmentState.queued);
    expect(state(task: job(), running: {s.key}), TranslationSegmentState.running);
    expect(
      state(
        task: job(state: TranslationJobState.stopped),
        running: {s.key},
      ),
      TranslationSegmentState.none,
    );
    expect(state(task: job(), para: paragraph(page: 15)), TranslationSegmentState.none);
    expect(state(task: job(), para: paragraph(page: 21)), TranslationSegmentState.none);
  });
  test('page states ignore skipped text and use defined priority', () {
    const n = TranslationSegmentState.none,
        q = TranslationSegmentState.queued,
        r = TranslationSegmentState.running,
        d = TranslationSegmentState.done,
        f = TranslationSegmentState.failed,
        u = TranslationSegmentState.reused,
        s = TranslationSegmentState.skipped;
    final cases = <List<TranslationSegmentState>, TranslationPageState>{
      []: TranslationPageState.skipped,
      [s]: TranslationPageState.skipped,
      [s, d]: TranslationPageState.done,
      [s, u]: TranslationPageState.reused,
      [d, u]: TranslationPageState.done,
      [f, d]: TranslationPageState.partial,
      [f, u]: TranslationPageState.partial,
      [f, s]: TranslationPageState.failed,
      [f, q]: TranslationPageState.queued,
      [r, f, q]: TranslationPageState.running,
      [q, n]: TranslationPageState.queued,
      [d, n]: TranslationPageState.none,
      [n]: TranslationPageState.none,
    };
    for (final c in cases.entries) {
      expect(deriveTranslationPageState(c.key), c.value);
    }
  });
}
