import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';

import '../../app/providers.dart';
import '../assistant/task_run_store.dart';

import 'package:path/path.dart' as p;

import '../assistant/assistant_settings.dart';
import '../assistant/assistant_services.dart';
import '../assistant/assistant_routing.dart';
import '../assistant/note_organizer_factory.dart';

/// Owns one cancellable model connection. Injectable with an ordinary fake port.
class NoteSession {
  NoteSession(this.organizer);
  final NoteOrganizer organizer;
  bool _closed = false;
  bool get usedFallback => false;
  Future<String> rewrite(String text, NoteRewrite mode) => (organizer as RuntimeNoteOrganizer).rewrite(text, mode);
  Future<String> reviewQuestion(NoteDraftSection section) =>
      (organizer as RuntimeNoteOrganizer).reviewQuestion(section);
  Future<String> explain(NoteMaterial material) => (organizer as RuntimeNoteOrganizer).explain(material);
  void close() {
    if (_closed) return;
    _closed = true;
    if (organizer case final RuntimeNoteOrganizer model) model.close();
  }

  Stream<NoteDraftSection> write(
    NoteMaterials materials,
    NoteOutline outline,
    NoteSettings settings,
    int startAt,
  ) async* {
    if (organizer case final RuntimeNoteOrganizer model) {
      yield* model.writeSections(materials, outline, settings, startAt: startAt);
    } else {
      final draft = await organizer.write(materials, outline, settings);
      yield* Stream.fromIterable(draft.sections.skip(startAt));
    }
  }
}

final noteSessionFactoryProvider =
    Provider<Future<NoteSession> Function({String? studySetId, String? sessionId, ModelReference? modelOverride})>((
      ref,
    ) {
      final tasks = studyNotesTaskRegistry();
      final sessions = <String, PersistentNoteStages>{};
      return ({studySetId, sessionId, modelOverride}) async {
        if (studySetId == null || studySetId.isEmpty) throw const ConfigurationFailure('persistentStudySetRequired');
        final directory = ref.read(contentRepositoryProvider).resolveFile(studySetId, '');
        if (!p.isAbsolute(directory)) throw const ConfigurationFailure('persistentStudySetRequired');
        final assembly = PersistentTaskAssembly(
          studySetDirectory: directory,
          tasks: tasks,
          services: ref.read(assistantServicesStoreProvider),
          routing: ref.read(assistantRoutingStoreProvider),
          profiles: ref.read(assistantCapabilityProfilesProvider),
          knowledge: VersionedKnowledgeRegistry([studyNotesKnowledge]),
        );
        final id = sessionId ?? newId();
        final key = '$studySetId:$id';
        final stages =
            sessions[key] ??
            await PersistentNoteStages.open(
              assembly,
              id,
              modelOverride: modelOverride,
              online: assistantOnlineDefault(ref, studySetId),
            );
        sessions[key] = stages;
        return NoteSession(RuntimeNoteOrganizer(stages));
      };
    });

final noteAiMarkersProvider = NotifierProvider.family<NoteAiMarkers, bool, String>(NoteAiMarkers.new);

class NoteAiMarkers extends Notifier<bool> {
  NoteAiMarkers(this.noteId);
  final String noteId;
  @override
  bool build() => ref.read(sharedPreferencesProvider).getBool('studyNotes.showAi.$noteId') ?? true;
  Future<void> toggle() async {
    state = !state;
    await ref.read(sharedPreferencesProvider).setBool('studyNotes.showAi.$noteId', state);
  }
}

