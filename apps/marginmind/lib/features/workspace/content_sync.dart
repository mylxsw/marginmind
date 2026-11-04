import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';

import '../../app/providers.dart';

final contentSyncProvider = StreamProvider.autoDispose.family<ContentSyncStatus, String>((ref, id) {
  final repository = ref.watch(contentRepositoryProvider);
  return repository is ContentSyncRepository
      ? (repository as ContentSyncRepository).watchContentSync(id)
      : Stream.value(ContentSyncStatus());
});
