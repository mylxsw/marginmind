import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:mm_core/mm_core.dart';

import 'sources.dart';

ResearchSession patchSession(ResearchSession session, Map<String, Object?> patch) =>
    ResearchSession.fromJson({...session.toJson(), ...patch});

/// One application-wide barrier. Failure prevents every new request until retried
/// explicitly by rebuilding the runtime. Never restarts paid provider work.
class ResearchRecovery {
  ResearchRecovery(this.repository, this.studySets, {DateTime Function()? now}) : now = now ?? DateTime.now;
  final ResearchSessionRepository repository;
  final Future<List<String>> Function() studySets;
  final DateTime Function() now;
  Future<void>? _ready;
  Future<void> get ready => _ready ??= _recover();
  Future<void> _recover() async {
    for (final id in await studySets()) {
      for (final session in await repository.listResearchSessions(id)) {
        if (session.status == 'running' || session.status == 'idle') {
          await repository.saveResearchSession(
            id,
            patchSession(session, {
              'status': session.status == 'running' ? 'interrupted' : 'draft',
              'updatedAt': now().toIso8601String(),
            }),
          );
        }
      }
    }
  }
}

enum ResearchReadState { unread, snippet, abstractOnly, fullText, transcript, failed, noTranscript }

/// Engine drafts stay inside format 7's extensible session envelope. They become
/// library content only through saveResearchNote; unfinished work is not undoable.
class ResearchSessionState {
  ResearchSessionState(this.session);
  final ResearchSession session;
  Map<String, Object?> get data => session.drafts.where((e) => e['type'] == 'engine').firstOrNull ?? const {};
  List<ResearchSource> get sources => [
    for (final s in data['sources'] as List? ?? []) ResearchSource.fromJson((s as Map).cast()),
  ];
  List<Evidence> get evidence => [
    for (final e in data['evidence'] as List? ?? []) Evidence.fromJson((e as Map).cast()),
  ];
  Map<String, Object?> get metadata => (data['metadata'] as Map? ?? {}).cast<String, Object?>();
  String get answer => session.history.lastOrNull?['answer'] as String? ?? '';
  String? get error => data['error'] as String?;
}

class ResearchSessionEngine {
  ResearchSessionEngine({
    required this.studySetId,
    required ResearchSession session,
    required this.repository,
    required this.snapshots,
    required this.recovery,
    required this.newRequestId,
    DateTime Function()? now,
    this.onSaved,
    this.videoTitles,
  }) : _state = ResearchSessionState(session),
       now = now ?? DateTime.now;
  final String studySetId;
  final ResearchSessionRepository repository;
  final ResearchSnapshotRepository snapshots;
  final ResearchRecovery recovery;
  final String Function() newRequestId;
  final DateTime Function() now;
  final void Function()? onSaved;
  final VideoTitles? videoTitles;
  ResearchSessionState _state;
  ResearchSessionState get state => _state;
  final _changes = StreamController<ResearchSessionState>.broadcast();
  Stream<ResearchSessionState> get changes => _changes.stream;
  Future<void> _writes = Future.value();
  CancellationToken? _active;
  String? _requestId;
  bool _disposed = false;

