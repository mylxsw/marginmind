import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';

import '../../app/providers.dart';
import '../workspace/workspace_controller.dart';

String noteMaterialKey(NoteMaterial m) => '${m.source?.name ?? 'highlight'}:${m.sourceId}';

/// A single snapshot drives both the sidebar count and the update banner.
class NoteChanges {
  NoteChanges(this.materials, this.deleted);
  final NoteMaterials materials;
  final Set<String> deleted;
  int get highlights => materials.highlights.length;
  int get own => materials.items.length - highlights;
  int get count => materials.items.length + deleted.length;
  Set<String> get keys => {...materials.items.map(noteMaterialKey), ...deleted.map((id) => 'deleted:$id')};
}

NoteChanges collectNoteChanges(
  StudySetContent content,
  StudyNote note, {
  Set<String> ignored = const {},
  NoteTextSource text = const NoteTextSource(),
}) {
  final all = const NoteMaterialCollector().collect(
    content,
    note.scope,
    note.settings,
    now: DateTime.now(),
    text: text,
  );
  final used = {
    for (final section in note.sections)
      for (final block in section.blocks)
        if (block is QuoteBlock)
          'highlight:${block.annotationId}'
        else if (block is OwnBlock)
          '${block.source.name}:${block.sourceId}',
  };
  return NoteChanges(
    NoteMaterials(
      all.items
          .where(
            (m) =>
                m.createdAt.isAfter(note.organizedAt) &&
                !used.contains(noteMaterialKey(m)) &&
                !ignored.contains(noteMaterialKey(m)),
          )
          .toList(),
      collectedAt: all.collectedAt,
      catalog: all.catalog,
    ),
    {
      for (final section in note.sections)
        for (final block in section.blocks)
          if (block is QuoteBlock &&
              resolveNoteSource(content, block.annotationId).status == NoteSourceStatus.annotationDeleted &&
              !ignored.contains('deleted:${block.annotationId}'))
            block.annotationId,
    },
  );
}

final noteIgnoredUpdatesProvider = NotifierProvider.family<NoteIgnoredUpdates, Set<String>, (String, String)>(
  NoteIgnoredUpdates.new,
);

class NoteIgnoredUpdates extends Notifier<Set<String>> {
  NoteIgnoredUpdates(this.identity);
  final (String, String) identity;
  String get _key => 'studyNotes.ignored.${identity.$1}.${identity.$2}';
  @override
  Set<String> build() => ref.read(sharedPreferencesProvider).getStringList(_key)?.toSet() ?? {};
  Future<void> ignore(Set<String> keys) async {
    state = {...state, ...keys};
    await ref.read(sharedPreferencesProvider).setStringList(_key, state.toList());
  }
}

final noteChangesProvider = Provider.family<NoteChanges?, (String, String)>((ref, identity) {
  final content = ref.watch(workspaceContentProvider(identity.$1));
  final note = content?.studyNote(identity.$2);
  final ignored = ref.watch(noteIgnoredUpdatesProvider(identity));
  return content == null || note == null ? null : collectNoteChanges(content, note, ignored: ignored);
}, dependencies: [workspaceContentProvider]);

final noteUpdateRequestedProvider = NotifierProvider.family<NoteUpdateRequested, bool, String>(NoteUpdateRequested.new);

class NoteUpdateRequested extends Notifier<bool> {
  NoteUpdateRequested(this.noteId);
  final String noteId;
  @override
  bool build() => false;
  void request() => state = true;
  void consume() => state = false;
}
