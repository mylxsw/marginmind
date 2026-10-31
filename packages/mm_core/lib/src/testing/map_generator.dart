import '../assistant/map_generation.dart';
import '../research/ports.dart';

/// Scripted raw lines exercise the same parser as the production adapter.
class FakeMapGenerator implements MapGenerator {
  FakeMapGenerator({
    Map<String, List<String>> chapters = const {},
    List<String> generation = const [],
    List<String> diff = const [],
    Map<String, ResearchFailure> chapterFailures = const {},
    this.generationFailure,
    this.diffFailure,
    this.delay = Duration.zero,
  }) : chapters = {for (final e in chapters.entries) e.key: List<String>.of(e.value)},
       generation = List.of(generation),
       diff = List.of(diff),
       chapterFailures = Map.of(chapterFailures);
  final Map<String, List<String>> chapters;
  final List<String> generation, diff;
  final Map<String, ResearchFailure> chapterFailures;
  ResearchFailure? generationFailure, diffFailure;
  final Duration delay;
  final calls = <String>[];
  bool closed = false;

  Stream<MapLine> _stream(
    String call,
    List<String> lines,
    MapLineContext context,
    CancellationToken cancel,
    ResearchFailure? failure,
  ) async* {
    if (closed) throw StateError('Generator closed');
    calls.add(call);
    cancel.check();
    for (final raw in lines) {
      await cancel.bind(Future<void>.delayed(delay));
      final line = parseMapLine(raw, context);
      if (line != null) yield line;
    }
    cancel.check();
    if (failure != null) throw failure;
  }

  @override
  Stream<MapLine> readChapter(MapChapterInput input, CancellationToken cancel) => _stream(
    'chapter:${input.chapterId}',
    chapters[input.chapterId] ?? [],
    input.context,
    cancel,
    chapterFailures[input.chapterId],
  );
  @override
  Stream<MapLine> generate(MapBuildInput input, CancellationToken cancel) =>
      _stream('generate', generation, input.context, cancel, generationFailure);
  @override
  Stream<MapLine> update(MapBuildInput input, CancellationToken cancel) =>
      _stream('update', diff, input.context, cancel, diffFailure);
  @override
  Future<void> close() async {
    closed = true;
  }
}
