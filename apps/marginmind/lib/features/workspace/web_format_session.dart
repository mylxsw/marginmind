import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';

/// Formats one section. [onDraft] receives the whole draft so far, which a
/// model restart may shorten. Throws on failure, also when [cancel] fires.
typedef WebFormatExecutor = Future<String> Function(
  Map<String, dynamic> input,
  ModelReference? model,
  void Function(String draft) onDraft,
  CancellationToken cancel,
);

enum WebFormatPhase { preparing, running, done, stopped }

enum WebFormatSectionState { waiting, running, done, failed, source }

class WebFormatSection {
  WebFormatSection(this.source, this._urls);
  final WebFormatSource source;
  final WebFormatUrls _urls;
  String _draft = '';
  WebFormatSectionState state = WebFormatSectionState.waiting;
  Object? error;
  bool acknowledged = false;
  WebFormatCheck? check;

  /// Headings of finished text replace the guess made from the extraction.
  String get title {
    final heading = RegExp(r'^#{2,6} (.+)$', multiLine: true).firstMatch(_draft);
    if (heading != null) return heading[1]!.trim();
    // Without a heading, name it after what was kept: the extraction's first
    // line is often the page debris formatting just removed.
    final body = _bodyWithTokens.trim();
    return formatted && body.isNotEmpty ? webFormatPlainTitle(body) : source.title;
  }

  bool get formatted => state == WebFormatSectionState.done;
  bool get needsReview => formatted && !acknowledged && (check?.needsReview ?? false);
  String get _bodyWithTokens {
    final body = splitWebFormatTitle(_draft).body;
    return body.trim() == webFormatEmptySection ? '' : body;
  }

  /// Formatted text so far, ready to display or save.
  String get output => _urls.restore(_bodyWithTokens, partial: state == WebFormatSectionState.running);
  String get sourceMarkdown => _urls.restore(source.text);

  /// What this section contributes to the document.
  String get markdown => formatted ? output : sourceMarkdown;

  /// Source blocks, ready to display, marked when formatting removed them.
  List<({String text, bool removed})> get comparison => [
    for (final row in webFormatComparison(source.text, formatted ? _bodyWithTokens : source.text))
      (text: _urls.restore(row.text), removed: row.removed),
  ];
}

/// One conversion's formatting, from extraction to the Markdown the user saves.
/// It owns no model client: every section is a run through [executor].
class WebFormatSession extends ChangeNotifier {
  WebFormatSession({required this.executor, required this.pageTitle, this.model});
  final WebFormatExecutor executor;
  final String pageTitle;
  final ModelReference? model;
  final _urls = WebFormatUrls();
  final _clock = Stopwatch();
  List<WebFormatSection> sections = const [];
  WebFormatPhase phase = WebFormatPhase.preparing;
  bool checking = false;

  /// Why the whole run stopped. Single section failures stay on their section.
  Object? runError;

  /// The clean title from the first section, for the caller to offer.
  String? proposedTitle;
  String? _edited;
  CancellationToken? _cancel;
  Timer? _ticker;
  final _queue = <int>[];
  int _generation = 0;
  DateTime _lastDraft = DateTime.fromMillisecondsSinceEpoch(0);
  bool _disposed = false;

  bool get edited => _edited != null;
  bool get running => phase == WebFormatPhase.preparing || phase == WebFormatPhase.running;
  bool get finished => phase == WebFormatPhase.done || phase == WebFormatPhase.stopped;
  Duration get elapsed => _clock.elapsed;
  int get formattedCount => sections.where((s) => s.formatted).length;
  int get sourceChars => sections.fold(0, (n, s) => n + s.source.text.length);
  int get outputChars => sections
      .where((s) => s.formatted || s.state == WebFormatSectionState.running)
      .fold(0, (n, s) => n + s.output.length);
  int? get activeIndex {
    final index = sections.indexWhere((s) => s.state == WebFormatSectionState.running);
    return index < 0 ? null : index;
  }

  /// Share of the run finished, including the running section's draft.
  double get progress {
    if (sections.isEmpty) return 0;
    final settled = sections
        .where((s) => s.formatted || s.state == WebFormatSectionState.failed || s.state == WebFormatSectionState.source)
        .length;
    final active = activeIndex == null ? null : sections[activeIndex!];
    final draft = active == null || active.source.text.isEmpty
        ? 0.0
        : (active.output.length / active.source.text.length).clamp(0.0, 1.0);
    return (settled + draft) / sections.length;
  }

  String get markdown => _edited ?? sections.map((s) => s.markdown).where((m) => m.trim().isNotEmpty).join('\n\n');

