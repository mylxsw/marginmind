import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/workspace/workspace_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';

import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('written note save, edit and deletion use the persistent global undo stack', () async {
    final repo = InMemoryStudySetContentRepository({'demo-1': demoContent()});
    final container = ProviderContainer(overrides: await testOverrides(content: repo));
    addTearDown(container.dispose);
    container.listen(workspaceProvider('demo-1'), (_, _) {});
    await container.read(contentProvider('demo-1').future);
    final controller = container.read(workspaceProvider('demo-1').notifier);
    final now = DateTime.utc(2026, 10, 30);
    final annotation = controller.content.annotations.first;
    final note = StudyNote(
      id: 'written-note',
      title: 'Reading',
      scope: const WholeSet(),
      settings: NoteSettings(),
      createdAt: now,
      updatedAt: now,
      organizedAt: now,
      sections: [
        NoteSection(
          id: 's',
          title: 'Section',
          blocks: [
            QuoteBlock(id: 'q', annotationId: annotation.id),
            const TextBlock(id: 't', text: 'Original AI'),
          ],
        ),
      ],
    );
    await controller.saveStudyNote(note);
    expect((await repo.load('demo-1')).studyNote(note.id), isNotNull);
    await controller.editStudyNoteBlock(note.id, 't', text: 'My edit');
    final edited = (await repo.load('demo-1')).studyNote(note.id)!;
    expect(edited.sections.single.blocks.whereType<TextBlock>().single.origin, NoteOrigin.mixed);
    await controller.undo();
    expect(
      (await repo.load('demo-1')).studyNote(note.id)!.sections.single.blocks.whereType<TextBlock>().single.text,
      'Original AI',
    );
    await controller.redo();
    expect(
      (await repo.load('demo-1')).studyNote(note.id)!.sections.single.blocks.whereType<TextBlock>().single.text,
      'My edit',
    );
    await controller.removeDocument(annotation.documentId);
    expect(resolveNoteSource(await repo.load('demo-1'), annotation.id).status, NoteSourceStatus.documentRemoved);
    await controller.undo();
    expect(resolveNoteSource(await repo.load('demo-1'), annotation.id).status, NoteSourceStatus.available);
    await controller.deleteStudyNote(note.id);
    expect((await repo.load('demo-1')).studyNotes, isEmpty);
    await controller.undo();
    expect((await repo.load('demo-1')).studyNote(note.id), isNotNull);
  });
}
