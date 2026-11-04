/// Local immutable chunk cache only; excludes original package files and the
/// private recovery journal. Historical and unaccepted references remain pinned.
class SyncCacheUsage {
  const SyncCacheUsage({
    required this.bytes,
    required this.chunks,
    required this.reclaimableBytes,
    required this.reclaimableChunks,
    required this.canReclaim,
    this.staging = false,
    this.incompleteHistory = false,
    this.reclaimedBytes = 0,
  });
  final int bytes, chunks, reclaimableBytes, reclaimableChunks, reclaimedBytes;
  final bool canReclaim, staging, incompleteHistory;
}
