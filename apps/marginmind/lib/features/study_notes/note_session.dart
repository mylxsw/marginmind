import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';

import '../../app/providers.dart';
import '../assistant/assistant_services.dart';
import '../assistant/assistant_settings.dart';
import '../assistant/note_organizer_factory.dart';

/// Owns one cancellable model connection. Injectable with an ordinary fake port.
class NoteSession {
  NoteSession(this.organizer);
  final NoteOrganizer organizer;
  bool _closed = false;
  bool get usedFallback => organizer is ModelNoteOrganizer && (organizer as ModelNoteOrganizer).failures.isNotEmpty;
  Future<String> rewrite(String text, NoteRewrite mode) => (organizer as ModelNoteOrganizer).rewrite(text, mode);
  Future<String> reviewQuestion(NoteDraftSection section) => (organizer as ModelNoteOrganizer).reviewQuestion(section);
  Future<String> explain(NoteMaterial material) => (organizer as ModelNoteOrganizer).explain(material);
  void close() {
    if (_closed) return;
    _closed = true;
    if (organizer case final ModelNoteOrganizer model) model.close();
  }

  Stream<NoteDraftSection> write(
    NoteMaterials materials,
    NoteOutline outline,
    NoteSettings settings,
    int startAt,
  ) async* {
    if (organizer case final ModelNoteOrganizer model) {
      yield* model.writeSections(materials, outline, settings, startAt: startAt);
    } else {
      final draft = await organizer.write(materials, outline, settings);
      yield* Stream.fromIterable(draft.sections.skip(startAt));
    }
  }
}

final noteSessionFactoryProvider = Provider<Future<NoteSession> Function()>(
  (ref) =>
      () async => NoteSession(
        await createModelNoteOrganizer(
          services: ref.read(assistantServicesStoreProvider),
          secrets: ref.read(assistantSecretsProvider),
        ),
      ),
);

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
  });
  final String setId, title;
  final String? noteId;
  final NoteScope scope;
  final NoteSettings settings;
  final NoteTemplate template;
  final NoteMaterials materials;
  final NoteOutline outline;
  final NoteDraft draft;
}

final noteContinuationsProvider = NotifierProvider<NoteContinuations, Map<String, NoteContinuation>>(
  NoteContinuations.new,
);

class NoteContinuations extends Notifier<Map<String, NoteContinuation>> {
  @override
  Map<String, NoteContinuation> build() => {};
  void put(NoteContinuation value) {
    if (value.noteId != null) state = {...state, value.noteId!: value};
  }

  void remove(String? id) => state = {...state}..remove(id);
}
