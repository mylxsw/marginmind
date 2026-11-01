import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/assistant/assistant_settings.dart';
import 'package:marginmind/features/assistant/assistant_routing.dart';
import 'package:marginmind/features/assistant/quick_tasks.dart';
import 'package:marginmind/features/workspace/word_lookup.dart';
import 'package:mm_core/mm_core.dart';
import 'package:marginmind/app/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'assistant_settings_test.dart' show Secrets;

import '../../../packages/mm_assistant/test/word_lookup_test.dart' as fixture;

void main() {
  test('lookup factory uses scoped quick executor and invalidates memory cache', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var calls = 0;
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        assistantSecretsProvider.overrideWithValue(Secrets()),
        quickTaskExecutorProvider('study').overrideWithValue((type, input, cancel) async {
          calls++;
          expect(type, TaskType.wordLookup);
          return jsonEncode(fixture.value());
        }),
      ],
    );
    addTearDown(container.dispose);
    await container.read(assistantRoutingProvider.future);
    final service = container.read(wordLookupProvider('study'));
    for (var i = 0; i < 2; i++) {
      await service.lookup(
        term: 'plateau',
        sentence: 'Progress plateaus.',
        targetLanguage: 'zh',
        model: null,
        cancel: CancellationToken(),
      );
    }
    expect(calls, 1);
    container.read(assistantKeysProvider.notifier).changed();
    expect(container.read(wordLookupProvider('study')), isNot(same(service)));
  });
}
