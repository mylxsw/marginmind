import 'package:mm_sync/mm_sync.dart';

import 'file_library_store.dart';
import 'file_sync_ledger.dart';
import 'file_vocabulary_store.dart';

/// Dispatches a received batch through the live repositories sharing one ledger.
/// A partial projection is recoverable: receipts are durable and retry is
/// idempotent. This is not a transport or a cloud-delivery acknowledgement.
class FileSyncReceiver {
  const FileSyncReceiver(this.library, this.vocabulary);
  final FileLibraryStore library;
  final FileVocabularyStore vocabulary;
  Future<void> validateLedger(FileSyncLedger expected) async {
    await _check();
    if (!identical(expected, await library.syncLedger)) throw StateError('Wrong transport ledger');
  }

  Future<void> _check() async {
    final ledger = await library.syncLedger;
    if (ledger == null || !identical(ledger, await vocabulary.syncLedger)) {
      throw StateError('Sync receivers must share the library ledger instance');
    }
  }

  Future<void> receive(Iterable<SyncCommit> commits) async {
    await _check();
    await library.receiveSync(commits);
    await vocabulary.reconcileSync();
  }

  Future<void> retry() async {
    await _check();
    await library.reconcileSync();
    await vocabulary.retryVocabularySync();
  }
}