  bool _current(CancellationToken token) => !_disposed && identical(token, _active) && !token.isCancelled;
  Future<void> _write(ResearchSession Function(ResearchSession) change, {CancellationToken? token}) {
    final next = _writes.then((_) async {
      if (_disposed || (token != null && !_current(token))) return;
      final session = patchSession(change(_state.session), {'updatedAt': now().toIso8601String()});
      await repository.saveResearchSession(studySetId, session);
      _state = ResearchSessionState(session);
      if (!_disposed) _changes.add(_state);
      onSaved?.call();
    });
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  ResearchSession _data(ResearchSession session, Map<String, Object?> changes) => patchSession(session, {
    'drafts': [
      for (final draft in session.drafts)
        if (draft['type'] != 'engine') draft,
      {...ResearchSessionState(session).data, 'type': 'engine', ...changes},
    ],
  });

  Future<void> updateDrafts(List<Map<String, Object?>> drafts) async {
    await recovery.ready;
    if (drafts.any((e) => e['type'] == 'engine')) throw ArgumentError('Reserved draft type');
    await _write(
      (s) => patchSession(s, {
        'drafts': [
          ...drafts,
          {...state.data, 'type': 'engine'},
        ],
      }),
    );
  }

  /// Cancelling immediately invalidates callbacks, then flushes the accepted data.
  Future<void> cancel() async {
    final token = _active;
    if (token == null) return;
    token.cancel();
    await _write(
      (s) => identical(_active, token) && s.status == 'running' ? patchSession(s, {'status': 'cancelled'}) : s,
    );
  }

  Future<void> _run(
    Duration duration,
    Future<void> Function(CancellationToken, String) work, {
    Map<String, Object?>? turn,
  }) async {
    if (duration <= Duration.zero) throw ArgumentError.value(duration);
    await recovery.ready;
    if (_disposed) throw StateError('Disposed session');
    _active?.cancel();
    final token = _active = CancellationToken();
    final requestId = _requestId = newRequestId();
    await _write(
      (s) => _data(
        patchSession(s, {
          'status': 'running',
          if (turn != null) 'mode': turn['mode'],
          if (turn != null)
            'history': [
              ...s.history,
              {...turn, 'requestId': requestId, 'answer': ''},
            ],
        }),
        {'error': null},
      ),
      token: token,
    );
    if (!_current(token)) return;
    try {
      // Includes TLS handshake stalls, provider silence and platform callbacks.
      // Timeout releases the session even if a transport cannot release its socket.
      await token.bind(work(token, requestId)).timeout(duration);
      await _write((s) => patchSession(s, {'status': 'done'}), token: token);
    } catch (error) {
      if (_current(token)) {
        // Invalidate first: late completions cannot cross the terminal write.
        token.cancel();
        final failure = error is TimeoutException
            ? 'timeout'
            : error is ResearchFailure
            ? (error.code ?? error.kind.name)
            : 'unavailable';
        await _write(
          (s) => identical(_active, token)
              ? _data(
                  patchSession(s, {
                    'status': error is ResearchFailure && error.kind == ResearchFailureKind.budget
                        ? 'cancelled'
                        : 'failed',
                  }),
                  {'error': failure},
                )
              : s,
        );
      }
    } finally {
      token.cancel();
    }
  }

  Future<void> answer({
    required AiProvider provider,
    required String question,
    required ResearchMode mode,
    String context = '',
    List<ResearchDocument> documents = const [],
    bool followUp = false,
    ResearchBudget budget = const ResearchBudget(),
  }) async {
    budget.validate();
    final selected = List<ResearchDocument>.unmodifiable(documents);
    // Only caller-confirmed context plus this session's own previous turns.
    final history = followUp
        ? jsonEncode(state.session.history.map((e) => {'question': e['question'], 'answer': e['answer']}).toList())
        : '';
    final confirmed = [context, if (history.isNotEmpty) history].join('\n');
    await _run(
      budget.duration,
      (token, id) async {
        if (mode == ResearchMode.sources) {
          for (final document in selected) {
            final source = state.sources.where((s) => s.id == document.sourceId).firstOrNull;
            final version = source?.versions.where((v) => v.version == document.version).firstOrNull;
            if (source?.kind == 'video') {
              throw const ResearchFailure(ResearchFailureKind.invalidRequest, 'no_transcript');
            }
            if (version == null) throw const ResearchFailure(ResearchFailureKind.invalidRequest, 'missing_snapshot');
            final markdown = await token.bind(snapshots.readResearchSnapshot(studySetId, version.snapshotFile));
            if (snapshotParagraphs(markdown)[document.paragraphId] != document.text) {
              throw const ResearchFailure(ResearchFailureKind.invalidRequest, 'invalid_paragraph');
            }
          }
        }
        final request = AiRequest(
          sessionId: state.session.id,
          requestId: id,
          question: question,
          mode: mode,
          context: confirmed,
          documents: selected,
          budget: budget,
        );
        var completed = false;
        final iterator = StreamIterator(provider.generate(request, token));
        try {
          while (await token.bind(iterator.moveNext())) {
            final event = iterator.current;
            if (!_current(token) || event.sessionId != request.sessionId || event.requestId != _requestId) continue;
            if (event.kind == AiEventKind.completed) {
              completed = true;
              break;
            }
            await _write((s) {
              var next = s;
              if (event.kind == AiEventKind.text && event.text != null) {
                final turns = [...s.history];
                turns[turns.length - 1] = {...turns.last, 'answer': '${turns.last['answer']}${event.text}'};
                next = patchSession(s, {'history': turns});
              }
              if ((event.kind == AiEventKind.source || event.kind == AiEventKind.citation) &&
                  mode != ResearchMode.offline) {
                next = _citation(next, event.citation, mode, selected, cite: event.kind == AiEventKind.citation);
              }
              if (event.kind == AiEventKind.toolError) {
                next = _data(next, {'toolError': 'source_failed'});
              }
              return next;
            }, token: token);
          }
        } finally {
          // A misbehaving stream's cancel Future must not hold the session hostage.
          unawaited(iterator.cancel().catchError((Object _) {}));
        }
        if (!completed) throw const ResearchFailure(ResearchFailureKind.protocol, 'incomplete_stream');
      },
      turn: {
        'question': question,
        'mode': mode.name,
        'context': context,
        'documents': [
          for (final d in selected) {'sourceId': d.sourceId, 'version': d.version, 'paragraphId': d.paragraphId},
        ],
      },
    );
  }

  ResearchSource _source(SearchHit hit) {
    final source = sourceFromHit(hit, now());
    return ResearchSource.fromJson({
      ...source.toJson(),
      'id': sha256.convert(utf8.encode('${state.session.id}:${source.id}')).toString(),
    });
  }

  ResearchSource _mergeCandidate(List<ResearchSource> sources, ResearchSource incoming, Map<String, Object?> metadata) {
    for (final source in sources) {
      final aliases = (metadata[source.id] as Map?)?['aliases'] as List? ?? [];
      for (final alias in aliases.cast<String>()) {
        try {
          if (canonicalUrl(Uri.parse(alias)) == incoming.canonicalUrl) return source;
        } on ResearchFailure {
          /* Ignore an invalid historical alias. */
        }
      }
    }
    return mergeSource(sources, incoming);
  }

  /// [cite] records where the citation falls in the answer (`turn.cites`):
  /// the provider's answer offset when it has one, else the answer length so
  /// far (a cited block streams right after its citations). The UI ties
  /// citations to answer points with it; sources alone are never cited.
  ResearchSession _citation(
    ResearchSession session,
    ResearchCitation? citation,
    ResearchMode mode,
    List<ResearchDocument> documents, {
    bool cite = false,
  }) {
    if (citation == null) return session;
    final value = ResearchSessionState(session);
    final sources = [...value.sources];
    final metadata = {...value.metadata};
    final cited = <Map<String, Object?>>[];
    if (mode == ResearchMode.web && citation.url != null) {
      ResearchSource source;
      try {
        source = _mergeCandidate(sources, _source(SearchHit(url: citation.url!, title: citation.title)), metadata);
      } on ResearchFailure {
        return session;
      }
      cited.add({'source': source.id});
      if (citation.quote != null && citation.quote!.isNotEmpty) {
        final previous = (metadata[source.id] as Map? ?? {}).cast<String, Object?>();
        metadata[source.id] = {
          ...previous,
          'candidateQuotes': {...(previous['candidateQuotes'] as List? ?? []).cast<String>(), citation.quote!}.toList(),
        };
      }
    }
    final evidence = [...value.evidence];
    // URL-only citations are never evidence. Exact supplied paragraphs are trusted
    // only after the immutable snapshot check before generating the request.
    for (final d in documents) {
      if (mode != ResearchMode.sources ||
          citation.sourceId != d.sourceId ||
          citation.version != d.version ||
          citation.paragraphId != d.paragraphId) {
        continue;
      }
      final quote = citation.quote ?? d.text;
      if (quote.isEmpty || !d.text.contains(quote)) continue;
      final key = sha256.convert(utf8.encode(jsonEncode([d.sourceId, d.version, d.paragraphId, quote]))).toString();
      cited.add({'source': d.sourceId, 'evidence': key, 'paragraph': d.paragraphId});
      if (evidence.any((e) => e.id == key)) continue;
      evidence.add(
        Evidence(
          id: key,
          sourceId: d.sourceId,
          sourceVersion: d.version,
          quote: quote,
          locator: EvidenceLocator.paragraph(d.paragraphId),
          acquisition: EvidenceAcquisition.auto,
          capturedAt: now(),
        ),
      );
    }
    var turns = session.history;
    if (cite && cited.isNotEmpty && turns.isNotEmpty) {
      final turn = turns.last;
      final at = citation.start ?? (turn['answer'] as String? ?? '').length;
      turns = [
        ...turns.take(turns.length - 1),
        {
          ...turn,
          'cites': [
            ...turn['cites'] as List? ?? const [],
            for (final c in cited) {...c, 'at': at},
          ],
        },
      ];
    }
    return _data(patchSession(session, {'sourceIds': sources.map((s) => s.id).toList(), 'history': turns}), {
      'sources': sources.map((s) => s.toJson()).toList(),
      'evidence': evidence.map((e) => e.toJson()).toList(),
      'metadata': metadata,
    });
  }

  Future<void> search(SearchProvider provider, String query, {Duration timeout = const Duration(seconds: 30)}) =>
      _run(timeout, (token, _) async {
        final hits = await token.bind(provider.search(SearchRequest(query), token));
        final abstracts = <SearchHit, (String, String)>{};
        for (final hit in hits) {
          token.check();
          if (hit.snippet.isEmpty || _source(hit).kind != 'paper') continue;
          final content = markdownArticle(
            ReadableHtml(url: hit.url, title: hit.title, html: '<p>${htmlEscape.convert(hit.snippet)}</p>'),
          );
          final markdown = encodeSnapshot(content.paragraphs);
          final file = await token.bind(snapshots.writeResearchSnapshot(studySetId, markdown));
          abstracts[hit] = (file, sha256.convert(utf8.encode(markdown)).toString());
        }
        await _write((s) {
          final sources = [...ResearchSessionState(s).sources];
          final metadata = {...ResearchSessionState(s).metadata};
          for (final hit in hits) {
            var source = _mergeCandidate(sources, _source(hit), metadata);
            final abstract = abstracts[hit];
            if (abstract != null &&
                source.readState != ResearchReadState.fullText.name &&
                !source.versions.any((v) => v.hash == abstract.$2)) {
              final version = SourceVersion(
                version: source.versions.fold<int>(0, (n, v) => n > v.version ? n : v.version) + 1,
                snapshotFile: abstract.$1,
                hash: abstract.$2,
              );
              source = ResearchSource.fromJson({
                ...source.toJson(),
                'readState': ResearchReadState.abstractOnly.name,
                'versions': [...source.versions.map((v) => v.toJson()), version.toJson()],
              });
              sources[sources.indexWhere((s) => s.id == source.id)] = source;
            }
            final previous = (metadata[source.id] as Map? ?? {}).cast<String, Object?>();
            metadata[source.id] = {
              ...previous,
              if (hit.snippet.isNotEmpty) 'abstract': hit.snippet,
              if (hit.openAccess != null) 'openAccess': hit.openAccess,
              if (hit.openAccessUrl != null) 'openAccessUrl': hit.openAccessUrl.toString(),
              'aliases': {...(previous['aliases'] as List? ?? []), hit.url.toString()}.toList(),
            };
          }
          return _data(
            patchSession(s, {
              'keywords': [query],
              'sourceIds': sources.map((s) => s.id).toList(),
            }),
            {'sources': sources.map((s) => s.toJson()).toList(), 'metadata': metadata},
          );
        }, token: token);
      });

  /// Explicit reading only. Each failure is local to its source. Sequential reads
  /// are deliberately bounded to one WebView; callers can retry individual IDs.
  Future<void> readSources(
    ContentExtractor extractor,
    List<String> sourceIds, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    final ids = sourceIds.toSet().toList();
    return _run(timeout * (ids.length + 1), (token, _) async {
      for (final id in ids) {
        token.check();
        final source = state.sources.where((s) => s.id == id).firstOrNull;
        if (source == null || source.kind == 'video') continue;
        final child = CancellationToken();
        token.whenCancelled.then((_) => child.cancel());
        try {
          final content = await child.bind(extractor.extract(Uri.parse(source.url), child)).timeout(timeout);
          child.check();
          token.check();
          final markdown = encodeSnapshot(content.paragraphs);
          final file = await token.bind(snapshots.writeResearchSnapshot(studySetId, markdown));
          await _write((s) {
            final current = ResearchSessionState(s);
            final sources = [...current.sources];
            var index = sources.indexWhere((e) => e.id == id);
            if (index < 0) return s;
            var canonical = sources[index].canonicalUrl;
            try {
              if (content.canonicalUrl != null) canonical = canonicalUrl(content.canonicalUrl!);
            } on ResearchFailure {
              /* Ignore unsafe canonical hints; never fetch them. */
            }
            final metadata = {...current.metadata};
            final duplicate = sources.where((e) => e.id != id && e.canonicalUrl == canonical).firstOrNull;
            // Merge only an unversioned candidate. Published evidence and source
            // IDs are immutable; already-retained sources remain distinct records.
            if (duplicate != null && sources[index].versions.isEmpty) {
              final incoming = (metadata[id] as Map? ?? {}).cast<String, Object?>();
              final retained = (metadata[duplicate.id] as Map? ?? {}).cast<String, Object?>();
              metadata[duplicate.id] = {
                ...incoming,
                ...retained,
                'aliases': {
                  ...(incoming['aliases'] as List? ?? []),
                  ...(retained['aliases'] as List? ?? []),
                  sources[index].url,
                  duplicate.url,
                }.toList(),
                'candidateQuotes': {
                  ...(incoming['candidateQuotes'] as List? ?? []),
                  ...(retained['candidateQuotes'] as List? ?? []),
                }.toList(),
              };
              metadata.remove(id);
              sources.removeAt(index);
              index = sources.indexWhere((e) => e.id == duplicate.id);
            }
            final old = sources[index];
            final targetId = old.id;
            final hash = sha256.convert(utf8.encode(markdown)).toString();
            final versions = [...old.versions];
            versions.add(
              SourceVersion(
                version: versions.fold<int>(0, (n, v) => n > v.version ? n : v.version) + 1,
                snapshotFile: file,
                hash: hash,
              ),
            );
            sources[index] = ResearchSource.fromJson({
              ...old.toJson(),
              'title': content.title,
              'canonicalUrl': canonical,
              'readState': ResearchReadState.fullText.name,
              'fetchedAt': now().toIso8601String(),
              'versions': versions.map((v) => v.toJson()).toList(),
            });
            metadata[targetId] = {
              ...(metadata[targetId] as Map? ?? {}),
              'error': null,
              'versions': {
                ...((metadata[targetId] as Map?)?['versions'] as Map? ?? {}),
                '${versions.last.version}': {
                  'fetchedAt': now().toIso8601String(),
                  'readState': ResearchReadState.fullText.name,
                },
              },
            };
            final evidence = [...current.evidence];
            final version = versions.last.version;
            for (final quote in ((metadata[targetId] as Map?)?['candidateQuotes'] as List? ?? []).cast<String>()) {
              for (final paragraph in content.paragraphs.entries) {
                if (quote.isEmpty || !paragraph.value.contains(quote)) continue;
                final evidenceId = sha256
                    .convert(utf8.encode(jsonEncode([targetId, version, paragraph.key, quote])))
                    .toString();
                if (!evidence.any((e) => e.id == evidenceId)) {
                  evidence.add(
                    Evidence(
                      id: evidenceId,
                      sourceId: targetId,
                      sourceVersion: version,
                      quote: quote,
                      locator: EvidenceLocator.paragraph(paragraph.key),
                      acquisition: EvidenceAcquisition.auto,
                      capturedAt: now(),
                    ),
                  );
                }
                break;
              }
            }
            return _data(patchSession(s, {'sourceIds': sources.map((s) => s.id).toList()}), {
              'sources': sources.map((s) => s.toJson()).toList(),
              'metadata': metadata,
              'evidence': evidence.map((e) => e.toJson()).toList(),
            });
          }, token: token);
        } catch (error) {
          await _write((s) {
            final current = ResearchSessionState(s);
            final metadata = {...current.metadata};
            metadata[id] = {
              ...(metadata[id] as Map? ?? {}),
              'error': error is TimeoutException
                  ? 'timeout'
                  : error is ResearchFailure
                  ? error.code ?? error.kind.name
                  : 'unavailable',
            };
            return _data(s, {
              'metadata': metadata,
              'sources': [
                for (final e in current.sources)
                  e.id == id ? {...e.toJson(), 'readState': ResearchReadState.failed.name} : e.toJson(),
              ],
            });
          }, token: token);
        } finally {
          child.cancel();
        }
      }
    });
  }

  /// Link-only sources never produce snapshots or evidence. The video's own
  /// title is looked up once; without it the link is the title.
  Future<void> saveVideoLink(Uri url) async {
    final link = videoSource(url, now());
    final title = await videoTitles?.lookup(link, CancellationToken());
    final source = title == null ? link : ResearchSource.fromJson({...link.toJson(), 'title': title});
    await _write((s) {
      final current = ResearchSessionState(s);
      final sources = [...current.sources];
      mergeSource(sources, source);
      return _data(patchSession(s, {'sourceIds': sources.map((s) => s.id).toList()}), {
        'sources': sources.map((s) => s.toJson()).toList(),
      });
    });
  }

  /// The question as the user rewrote it; later requests ask it.
  Future<void> rename(String question) async {
    final text = question.trim();
    if (text.isEmpty) throw ArgumentError.value(question, 'question');
    await recovery.ready;
    await _write((s) => patchSession(s, {'question': text}));
  }

  /// Text the user pasted for a source that could not be read: a new
  /// snapshot version recorded in `metadata[sourceId].pasted`, so evidence
  /// from it is marked as user-supplied rather than extracted.
  Future<void> pasteSource(String sourceId, String text) async {
    final blocks = [
      for (final block in text.split(RegExp(r'\n\s*\n')))
        if (block.trim().isNotEmpty) block.trim(),
    ];
    if (blocks.isEmpty) throw ArgumentError.value(text, 'text');
    await recovery.ready;
    final source = state.sources.where((s) => s.id == sourceId).firstOrNull;
    if (source == null) throw ArgumentError.value(sourceId, 'sourceId');
    final content = markdownArticle(
      ReadableHtml(
        url: Uri.parse(source.url),
        title: source.title,
        html: blocks.map((b) => '<p>${htmlEscape.convert(b)}</p>').join(),
      ),
    );
    final markdown = encodeSnapshot(content.paragraphs);
    final file = await snapshots.writeResearchSnapshot(studySetId, markdown);
    final hash = sha256.convert(utf8.encode(markdown)).toString();
    await _write((s) {
      final current = ResearchSessionState(s);
      final sources = [...current.sources];
      final index = sources.indexWhere((e) => e.id == sourceId);
      if (index < 0) return s;
      final versions = [...sources[index].versions];
      var version = versions.where((v) => v.hash == hash).firstOrNull;
      if (version == null) {
        version = SourceVersion(
          version: versions.fold<int>(0, (n, v) => n > v.version ? n : v.version) + 1,
          snapshotFile: file,
          hash: hash,
        );
        versions.add(version);
      }
      sources[index] = ResearchSource.fromJson({
        ...sources[index].toJson(),
        'readState': ResearchReadState.fullText.name,
        'fetchedAt': now().toIso8601String(),
        'versions': versions.map((v) => v.toJson()).toList(),
      });
      final metadata = {...current.metadata};
      final previous = (metadata[sourceId] as Map? ?? {}).cast<String, Object?>();
      metadata[sourceId] = {
        ...previous,
        'error': null,
        'pasted': {...(previous['pasted'] as List? ?? []), version.version}.toList(),
      };
      return _data(s, {'sources': sources.map((e) => e.toJson()).toList(), 'metadata': metadata});
    });
  }

  Future<void> dispose() async {
    await cancel();
    _disposed = true;
    await _changes.close();
  }
}
