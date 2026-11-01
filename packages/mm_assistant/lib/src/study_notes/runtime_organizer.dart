import 'dart:convert';

import 'package:mm_core/mm_core.dart';

import 'organizer.dart';

/// The application owns frozen routing, durable stages and explicit recovery.
abstract interface class NoteStageExecutor {
  int get requestCharacters;
  String get model;
  Future<Map<String, dynamic>> execute(String operation, Map<String, dynamic> data, CancellationToken cancel);
  Future<void> finish(Set<String> covered, Set<String> missing);
}

/// Domain assembly stays separate from runtime and from the confirmed write.
class RuntimeNoteOrganizer implements NoteOrganizer {
  RuntimeNoteOrganizer(this.executor);
  final NoteStageExecutor executor;
  final cancelToken = CancellationToken();
  final _completed = <NoteDraftSection>[];
  List<NoteDraftSection> get completedSections => List.unmodifiable(_completed);
  void close() => cancelToken.cancel();

  List<Map<String, dynamic>> _pieces(NoteMaterials materials) {
    final limit = executor.requestCharacters ~/ 3;
    if (limit < 256) throw const ConfigurationFailure('noteRequestCapacity');
    final result = <Map<String, dynamic>>[];
    for (final material in materials.items) {
      final item = Map<String, dynamic>.from(material.toJson());
      // Split the full encoded payload, including context. Original materials
      // remain untouched; every fragment carries the same stable source ID.
      final text = material.text;
      final before = material.context.before, after = material.context.after;
      final content = '$before$text$after';
      final runes = content.runes.toList();
      final metadata = {
        ...item,
        'text': '',
        'context': {
          'fragment': material.context.fragment,
          'noText': material.context.noText,
          'unresolved': material.context.unresolved,
        },
        'quoteStart': before.runes.length,
        'quoteEnd': before.runes.length + text.runes.length,
      };
      final room = limit - jsonEncode(metadata).length - 256;
      if (room < 1) throw const ConfigurationFailure('noteMetadataCapacity');
      var offset = 0;
      do {
        var end = (offset + room ~/ 6).clamp(offset + 1, runes.length.clamp(1, 1 << 30));
        final fragment = runes.isEmpty ? '' : String.fromCharCodes(runes.sublist(offset, end));
        result.add({...metadata, 'text': fragment, 'fragment': offset, 'complete': end >= runes.length});
        offset = end;
      } while (offset < runes.length);
    }
    return result;
  }

  List<List<Map<String, dynamic>>> _batches(NoteMaterials materials, Map<String, dynamic> extra) {
    final result = <List<Map<String, dynamic>>>[];
    var batch = <Map<String, dynamic>>[];
    for (final item in _pieces(materials)) {
      final next = [...batch, item];
      final duplicate = batch.any((m) => m['id'] == item['id']);
      if (batch.isNotEmpty &&
          (duplicate || jsonEncode({...extra, 'materials': next}).length > executor.requestCharacters)) {
        result.add(batch);
        batch = [];
      }
      batch.add(item);
      if (jsonEncode({...extra, 'materials': batch}).length > executor.requestCharacters) {
        throw const ConfigurationFailure('noteRequestCapacity');
      }
    }
    if (batch.isNotEmpty) result.add(batch);
    return result;
  }

  Future<Map<String, dynamic>> _call(String operation, Map<String, dynamic> data) {
    cancelToken.check();
    if (jsonEncode(data).length > executor.requestCharacters) throw const ConfigurationFailure('noteRequestCapacity');
    return executor.execute(operation, data, cancelToken);
  }

  @override
  Future<NoteOutline> outline(NoteMaterials materials, NoteSettings settings) async {
    if (settings.depth == NoteDepth.none || settings.effectiveOrganization != NoteOrganization.theme) {
      return const LocalNoteOrganizer().outline(materials, settings);
    }
    final sections = <NoteOutlineSection>[];
    final seen = <String>{};
    final extra = <String, dynamic>{'settings': settings.toJson()};
    for (final batch in _batches(materials, extra)) {
      final result = NoteOutline.fromJson(await _call('outline', {...extra, 'materials': batch}));
      for (final section in result.sections) {
        final refs = section.refs.where(seen.add).toList();
        if (refs.isNotEmpty) sections.add(NoteOutlineSection(title: section.title, why: section.why, refs: refs));
      }
    }
    // Never fan all material text back into an unbounded merge request. The
    // editable outline preserves the thematic groups from every bounded stage.
    return NoteOutline(sections);
  }

