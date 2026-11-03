import 'content_sync_repository.dart';
import 'text_anchor.dart';

enum ReadingContinuationAvailability { ready, documentChanged, unavailable }

class ReadingContinuation {
  const ReadingContinuation({
    required this.deviceId,
    this.deviceName,
    required this.documentId,
    required this.title,
    required this.remoteRevision,
    required this.localToken,
    required this.position,
    required this.readAt,
    required this.availability,
  });
  final String deviceId, documentId, title, remoteRevision, localToken;
  final String? deviceName;
  final ReadingPosition position;
  final DateTime readAt;
  final ReadingContinuationAvailability availability;
}

class ReadingContinuations {
  ReadingContinuations({
    this.enabled = false,
    this.editing = false,
    Iterable<ReadingContinuation> items = const [],
    Iterable<ContentSyncProblem> problems = const [],
  }) : items = List.unmodifiable(items),
       problems = Set.unmodifiable(problems);
  final bool enabled, editing;
  final List<ReadingContinuation> items;
  final Set<ContentSyncProblem> problems;
}

/// Receiving progress never replaces this device's reading position. Preparing
/// a continuation validates the observed versions; only subsequent reader
/// navigation records a new local position through the usual reading port.
abstract interface class ReadingContinuationRepository {
  Future<ReadingContinuations> readingContinuations(String studySetId);
  Stream<ReadingContinuations> watchReadingContinuations(String studySetId);
  Future<ReadingPosition> prepareReadingContinuation(
    String studySetId,
    String deviceId,
    String documentId, {
    required String remoteRevision,
    required String localToken,
  });
}