/// A paused run keeps the same ID dictionary and validated completed sections.
class NoteContinuation {
  NoteContinuation({
    required this.setId,
    required this.title,
    required this.scope,
    required this.settings,
    required this.template,
    required this.materials,
    required this.outline,
    required this.draft,
    this.noteId,
    this.sessionId,
    this.modelOverride,
  });
  final String setId, title;
  final String? noteId;
  final String? sessionId;
  final ModelReference? modelOverride;
  final NoteScope scope;
  final NoteSettings settings;
  final NoteTemplate template;
  final NoteMaterials materials;
  final NoteOutline outline;
  final NoteDraft draft;
  Map<String, dynamic> toJson() => {
    'version': 1,
    'setId': setId,
    'title': title,
    'scope': scope.toJson(),
    'settings': settings.toJson(),
    'template': template.name,
    'noteId': noteId,
    'sessionId': sessionId,
    'modelOverride': modelOverride?.toJson(),
    'outline': outline.toJson(),
    'draft': draft.toJson(),
    'collectedAt': materials.collectedAt.toIso8601String(),
    'materials': [
      for (final m in materials.items)
        {
          ...m.toJson(),
          'sourceId': m.sourceId,
          'createdAt': m.createdAt.toIso8601String(),
          'documentId': m.documentId,
          'annotationId': m.annotationId,
          'branchKey': m.branchKey,
          'branchTitle': m.branchTitle,
          'mapOrder': m.mapOrder,
        },
    ],
  };
  factory NoteContinuation.fromJson(Map<String, dynamic> j) {
    if (j['version'] != 1) throw const FormatException('Note continuation version');
    return NoteContinuation(
      setId: j['setId'],
      title: j['title'],
      noteId: j['noteId'],
      sessionId: j['sessionId'],
      modelOverride: j['modelOverride'] == null
          ? null
          : ModelReference.fromJson(Map<String, dynamic>.from(j['modelOverride'])),
      scope: NoteScope.fromJson(Map<String, dynamic>.from(j['scope'])),
      settings: NoteSettings.fromJson(Map<String, dynamic>.from(j['settings'])),
      template: NoteTemplate.values.byName(j['template']),
      outline: NoteOutline.fromJson(Map<String, dynamic>.from(j['outline'])),
      draft: NoteDraft.fromJson(Map<String, dynamic>.from(j['draft'])),
      materials: NoteMaterials([
        for (final m in j['materials'])
          NoteMaterial(
            ref: m['id'],
            sourceId: m['sourceId'],
            text: m['text'],
            groupKey: m['group'],
            groupTitle: m['title'],
            source: m['source'] == 'highlight' ? null : OwnSource.values.byName(m['source']),
            origin: NoteOrigin.values.byName(m['origin']),
            createdAt: DateTime.parse(m['createdAt']),
            documentId: m['documentId'],
            annotationId: m['annotationId'],
            branchKey: m['branchKey'],
            branchTitle: m['branchTitle'],
            mapOrder: m['mapOrder'],
            context: NoteContext(
              before: m['context']['before'],
              after: m['context']['after'],
              fragment: m['context']['fragment'],
              noText: m['context']['noText'],
              unresolved: m['context']['unresolved'],
            ),
          ),
      ], collectedAt: DateTime.parse(j['collectedAt'])),
    );
  }
}

final noteContinuationsProvider = NotifierProvider<NoteContinuations, Map<String, NoteContinuation>>(
  NoteContinuations.new,
);

class NoteContinuations extends Notifier<Map<String, NoteContinuation>> {
  static const storageKey = 'studyNotes.continuations.v1';
  bool _unreadable = false;
  Future<void> _writes = Future.value();
  @override
  Map<String, NoteContinuation> build() {
    final raw = ref.read(sharedPreferencesProvider).getString(storageKey);
    if (raw == null) return {};
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return data.map((id, value) => MapEntry(id, NoteContinuation.fromJson(Map<String, dynamic>.from(value))));
    } catch (_) {
      _unreadable = true; // Never replace a corrupt/future archive with empty state.
      return {};
    }
  }

  Future<void> _save(Map<String, NoteContinuation> Function(Map<String, NoteContinuation>) change) {
    final write = _writes.then((_) async {
      if (_unreadable) throw const FormatException('Unreadable note continuations');
      final next = change(state);
      final prefs = ref.read(sharedPreferencesProvider);
      try {
        final saved = await prefs.setString(
          storageKey,
          jsonEncode(next.map((id, value) => MapEntry(id, value.toJson()))),
        );
        if (!saved) throw StateError('Note continuation save failed');
      } catch (_) {
        await prefs.reload();
        rethrow;
      }
      state = next;
    });
    _writes = write.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return write;
  }

  Future<void> put(NoteContinuation value) async {
    if (value.noteId != null) await _save((current) => {...current, value.noteId!: value});
  }

  Future<void> remove(String? id) => _save((current) => {...current}..remove(id));
}
