import 'package:mm_core/mm_core.dart';

/// Asks for an answer the panel can show as checkable points. Sent with the
/// confirmed context, never instead of it.
const researchAnswerFormat =
    'Answer in the language of the question, as Markdown: a few `## ` sections chosen from conclusion, '
    'key explanation, evidence, other views and limits, open questions (only those the question needs; '
    'a short question needs two or three). Under each heading write every point as one `- ` bullet. '
    'No preamble, no closing summary.';

/// A citation of one answer point: a source of the session, and the evidence
/// (a verified quote) when there is one.
class AnswerCite {
  const AnswerCite(this.sourceId, [this.evidenceId]);

  final String sourceId;
  final String? evidenceId;

  @override
  bool operator ==(Object other) => other is AnswerCite && other.sourceId == sourceId && other.evidenceId == evidenceId;

  @override
  int get hashCode => Object.hash(sourceId, evidenceId);
}

/// One checkable statement of an answer. [key] is stable for the turn's text:
/// checks and edits are stored under it.
class AnswerPoint {
  const AnswerPoint({required this.key, required this.text, this.cites = const []});

  final String key;
  final String text;
  final List<AnswerCite> cites;
}

class AnswerSection {
  const AnswerSection({required this.heading, required this.points, this.openQuestions = false});

  /// Empty when the answer starts without a heading.
  final String heading;
  final List<AnswerPoint> points;

  /// "Open questions": its points are not expected to cite anything.
  final bool openQuestions;
}

/// One question and answer of a session.
class AnswerTurn {
  const AnswerTurn({
    required this.index,
    required this.question,
    required this.method,
    required this.sections,
    required this.answer,
  });

  final int index;
  final String question;

  /// The session `mode` the turn ran with (`offline`, `sources`, `web`).
  final String method;
  final String answer;
  final List<AnswerSection> sections;

  Iterable<AnswerPoint> get points => sections.expand((s) => s.points);

  /// Every turn of [history] that has text, oldest first.
  static List<AnswerTurn> all(List<Map<String, Object?>> history) => [
    for (final (i, turn) in history.indexed)
      if ((turn['answer'] as String? ?? '').trim().isNotEmpty)
        AnswerTurn(
          index: i,
          question: turn['question'] as String? ?? '',
          method: turn['mode'] as String? ?? '',
          answer: turn['answer'] as String,
          sections: parseAnswer(
            turn['answer'] as String,
            turn: i,
            cites: [
              for (final c in turn['cites'] as List? ?? const [])
                if (c is Map) c.cast<String, Object?>(),
            ],
            documents: [
              for (final d in turn['documents'] as List? ?? const [])
                if (d is Map) d.cast<String, Object?>(),
            ],
          ),
        ),
  ];
}

final _heading = RegExp(r'^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$');
final _boldHeading = RegExp(r'^\s*\*\*([^*]{1,40})\*\*\s*[:：]?\s*$');
final _bullet = RegExp(r'^\s*(?:[-*•]|\d{1,2}[.)、])\s+(.*)$');
final _sourceMarker = RegExp(r'\s*\[source:(\d+)\]');
final _openQuestions = RegExp(r'待解决|未解决|开放问题|尚待|open question|unresolved|further question', caseSensitive: false);

/// Splits a Markdown answer into sections of points. Headings start sections;
/// bullets and paragraphs are points. `[source:N]` markers (answers from
/// chosen sources) become citations of the N-th sent paragraph and are removed
/// from the text; [cites] recorded at answer offsets go to the point there.
List<AnswerSection> parseAnswer(
  String answer, {
  int turn = 0,
  List<Map<String, Object?>> cites = const [],
  List<Map<String, Object?>> documents = const [],
}) {
  final sections = <(String, List<_Point>)>[('', [])];
  var offset = 0;
  var open = false;
  for (final line in answer.split('\n')) {
    final start = offset;
    offset += line.length + 1;
    if (line.trim().isEmpty) {
      open = false;
      continue;
    }
    final heading = _heading.firstMatch(line) ?? _boldHeading.firstMatch(line);
    if (heading != null) {
      sections.add((_plain(heading.group(heading.groupCount)!), []));
      open = false;
      continue;
    }
    final points = sections.last.$2;
    final bullet = _bullet.firstMatch(line);
    if (bullet != null || !open || points.isEmpty) {
      points.add(_Point(start, offset, bullet?.group(1) ?? line.trim()));
      open = true;
    } else {
      // A wrapped line continues the point above.
      points.last
        ..end = offset
        ..raw = '${points.last.raw} ${line.trim()}';
    }
  }

  final all = [for (final s in sections) ...s.$2];
  String? evidenceOf(Object? source, Object? paragraph) => cites
      .where((c) => c['source'] == source && c['paragraph'] == paragraph)
      .map((c) => c['evidence'])
      .whereType<String>()
      .firstOrNull;
  var marked = false;
  for (final point in all) {
    point.text = _plain(
      point.raw.replaceAllMapped(_sourceMarker, (m) {
        marked = true;
        final index = int.parse(m[1]!);
        final document = index < documents.length ? documents[index] : null;
        final id = document?['sourceId'];
        if (id is String) point.cites.add(AnswerCite(id, evidenceOf(id, document!['paragraphId'])));
        return '';
      }),
    );
  }
  // Offsets recorded while streaming: the point containing the offset, or
  // the first one after it (a cited block streams right after its citation).
  // Markers in the text are exact; offsets then only repeat them at the end.
  for (final c in marked ? const <Map<String, Object?>>[] : cites) {
    final source = c['source'];
    final at = c['at'];
    if (source is! String || at is! int || all.isEmpty) continue;
    final point = all.firstWhere((p) => at < p.end, orElse: () => all.last);
    point.cites.add(AnswerCite(source, c['evidence'] as String?));
  }

  return [
    for (final (si, (heading, points)) in sections.indexed)
      if (points.any((p) => p.text.isNotEmpty))
        AnswerSection(
          heading: heading,
          openQuestions: _openQuestions.hasMatch(heading),
          points: [
            for (final (pi, p) in points.indexed)
              if (p.text.isNotEmpty) AnswerPoint(key: '$turn.$si.$pi', text: p.text, cites: _merge(p.cites)),
          ],
        ),
  ];
}

class _Point {
  _Point(this.start, this.end, this.raw);

  final int start;
  int end;
  String raw;
  String text = '';
  final cites = <AnswerCite>[];
}

/// One cite per source, keeping one with evidence when there is.
List<AnswerCite> _merge(List<AnswerCite> cites) {
  final bySource = <String, AnswerCite>{};
  for (final c in cites) {
    final previous = bySource[c.sourceId];
    if (previous == null || (previous.evidenceId == null && c.evidenceId != null)) bySource[c.sourceId] = c;
  }
  return bySource.values.toList();
}

/// Markdown emphasis and links as plain text.
String _plain(String text) => text
    .replaceAllMapped(RegExp(r'\[([^\]]+)\]\((?:[^)]+)\)'), (m) => m[1]!)
    .replaceAll(RegExp(r'\*\*|__|`'), '')
    .replaceAllMapped(RegExp(r'(^|[^*])\*([^*\s][^*]*)\*'), (m) => '${m[1]}${m[2]}')
    .trim();

/// The paragraph a source's evidence points to, for "open at the cited
/// passage".
String? evidenceParagraph(Iterable<Evidence> evidence, AnswerCite cite) =>
    evidence.where((e) => e.id == cite.evidenceId).firstOrNull?.locator.paragraphId ??
    evidence.where((e) => e.sourceId == cite.sourceId).firstOrNull?.locator.paragraphId;
