import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/assistant/assistant_routing.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/study_notes/note_session.dart';
import 'package:mm_assistant/mm_assistant.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_core/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'assistant_settings_test.dart' show Secrets;
import 'note_organizer_factory_test.dart' show NotesFixture;
import 'helpers.dart';

class Repository extends InMemoryStudySetContentRepository {
  Repository(this.directory) : super({});
  final String directory;
  @override
  String resolveFile(String studySetId, String fileName) => directory;
}

void main() {
  test('production session requires persistent scope, uses routed runtime and closes idempotently', () async {
    final fixture = NotesFixture();
    await fixture.open();
    addTearDown(fixture.close);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance()),
        assistantSecretsProvider.overrideWithValue(Secrets()),
        contentRepositoryProvider.overrideWithValue(Repository(fixture.dir.path)),
        assistantCapabilityProfilesProvider.overrideWithValue(fixture.profiles),
      ],
    );
    addTearDown(container.dispose);
    await expectLater(container.read(noteSessionFactoryProvider)(), throwsA(isA<ConfigurationFailure>()));
    final session = await container.read(noteSessionFactoryProvider)(studySetId: 'set');
    final organizer = session.organizer as RuntimeNoteOrganizer;
    expect(session.usedFallback, isFalse);
    expect(await session.rewrite('prose', NoteRewrite.concise), 'validated');
    final settings = NoteSettings(depth: NoteDepth.none);
    final materials = const NoteMaterialCollector().collect(demoContent(), const WholeSet(), settings, now: testNow);
    final outline = await organizer.outline(materials, settings);
    final draft = await session.write(materials, outline, settings, 0).toList();
    expect(draft.single.blocks.single.ref, materials.highlights.single.ref);
    session.close();
    session.close();
    expect(organizer.cancelToken.isCancelled, isTrue);
  });
  test('paused note dictionary, hand material and completed sections survive provider restart', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    ProviderContainer open() => ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    final first = open();
    final settings = NoteSettings(depth: NoteDepth.context);
    final materials = const NoteMaterialCollector().collect(demoContent(), const WholeSet(), settings, now: testNow);
    final outline = await const LocalNoteOrganizer().outline(materials, settings);
    final draft = await const LocalNoteOrganizer().write(materials, outline, settings);
    await first
        .read(noteContinuationsProvider.notifier)
        .put(
          NoteContinuation(
            setId: 'set',
            title: 'Title',
            scope: const WholeSet(),
            settings: settings,
            template: NoteTemplate.reading,
            materials: materials,
            outline: outline,
            draft: draft,
            noteId: 'note',
            sessionId: 'stable-session',
          ),
        );
    first.dispose();
    final second = open();
    addTearDown(second.dispose);
    final restored = second.read(noteContinuationsProvider)['note']!;
    expect(restored.sessionId, 'stable-session');
    expect(restored.materials.items.single.sourceId, materials.items.single.sourceId);
    expect(restored.materials.items.single.text, materials.items.single.text);
    expect(restored.draft.toJson(), draft.toJson());
    await second.read(noteContinuationsProvider.notifier).remove('note');
    final third = open();
    addTearDown(third.dispose);
    expect(third.read(noteContinuationsProvider), isEmpty);
  });
}
