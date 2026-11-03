import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/providers.dart';
import 'package:marginmind/features/library/library_controller.dart';
import 'package:mm_core/mm_core.dart';

void main() {
  test('a removed folder switches its active filter to Unfiled without clearing search', () async {
    final changes = StreamController<List<Folder>>();
    final container = ProviderContainer(overrides: [foldersProvider.overrideWith((ref) => changes.stream)]);
    container.listen(libraryViewProvider, (_, _) {});
    final controller = container.read(libraryViewProvider.notifier);
    changes.add([const Folder(id: 'folder', name: 'Name')]);
    await container.read(foldersProvider.future);
    controller.setFilter(const FolderFilter('folder'));
    controller.setSearch('term');
    changes.add([const Folder(id: 'folder', name: 'Renamed')]);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(libraryViewProvider).query.filter, const FolderFilter('folder'));
    changes.add([]);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(libraryViewProvider).query.filter, const FolderFilter(null));
    expect(container.read(libraryViewProvider).query.search, 'term');
    container.dispose();
    await changes.close();
  });
}
