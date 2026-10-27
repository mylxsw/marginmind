import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_research/mm_research.dart';

import '../../app/providers.dart';
import '../workspace/workspace_controller.dart';
import 'research_answer.dart';
import 'research_drafts.dart';
import 'research_intents.dart';
import 'research_origin.dart';
import 'research_providers.dart';
import 'research_settings.dart';

/// What the launcher starts: the question as the user left it.
class ResearchLaunch {
  const ResearchLaunch({
    required this.origin,
    required this.intent,
    required this.question,
    required this.method,
    this.keywords = const [],
    this.kinds = const {},
    this.context = '',
  });

  final ResearchOrigin origin;
  final ResearchIntent intent;
  final String question;
  final ResearchMethod method;
  final List<String> keywords;
  final Set<ResearchSourceKind> kinds;

  /// The context the user confirmed, as sent.
  final String context;
}

enum ResearchTab { answer, sources, saved }

enum ResearchStage { search, answer, read }

/// A run in progress: its stage and, while reading, how far it got.
class ResearchProgress {
  const ResearchProgress(this.stage, {this.done = 0, this.total = 0});

  final ResearchStage stage;
  final int done;
  final int total;
}

/// Why a research could not start, for the panel to say.
enum ResearchBlock { noAi, noWeb }

/// The research panel of one study set: which session it shows and how,
/// plus the runs it started. Sessions own their results (the engine checks
/// every response against its session and request), so switching sessions,
/// documents or selections never moves a result elsewhere.
class ResearchPanelState {
  const ResearchPanelState({
    this.sessionId,
    this.tab = ResearchTab.answer,
    this.readingSourceId,
    this.focusParagraphId,
    this.readingVersion,
    this.filter,
    this.noteId,
    this.progress = const {},
    this.summarizing = const {},
    this.blocked = const {},
  });

  final String? sessionId;
  final ResearchTab tab;

  /// A source opened for reading, and the paragraph to scroll to.
  final String? readingSourceId;
  final String? focusParagraphId;
  final int? readingVersion;
  final ResearchSourceKind? filter;

  /// A saved note shown in the panel instead of the session.
  final String? noteId;

  /// Runs started from this window, by session id.
  final Map<String, ResearchProgress> progress;

  /// Sources (`sourceId@version`) whose AI summary is being written.
  final Set<String> summarizing;

  /// Sessions whose last run could not start, and why.
  final Map<String, ResearchBlock> blocked;

  ResearchPanelState copyWith({
    String? sessionId,
    bool clearSession = false,
    ResearchTab? tab,
    String? readingSourceId,
    String? focusParagraphId,
    int? readingVersion,
    bool closeReading = false,
    ResearchSourceKind? filter,
    bool clearFilter = false,
    String? noteId,
    bool clearNote = false,
    Map<String, ResearchProgress>? progress,
    Set<String>? summarizing,
    Map<String, ResearchBlock>? blocked,
  }) => ResearchPanelState(
    sessionId: clearSession ? null : (sessionId ?? this.sessionId),
    tab: tab ?? this.tab,
    readingSourceId: closeReading ? null : (readingSourceId ?? this.readingSourceId),
    focusParagraphId: closeReading
        ? null
        : readingSourceId != null
        ? focusParagraphId
        : this.focusParagraphId,
    readingVersion: closeReading
        ? null
        : readingSourceId != null
        ? readingVersion
        : this.readingVersion,
    filter: clearFilter ? null : (filter ?? this.filter),
    noteId: clearNote ? null : (noteId ?? this.noteId),
    progress: progress ?? this.progress,
    summarizing: summarizing ?? this.summarizing,
    blocked: blocked ?? this.blocked,
  );
}

/// The pane a research started from, which stays beside the panel: the
/// source for a passage, the map for a node.
PanelOrigin researchPanelOrigin(SourceAnchor? anchor) => switch (anchor?.target) {
  PdfTarget() => PanelOrigin.reader,
  CardTarget() => PanelOrigin.map,
  _ => PanelOrigin.toolbar,
};

class ResearchPanelController extends Notifier<ResearchPanelState> {
  ResearchPanelController(this.studySetId);

  final String studySetId;
  final _draftWrites = <String, Future<void>>{};
  final _stopped = <String>{};
  final _deleting = <String>{};

  /// The last request each session made from this window, for Retry.
  final _lastRequest = <String, Future<ResearchBlock?> Function()>{};

  @override
  ResearchPanelState build() => const ResearchPanelState();

  ResearchSessionKey _key(String sessionId) => (studySetId: studySetId, sessionId: sessionId);

