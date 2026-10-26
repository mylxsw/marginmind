import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_pdf/mm_pdf.dart';

import '../../app/providers.dart';
import '../../app/navigation.dart';

class ReviewSessionState {
  const ReviewSessionState({
    this.started = false,
    this.queue = const [],
    this.index = 0,
    this.revealed = false,
    this.reviewed = 0,
    this.forgotten = 0,
  });

  /// False until the content has loaded and the queue was built.
  final bool started;

  /// Card ids in session order. Cards rated "again" are appended once more.
  final List<String> queue;
  final int index;

  /// Whether the answer side is showing.
  final bool revealed;

  /// Ratings given, and how many of them were "again".
  final int reviewed;
  final int forgotten;

  String? get currentId => index < queue.length ? queue[index] : null;

  bool get finished => started && currentId == null;

  int get remaining => queue.length - index;

  ReviewSessionState copyWith({
    bool? started,
    List<String>? queue,
    int? index,
    bool? revealed,
    int? reviewed,
    int? forgotten,
  }) => ReviewSessionState(
    started: started ?? this.started,
    queue: queue ?? this.queue,
    index: index ?? this.index,
    revealed: revealed ?? this.revealed,
    reviewed: reviewed ?? this.reviewed,
    forgotten: forgotten ?? this.forgotten,
  );
}

/// One review session over a study set's due and new cards. The queue is
/// fixed when the session starts, so cards made meanwhile wait for the
/// next session. Ratings are saved immediately and are not undoable.
class ReviewSession extends Notifier<ReviewSessionState> {
  ReviewSession(this.studySetId);

  final String studySetId;
  String? mapId;

  @override
  ReviewSessionState build() {
    final route = ref.read(navigationProvider);
    mapId = route is ReviewRoute && route.studySetId == studySetId ? route.mapId : null;
    ref.listen(contentProvider(studySetId), (_, next) {
      final c = next.value;
      if (c != null && !state.started) state = _start(c);
    });
    final c = ref.read(contentProvider(studySetId)).value;
    return c == null ? const ReviewSessionState() : _start(c);
  }

  ReviewSessionState _start(StudySetContent c) {
    final now = ref.read(clockProvider)();
    return ReviewSessionState(started: true, queue: [for (final card in c.reviewQueue(now, mapId: mapId)) card.id]);
  }

  StudySetContent get content => ref.read(contentProvider(studySetId)).value ?? StudySetContent.empty;

  void reveal() {
    if (state.currentId != null) state = state.copyWith(revealed: true);
  }

  Future<void> rate(Rating rating) async {
    final id = state.currentId;
    if (id == null || !state.revealed) return;
    final editor = ref.read(editorProvider);
    await ref.read(contentRepositoryProvider).update(studySetId, (c) => editor.rate(c, id, rating));
    if (!ref.mounted) return;
    final again = rating == Rating.again;
    state = state.copyWith(
      queue: again ? [...state.queue, id] : null,
      index: state.index + 1,
      revealed: false,
      reviewed: state.reviewed + 1,
      forgotten: state.forgotten + (again ? 1 : 0),
    );
  }

  /// Skips a card that no longer exists (deleted while the session ran).
  void skipMissing() {
    final id = state.currentId;
    if (id != null && content.card(id) == null) state = state.copyWith(index: state.index + 1, revealed: false);
  }
}

final reviewSessionProvider = NotifierProvider.autoDispose.family<ReviewSession, ReviewSessionState, String>(
  ReviewSession.new,
);

/// The text of the page an untitled excerpt came from, which its card front
/// quotes around. Null when the file cannot be read (or PDFs are not
/// rendered), so the front falls back to the page thumbnail.
typedef PageContent = ({String text, double height});

final excerptPageTextProvider = FutureProvider.autoDispose.family<PageContent?, ({String studySetId, String cardId})>((
  ref,
  key,
) async {
  if (!ref.watch(pdfRenderingEnabledProvider)) return null;
  final content = ref.read(contentProvider(key.studySetId)).value;
  final card = content?.card(key.cardId);
  final annotation = card?.annotationId == null ? null : content!.annotation(card!.annotationId!);
  final doc = annotation == null ? null : content!.document(annotation.documentId);
  if (doc == null) return null;
  final path = ref.read(contentRepositoryProvider).resolveFile(key.studySetId, doc.fileName);
  return MMPdfEngine.pageContent(path, annotation!.page);
});
