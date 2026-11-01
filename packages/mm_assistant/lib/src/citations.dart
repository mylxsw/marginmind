import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:mm_core/mm_core.dart';

class Citation {
  const Citation({
    required this.marker,
    this.documentId,
    this.page,
    this.sourceId,
    this.version,
    this.paragraphId,
    this.url,
    this.quote = '',
    this.title = '',
    this.kind = '',
    this.fetchedAt,
    this.snapshotFile,
  });
  final String marker, quote, title, kind;
  final DateTime? fetchedAt;
  final String? snapshotFile;
  final String? documentId, sourceId, paragraphId, url;
  final int? page, version;
  String get evidenceId =>
      sha256.convert(utf8.encode(jsonEncode([documentId, page, sourceId, version, paragraphId, quote]))).toString();
  bool get external => sourceId != null;
  Map<String, dynamic> toJson() => {
    'marker': marker,
    'evidenceId': evidenceId,
    'documentId': documentId,
    'page': page,
    'sourceId': sourceId,
    'version': version,
    'paragraphId': paragraphId,
    'url': url,
    'quote': quote,
    'title': title,
    'kind': kind,
    'fetchedAt': fetchedAt?.toUtc().toIso8601String(),
    'snapshotFile': snapshotFile,
  };
  factory Citation.fromJson(Map<String, dynamic> j) => Citation(
    marker: j['marker'],
    documentId: j['documentId'],
    page: j['page'],
    sourceId: j['sourceId'],
    version: j['version'],
    paragraphId: j['paragraphId'],
    url: j['url'],
    quote: j['quote'] ?? '',
    title: j['title'] ?? '',
    kind: j['kind'] ?? '',
    fetchedAt: DateTime.tryParse(j['fetchedAt'] ?? ''),
    snapshotFile: j['snapshotFile'],
  );
}

/// Per-request view of a persistent evidence ledger. Search hits cannot register.
class CitationRegistry {
  CitationRegistry({this.primaryDocumentId, required this.online, this.persistentState}) {
    final saved = persistentState?['assistant.evidence.v1'] as Map?;
    if (saved != null) {
      _next = saved['next'] as int;
      for (final item in saved['items'] as List) {
        final citation = Citation.fromJson(Map<String, dynamic>.from(item));
        _items[citation.marker] = citation;
      }
    }
    _persist();
  }
  final Map<String, dynamic>? persistentState;
  void _persist() {
    persistentState?['assistant.evidence.v1'] = {'next': _next, 'items': items.map((c) => c.toJson()).toList()};
  }

  final String? primaryDocumentId;
  final bool online;
  final _items = <String, Citation>{};
  int _next = 1;
  List<Citation> get items => List.unmodifiable(_items.values);
  String page(ReadPage p) {
    final pageKey = '[page:${p.page}]';
    final previous = _items[pageKey];
    final key =
        p.documentId == primaryDocumentId &&
            (previous == null || (previous.documentId == p.documentId && previous.quote == p.text))
        ? pageKey
        : '[source:${_next++}]';
    _items[key] = Citation(marker: key, documentId: p.documentId, page: p.page, quote: p.text);
    _persist();
    return key;
  }

  List<String> source(AssistantSource s) {
    if (!online || s.version < 1 || s.paragraphs.isEmpty || !{'snapshot', 'openAlex'}.contains(s.kind)) {
      throw const ResearchFailure(ResearchFailureKind.invalidRequest);
    }
    return [for (final p in s.paragraphs.entries) _registerSource(s, p.key, p.value)];
  }

  String _registerSource(AssistantSource s, String paragraph, String text) {
    final key = '[source:${_next++}]';
    _items[key] = Citation(
      marker: key,
      sourceId: s.id,
      version: s.version,
      paragraphId: paragraph,
      url: s.url.toString(),
      quote: text,
      title: s.title,
      kind: s.kind,
      fetchedAt: s.fetchedAt,
      snapshotFile: s.snapshotFile,
    );
    _persist();
    return key;
  }

  String clean(String text) => text.replaceAllMapped(
    RegExp(r'\[(?:page|source):[^\]]*\]'),
    (m) => _items.containsKey(m[0]) && (online || !_items[m[0]]!.external) ? m[0]! : '',
  );
  List<Citation> used(String text) => List.unmodifiable(_items.values.where((c) => text.contains(c.marker)));
}

/// Holds incomplete bracket sequences so forged/split markers never flash in UI.
class CitationBuffer {
  CitationBuffer(this.registry);
  final CitationRegistry registry;
  String _pending = '';
  String add(String text) {
    _pending += text;
    final open = _pending.lastIndexOf('[');
    final cut = open > _pending.lastIndexOf(']') ? open : _pending.length;
    final out = registry.clean(_pending.substring(0, cut));
    _pending = _pending.substring(cut);
    return out;
  }

  String finish() {
    final out =
        RegExp(r'^\[(?:p(?:a(?:g(?:e(?::.*)?)?)?)?|s(?:o(?:u(?:r(?:c(?:e(?::.*)?)?)?)?)?)?)?$').hasMatch(_pending)
        ? ''
        : registry.clean(_pending);
    _pending = '';
    return out;
  }
}

ModelMessage withText(ModelMessage m, String text) => ModelMessage(
  model: m.model,
  textOutput: text,
  functionCalls: m.functionCalls,
  stopReason: m.stopReason,
  usage: m.usage,
  timestamp: m.timestamp,
  responseId: m.responseId,
  thought: m.thought,
  thoughtSignature: m.thoughtSignature,
  metadata: m.metadata,
  imageOutputs: m.imageOutputs,
  videoOutputs: m.videoOutputs,
  audioOutputs: m.audioOutputs,
  // Preserve protocol blocks (e.g. Claude tool_use) but sanitize text blocks.
  contentBlocks: [
    for (final b in m.contentBlocks)
      if (b['type'] != 'text') b else {...b, 'text': text},
  ],
);

class CitationHook extends AgentHook {
  CitationHook(this.registry) : buffer = CitationBuffer(registry);
  final CitationRegistry registry;
  final CitationBuffer buffer;
  @override
  ModelChunkHookResult onModelChunk(ModelChunkHookContext context) =>
      ModelChunkHookResult.proceed(withText(context.chunk, buffer.add(context.chunk.textOutput ?? '')));
  @override
  ModelResponseHookResult afterModelCall(ModelResponseHookContext context) {
    // Framework accumulates the sanitized chunks. Flush any ordinary bracket text.
    return ModelResponseHookResult.proceed(
      withText(context.response, registry.clean(context.response.textOutput ?? '') + buffer.finish()),
    );
  }
}