  ResearchSessionController _session(String sessionId) => ref.read(researchSessionProvider(_key(sessionId)).notifier);

  /// The engine's state, including writes not yet published to listeners.
  Future<ResearchSessionState> _state(String sessionId) => _session(sessionId).current;

  WorkspaceController get _workspace => ref.read(workspaceProvider(studySetId).notifier);

  // ---- what the panel shows --------------------------------------------------------

  /// Shows [sessionId] in the research panel, opening it beside the pane the
  /// research came from: [origin], or else where the session started.
  void show(String sessionId, {PanelOrigin? origin, ResearchTab? tab}) {
    origin ??= researchPanelOrigin(
      ref.read(researchSessionsProvider(studySetId)).value?.where((s) => s.id == sessionId).firstOrNull?.anchor,
    );
    state = state.copyWith(
      sessionId: sessionId,
      tab: tab ?? (sessionId == state.sessionId ? state.tab : ResearchTab.answer),
      closeReading: sessionId != state.sessionId,
      clearFilter: sessionId != state.sessionId,
      clearNote: true,
    );
    _workspace.openPanel(RightPanel.research, origin: origin);
  }

  /// The panel's start page: later research and nothing selected.
  void showStart() {
    state = state.copyWith(clearSession: true, closeReading: true, clearNote: true);
    _workspace.openPanel(RightPanel.research);
  }

  void setTab(ResearchTab tab) => state = state.copyWith(tab: tab, closeReading: true);

  void setFilter(ResearchSourceKind? kind) =>
      state = kind == null ? state.copyWith(clearFilter: true) : state.copyWith(filter: kind);

  void openReading(String sourceId, {String? paragraphId, int? version}) => state = state.copyWith(
    readingSourceId: sourceId,
    focusParagraphId: paragraphId,
    readingVersion: version,
    tab: ResearchTab.sources,
    clearNote: true,
  );

  void closeReading() => state = state.copyWith(closeReading: true);

  /// A saved note, with its citations and places, in the panel.
  void showNote(String noteId, {PanelOrigin origin = PanelOrigin.toolbar}) {
    state = state.copyWith(noteId: noteId);
    _workspace.openPanel(RightPanel.research, origin: origin);
  }

  void closeNote() => state = state.copyWith(clearNote: true);

  // ---- starting -------------------------------------------------------------------

  Future<String> _create(ResearchLaunch launch, {bool later = false}) async {
    final key = await createResearchSession(
      ref,
      studySetId: studySetId,
      question: launch.question.trim(),
      origin: launch.origin.anchor,
      contextScope: launch.context,
      intent: launch.intent.name,
    );
    await _session(key.sessionId).updateDrafts([
      ResearchDrafts(
        method: launch.method,
        keywords: launch.keywords,
        kinds: launch.kinds,
        context: launch.context,
        later: later,
      ).toJson(),
    ]);
    return key.sessionId;
  }

  /// Creates a session for [launch], shows it and runs it. Returns its id.
  Future<String> start(ResearchLaunch launch) async {
    final id = await _create(launch);
    if (!ref.mounted) return id;
    show(id, origin: launch.origin.fromMap ? PanelOrigin.map : PanelOrigin.reader);
    unawaited(run(id));
    return id;
  }

  /// Keeps the passage and question for later; nothing is requested.
  Future<String> later(ResearchLaunch launch) => _create(launch, later: true);

  /// Adds a passage to a research while it runs: its next request (retry or
  /// follow-up) sends it as well. Where the research saves stays the same.
  Future<void> join(String sessionId, String passage) =>
      updateDrafts(sessionId, (d) => d.copyWith(extra: [...d.extra, passage]));

  // ---- running ----------------------------------------------------------------------

  void _progress(String sessionId, ResearchProgress? value) {
    if (!ref.mounted) return;
    final next = {...state.progress};
    if (value == null) {
      next.remove(sessionId);
    } else {
      next[sessionId] = value;
    }
    state = state.copyWith(progress: next);
  }

  String _context(ResearchDrafts drafts) =>
      [researchAnswerFormat, if (drafts.context.isNotEmpty) drafts.context, ...drafts.extra].join('\n\n');

  /// Runs (or runs again) the session's question with its method. Results
  /// are kept as they arrive; a failure is recorded on the session. Returns
  /// why it could not start, if it could not.
  /// Retry: the request that failed or was cancelled (an answer from
  /// sources, a follow-up), or the session's own run.
  Future<ResearchBlock?> retry(String sessionId) => (_lastRequest[sessionId] ?? () => run(sessionId))();