  /// Totals over formatted sections; null until something is formatted.
  WebFormatCheck? get check {
    final checks = sections.where((s) => s.formatted).map((s) => s.check).nonNulls.toList();
    if (checks.isEmpty) return null;
    int sum(int Function(WebFormatCheck) of) => checks.fold(0, (n, c) => n + of(c));
    return WebFormatCheck(
      imagesKept: sum((c) => c.imagesKept),
      imagesTotal: sum((c) => c.imagesTotal),
      linksKept: sum((c) => c.linksKept),
      linksTotal: sum((c) => c.linksTotal),
      codeKept: sum((c) => c.codeKept),
      codeTotal: sum((c) => c.codeTotal),
      changePercent: 0,
    );
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// [source] is the extraction as Markdown, without title or provenance.
  void start(String source) {
    sections = [for (final part in splitWebMarkdown(_urls.protect(source))) WebFormatSection(part, _urls)];
    _clock
      ..reset()
      ..start();
    _queue
      ..clear()
      ..addAll(List.generate(sections.length, (i) => i));
    unawaited(_run());
  }

  /// Formats whatever is unfinished, in document order.
  void resume() {
    if (running || edited) return;
    _queue
      ..clear()
      ..addAll([
        for (final (i, s) in sections.indexed)
          if (s.state == WebFormatSectionState.waiting || s.state == WebFormatSectionState.failed) i,
      ]);
    if (_queue.isEmpty) return;
    _clock.start();
    unawaited(_run());
  }

  /// Runs one section again, right away or after the current run.
  void rerun(int index) {
    if (edited) return;
    final section = sections[index];
    section
      ..state = WebFormatSectionState.waiting
      ..error = null
      ..acknowledged = false
      ..check = null;
    if (running) {
      _queue.add(index);
      _changed();
      return;
    }
    _queue
      ..clear()
      ..add(index);
    unawaited(_run());
  }

  void useSource(int index) {
    sections[index]
      ..state = WebFormatSectionState.source
      ..error = null;
    _queue.remove(index);
    _changed();
  }

  void acknowledge(int index) {
    sections[index].acknowledged = true;
    _changed();
  }

  /// Section results are kept; the first text edit becomes the whole document.
  void edit(String markdown) {
    _edited = markdown;
    _changed();
  }

  void revertEdits() {
    _edited = null;
    _changed();
  }

  void stop() {
    if (!running) return;
    _generation++;
    _cancel?.cancel();
    _cancel = null;
    _queue.clear();
    for (final section in sections) {
      if (section.state == WebFormatSectionState.running) {
        section
          ..state = WebFormatSectionState.waiting
          .._draft = '';
      }
    }
    checking = false;
    _settle(WebFormatPhase.stopped);
  }

  void _settle(WebFormatPhase next) {
    phase = next;
    _clock.stop();
    _ticker?.cancel();
    _ticker = null;
    _changed();
  }

  bool _fatal(Object error) =>
      error is ConfigurationFailure ||
      error is ResearchFailure &&
          (error.kind == ResearchFailureKind.network || error.kind == ResearchFailureKind.authentication);

  Future<void> _run() async {
    final generation = ++_generation;
    runError = null;
    phase = WebFormatPhase.running;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _changed());
    _changed();
    while (_queue.isNotEmpty) {
      if (generation != _generation) return;
      final index = _queue.removeAt(0);
      final section = sections[index];
      section
        ..state = WebFormatSectionState.running
        ..error = null
        .._draft = '';
      _changed();
      final cancel = _cancel = CancellationToken();
      try {
        final result = await executor(
          webFormatInput(
            section.source,
            pageTitle: pageTitle,
            index: index,
            total: sections.length,
            previousHeadings: [
              for (final earlier in sections.take(index))
                if (earlier.formatted) ...webFormatHeadings(earlier._draft),
            ].reversed.take(8).toList().reversed.toList(),
          ),
          model,
          (draft) {
            if (generation != _generation) return;
            section._draft = draft;
            // Full re-layout on every token would make long documents stutter.
            final now = DateTime.now();
            if (now.difference(_lastDraft) >= const Duration(milliseconds: 60)) {
              _lastDraft = now;
              _changed();
            }
          },
          cancel,
        );
        if (generation != _generation) return;
        section
          .._draft = result
          ..state = WebFormatSectionState.done
          ..check = WebFormatCheck.of(section.source.text, splitWebFormatTitle(result).body);
        if (index == 0) proposedTitle = splitWebFormatTitle(result).title ?? proposedTitle;
        _changed();
      } catch (error) {
        if (generation != _generation) return;
        section
          .._draft = ''
          ..state = WebFormatSectionState.waiting;
        if (_fatal(error)) {
          runError = error;
          _queue.clear();
          _settle(WebFormatPhase.stopped);
          return;
        }
        section
          ..state = WebFormatSectionState.failed
          ..error = error;
        _changed();
      }
    }
    checking = true;
    _changed();
    // Checks ran with each section; this beat lets the last stage be seen.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (generation != _generation) return;
    checking = false;
    _settle(
      sections.any((s) => s.state == WebFormatSectionState.waiting) ? WebFormatPhase.stopped : WebFormatPhase.done,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _cancel?.cancel();
    _ticker?.cancel();
    _clock.stop();
    super.dispose();
  }
}