  @override
  Future<NoteDraft> write(NoteMaterials materials, NoteOutline outline, NoteSettings settings) async =>
      NoteDraft(await writeSections(materials, outline, settings).toList());

  Stream<NoteDraftSection> writeSections(
    NoteMaterials materials,
    NoteOutline outline,
    NoteSettings settings, {
    int startAt = 0,
  }) async* {
    _completed.clear();
    final sections = outline.sections.where((s) => s.refs.isNotEmpty).toList();
    if (startAt < 0 || startAt > sections.length || sections.any((s) => s.refs.any((id) => materials[id] == null))) {
      throw const ResearchFailure(ResearchFailureKind.invalidRequest);
    }
    for (final (index, section) in sections.indexed) {
      if (index < startAt) continue;
      cancelToken.check();
      final selected = NoteMaterials(
        materials.items.where((m) => section.refs.contains(m.ref)).toList(),
        collectedAt: materials.collectedAt,
      );
      if (settings.depth == NoteDepth.none) {
        final draft = await const LocalNoteOrganizer().write(selected, NoteOutline([section]), settings);
        _completed.add(draft.sections.single);
        yield draft.sections.single;
        continue;
      }
      final extra = <String, dynamic>{
        'title': section.title,
        'sectionIndex': index,
        'sectionCount': sections.length,
        'settings': settings.toJson(),
      };
      final blocks = <NoteDraftBlock>[];
      final seen = <String>{};
      String? question;
      for (final batch in _batches(selected, extra)) {
        final draft = NoteDraft.fromJson(await _call('write', {...extra, 'materials': batch}));
        final part = draft.sections.single;
        for (final block in part.blocks) {
          if ((block.type == 'quote' || block.type == 'own') && !seen.add(block.ref!)) continue;
          blocks.add(block);
        }
        question ??= part.question;
      }
      final value = NoteDraftSection(title: section.title, why: section.why, blocks: blocks, question: question);
      _completed.add(value);
      yield value;
    }
    final covered = sections.expand((s) => s.refs).toSet();
    await executor.finish(covered, materials.items.map((m) => m.ref).toSet().difference(covered));
  }

  @override
  Future<NotePlacements> place(NoteMaterials materials, StudyNote note) async {
    if (note.settings.depth == NoteDepth.none) return const LocalNoteOrganizer().place(materials, note);
    final extra = <String, dynamic>{
      // No existing block text is offered for rewriting; anchors retain the
      // existing updater's revision, confirmation and undo semantics.
      'sections': [
        for (final s in note.sections) {'id': s.id, 'title': s.title, 'blocks': s.blocks.map((b) => b.id).toList()},
      ],
      'settings': note.settings.toJson(),
    };
    final placements = <NotePlacement>[];
    final seen = <String>{};
    for (final batch in _batches(materials, extra)) {
      final part = NotePlacements.fromJson(await _call('place', {...extra, 'materials': batch}));
      placements.addAll(part.items.where((p) => seen.add(p.ref)));
    }
    await executor.finish(seen, materials.items.map((m) => m.ref).toSet().difference(seen));
    return NotePlacements(placements);
  }

  Future<String> _text(String task, Map<String, dynamic> data) async {
    final value = (await _call('text', {'task': task, ...data}))['text'] as String;
    await executor.finish({'input'}, {});
    return value;
  }

  Future<String> explain(NoteMaterial material) async {
    final values = <String>[];
    final source = NoteMaterials([material], collectedAt: material.createdAt);
    for (final piece in _pieces(source)) {
      values.add(
        (await _call('text', {
              'task': 'Explain this source fragment, distinguishing context from inference.',
              'material': piece,
            }))['text']
            as String,
      );
    }
    await executor.finish({material.ref}, {});
    return values.join('\n\n');
  }

  Future<String> rewrite(String text, NoteRewrite mode) async {
    final runes = text.runes.toList();
    final room = executor.requestCharacters ~/ 8;
    if (room < 1) throw const ConfigurationFailure('noteRequestCapacity');
    final values = <String>[];
    for (var offset = 0; offset < runes.length; offset += room) {
      final part = String.fromCharCodes(runes.sublist(offset, (offset + room).clamp(0, runes.length)));
      values.add(
        (await _call('text', {'task': 'Rewrite generated prose: ${mode.name}.', 'text': part}))['text'] as String,
      );
    }
    if (values.isEmpty) throw const ResearchFailure(ResearchFailureKind.invalidRequest);
    await executor.finish({'input'}, {});
    return values.join('\n\n');
  }

  Future<String> reviewQuestion(NoteDraftSection section) =>
      _text('Write one grounded review question.', {'section': section.toJson()});
}