  /// Records when a request finished well, for the run line.
  Future<void> _finished(String sessionId) async {
    if (!ref.mounted || _deleting.contains(sessionId)) return;
    final value = await _state(sessionId);
    if (value.session.status != 'done') return;
    await updateDrafts(sessionId, (d) => d.copyWith(doneAt: ref.read(clockProvider)()));
  }

  final _runs = <String, Future<ResearchBlock?>>{};

  Future<ResearchBlock?> run(String sessionId) => _deleting.contains(sessionId)
      ? Future.value()
      : _runs[sessionId] ??= _runOnce(sessionId).whenComplete(() {
          _runs.remove(sessionId);
        });

  Future<void> saveVideoLink(String sessionId, Uri url) => _session(sessionId).saveVideoLink(url);

  Future<ResearchBlock?> _runOnce(String sessionId) async {
    _lastRequest[sessionId] = () => run(sessionId);
    final block = await _run(sessionId);
    if (block == null) {
      await updateDrafts(sessionId, (d) => d.copyWith(later: false));
      await _finished(sessionId);
    }
    if (ref.mounted) {
      state = state.copyWith(
        blocked: block == null ? ({...state.blocked}..remove(sessionId)) : {...state.blocked, sessionId: block},
      );
    }
    return block;
  }

  Future<ResearchBlock?> _run(String sessionId) async {
    _stopped.remove(sessionId);
    final current = await _state(sessionId);
    if (_deleting.contains(sessionId)) return null;
    final drafts = current.drafts;

    final session = _session(sessionId);
    final settings = ref.read(researchSettingsProvider);
    // Until an authorized transcript adapter exists, video-only work is discovery.
    if (drafts.kinds.length == 1 && drafts.kinds.contains(ResearchSourceKind.video)) {
      if (ref.mounted && state.sessionId == sessionId) state = state.copyWith(tab: ResearchTab.sources);
      return null;
    }
    try {
      switch (drafts.method) {
        case ResearchMethod.search:
          if (!drafts.kinds.contains(ResearchSourceKind.paper)) return null;
          _progress(sessionId, const ResearchProgress(ResearchStage.search));
          final query = drafts.keywords.isEmpty ? current.session.question : drafts.keywords.join(' ');
          await session.search(query);
          if (ref.mounted && state.sessionId == sessionId) state = state.copyWith(tab: ResearchTab.sources);
        case ResearchMethod.offline:
        case ResearchMethod.web:
          final web = drafts.method == ResearchMethod.web;
          if (web && !settings.webAvailable) return ResearchBlock.noWeb;
          final provider = await ref.read(researchAiFactoryProvider)();
          if (_deleting.contains(sessionId)) return null;
          if (provider == null) return ResearchBlock.noAi;
          _progress(sessionId, const ResearchProgress(ResearchStage.answer));
          await session.answer(
            provider: provider,
            question: current.session.question,
            mode: web ? ResearchMode.web : ResearchMode.offline,
            context: _context(drafts),
            budget: settings.budget,
          );
          if (web) await _readCited(sessionId, settings.pages);
      }
    } finally {
      _progress(sessionId, null);
    }
    return null;
  }

  /// After a web answer: reads the cited pages here, so their quotes are
  /// checked against text we keep and can be saved as evidence.
  Future<void> _readCited(String sessionId, int limit) async {
    if (_deleting.contains(sessionId)) return;
    final value = await _state(sessionId);
    if (value.session.status != 'done') return;
    final cited = {
      for (final c in value.session.history.lastOrNull?['cites'] as List? ?? const [])
        if (c is Map && c['source'] is String) c['source'] as String,
    };
    final ids = [
      for (final s in value.sources)
        if (cited.contains(s.id) && s.versions.isEmpty && s.readState != ResearchReadState.failed.name) s.id,
    ].take(limit).toList();
    for (final (i, id) in ids.indexed) {
      if (_stopped.contains(sessionId) || !ref.mounted) return;
      _progress(sessionId, ResearchProgress(ResearchStage.read, done: i, total: ids.length));
      await _session(sessionId).readSources([id]);
    }
  }

  /// Stops what is running; what arrived stays.
  Future<void> cancel(String sessionId) async {
    _stopped.add(sessionId);
    _progress(sessionId, null);
    await _session(sessionId).cancel();
  }

  /// A follow-up in the same session: it carries the session's earlier
  /// questions and answers. Searches the web only when the research does.
  Future<ResearchBlock?> followUp(String sessionId, String question) async {
    final text = question.trim();
    if (text.isEmpty) return null;
    _lastRequest[sessionId] = () => followUp(sessionId, text);
    final current = await _state(sessionId);
    final drafts = current.drafts;
    final settings = ref.read(researchSettingsProvider);
    final provider = await ref.read(researchAiFactoryProvider)();
    if (provider == null) return ResearchBlock.noAi;
    final web = drafts.method == ResearchMethod.web && settings.webAvailable;
    _stopped.remove(sessionId);
    _progress(sessionId, const ResearchProgress(ResearchStage.answer));
    try {
      await _session(sessionId).answer(
        provider: provider,
        question: text,
        mode: web ? ResearchMode.web : ResearchMode.offline,
        context: _context(drafts),
        followUp: true,
        budget: settings.budget,
      );
      if (web) await _readCited(sessionId, settings.pages);
    } finally {
      _progress(sessionId, null);
    }
    await _finished(sessionId);
    return null;
  }

  /// Paragraphs of the newest version of [source], within [budget] characters.
  Future<List<ResearchDocument>> _documents(ResearchSource source, int budget) async {
    final version = source.kind == 'video' ? null : source.versions.lastOrNull;
    if (version == null) return const [];
    final markdown = await ref
        .read(researchSnapshotRepositoryProvider)
        .readResearchSnapshot(studySetId, version.snapshotFile);
    final documents = <ResearchDocument>[];
    var used = 0;
    for (final p in snapshotParagraphs(markdown).entries) {
      if (used + p.value.length > budget) break;
      used += p.value.length;
      documents.add(
        ResearchDocument(
          sourceId: source.id,
          version: version.version,
          paragraphId: p.key,
          title: source.title,
          text: p.value,
        ),
      );
    }
    return documents;
  }

  /// Answers from the chosen sources only (their kept text, nothing else).
  Future<ResearchBlock?> answerFromChosen(String sessionId) async {
    _lastRequest[sessionId] = () => answerFromChosen(sessionId);
    final current = await _state(sessionId);
    final drafts = current.drafts;
    final settings = ref.read(researchSettingsProvider);
    final provider = await ref.read(researchAiFactoryProvider)();
    if (provider == null) return ResearchBlock.noAi;
    final chosen = [
      for (final s in current.sources)
        if (drafts.chosen.contains(s.id) && s.versions.isNotEmpty) s,
    ];
    if (chosen.isEmpty) return null;
    // Room for the question, context and instructions within the budget.
    final share = (settings.budget.inputCharacters ~/ 2) ~/ chosen.length;
    final documents = [for (final s in chosen) ...await _documents(s, share)];
    _stopped.remove(sessionId);
    _progress(sessionId, const ResearchProgress(ResearchStage.answer));
    if (ref.mounted && state.sessionId == sessionId) state = state.copyWith(tab: ResearchTab.answer);
    try {
      await _session(sessionId).answer(
        provider: provider,
        question: current.session.question,
        mode: ResearchMode.sources,
        context: _context(drafts),
        documents: documents,
        followUp: current.session.history.isNotEmpty,
        budget: settings.budget,
      );
    } finally {
      _progress(sessionId, null);
    }
    await _finished(sessionId);
    return null;
  }

  /// Reads one source's page (again) and keeps its text.
  Future<void> read(String sourceId, {required String sessionId}) async {
    _progress(sessionId, const ResearchProgress(ResearchStage.read, total: 1));
    try {
      await _session(sessionId).readSources([sourceId]);
    } finally {
      _progress(sessionId, null);
    }
  }

  Future<void> paste(String sessionId, String sourceId, String text) => _session(sessionId).pasteSource(sourceId, text);

  Future<void> delete(String sessionId) async {
    if (!_deleting.add(sessionId)) return;
    try {
      await cancel(sessionId);
      await _runs[sessionId];
      await _draftWrites[sessionId];
      await _session(sessionId).disposeEngine();
      await ref.read(researchSessionRepositoryProvider).deleteResearchSession(studySetId, sessionId);
      _lastRequest.remove(sessionId);
      _draftWrites.remove(sessionId);
      if (state.sessionId == sessionId) showStart();
      state = state.copyWith(blocked: {...state.blocked}..remove(sessionId));
      ref.invalidate(researchSessionsProvider(studySetId));
      ref.invalidate(researchSessionProvider(_key(sessionId)));
    } catch (_) {
      _deleting.remove(sessionId);
      rethrow;
    }
  }

  Future<void> rename(String sessionId, String question) => _session(sessionId).rename(question);

  /// A short AI summary of a source's kept text, shown apart from the text.
  /// Written on request only; stored with the session.
  Future<ResearchBlock?> summarize(String sessionId, ResearchSource source, {required String language}) async {
    final version = source.kind == 'video' ? null : source.versions.lastOrNull;
    if (version == null) return null;
    final key = '${source.id}@${version.version}';
    if (state.summarizing.contains(key)) return null;
    final provider = await ref.read(researchAiFactoryProvider)();
    if (provider == null) return ResearchBlock.noAi;
    state = state.copyWith(summarizing: {...state.summarizing, key});
    try {
      final documents = await _documents(source, 20000);
      if (documents.isEmpty) return null;
      final request = AiRequest(
        sessionId: sessionId,
        requestId: newId(),
        question: 'Summarize this source in two or three sentences, in $language.',
        mode: ResearchMode.sources,
        documents: documents,
        budget: const ResearchBudget(outputTokens: 600, duration: Duration(seconds: 60)),
      );
      final text = StringBuffer();
      final token = CancellationToken();
      try {
        await for (final event in provider.generate(request, token).timeout(request.budget.duration)) {
          if (event.requestId != request.requestId) continue;
          if (event.kind == AiEventKind.text) text.write(event.text ?? '');
          if (event.kind == AiEventKind.completed) break;
        }
      } finally {
        token.cancel();
      }
      final summary = text.toString().replaceAll(RegExp(r'\s*\[source:\d+\]'), '').trim();
      if (summary.isNotEmpty) {
        await updateDrafts(sessionId, (d) => d.copyWith(summaries: {...d.summaries, key: summary}));
      }
    } finally {
      if (ref.mounted) state = state.copyWith(summarizing: {...state.summarizing}..remove(key));
    }
    return null;
  }

  // ---- drafts -------------------------------------------------------------------------

  /// Changes the panel's drafts of a session. Changes are applied one after
  /// another, each to the result of the one before.
  Future<void> updateDrafts(String sessionId, ResearchDrafts Function(ResearchDrafts) change) {
    if (_deleting.contains(sessionId)) return Future.value();
    final previous = _draftWrites[sessionId] ?? Future.value();
    final next = previous.then((_) async {
      final current = await _state(sessionId);
      final session = _session(sessionId);
      await session.updateDrafts([
        for (final d in current.session.drafts)
          if (d['type'] != 'engine' && d['type'] != ResearchDrafts.type) d,
        change(current.drafts).toJson(),
      ]);
    });
    _draftWrites[sessionId] = next.catchError((Object _) {});
    return next;
  }

  Future<void> toggleChecked(String sessionId, String pointKey) => updateDrafts(
    sessionId,
    (d) => d.copyWith(
      checked: d.checked.contains(pointKey) ? ({...d.checked}..remove(pointKey)) : {...d.checked, pointKey},
    ),
  );

  Future<void> clearChecked(String sessionId) => updateDrafts(sessionId, (d) => d.copyWith(checked: {}));

  Future<void> editPoint(String sessionId, String pointKey, String text) => updateDrafts(sessionId, (d) {
    final edits = {...d.edits};
    if (text.trim().isEmpty) {
      edits.remove(pointKey);
    } else {
      edits[pointKey] = text.trim();
    }
    return d.copyWith(edits: edits);
  });

  Future<void> toggleChosen(String sessionId, String sourceId) => updateDrafts(
    sessionId,
    (d) =>
        d.copyWith(chosen: d.chosen.contains(sourceId) ? ({...d.chosen}..remove(sourceId)) : {...d.chosen, sourceId}),
  );

  Future<void> addClip(String sessionId, ResearchClip clip) => updateDrafts(
    sessionId,
    (d) => d.clips.any((c) => c.evidence.id == clip.evidence.id) ? d : d.copyWith(clips: [...d.clips, clip]),
  );

  Future<void> removeClip(String sessionId, String evidenceId) => updateDrafts(
    sessionId,
    (d) => d.copyWith(
      clips: [
        for (final c in d.clips)
          if (c.evidence.id != evidenceId) c,
      ],
    ),
  );

  /// After a save: what was saved is no longer pending in the panel.
  Future<void> saved(String sessionId, {required Set<String> points, required Set<String> clips}) => updateDrafts(
    sessionId,
    (d) => d.copyWith(
      checked: d.checked.difference(points),
      clips: [
        for (final c in d.clips)
          if (!clips.contains(c.evidence.id)) c,
      ],
    ),
  );
}

final researchPanelProvider = NotifierProvider.family<ResearchPanelController, ResearchPanelState, String>(
  ResearchPanelController.new,
);
