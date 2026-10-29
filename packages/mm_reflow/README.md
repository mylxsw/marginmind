# mm_reflow

Flutter book layout over `mm_book` canonical UTF-16 text. The engine has no network,
file storage, font loader or image decoder. UI integrations own those resources.

```dart
final engine = ReflowEngine();
final generation = engine.invalidate();
final layout = await engine.layout(chapter, spec, generation,
  revision: book.revision,
  resources: LayoutResources(images: decodedImages));
final position = layout.hitTest(point, page: page);
final geometry = layout.boxes(anchor, page: page);
layout.paint(canvas, page: page, highlight: anchor);
layout.dispose();
engine.dispose(); // Release cache leases before disposing decodedImages.
```

`LayoutSpec` includes viewport dimensions, insets, font size, line height, family,
font-resource digest, locale, direction, text scale, ink color and engine version.
Await font loading before layout; change the digest on successful load or fallback.
Reader typography and ink override publisher body sizes, line spacing and colors;
relative font sizes remain proportional. The same chapter geometry serves both
continuous scrolling and pagination. Omitting `page` selects chapter coordinates;
`toPage` / `toChapter` explicitly convert page viewport coordinates.

`ReflowController.layout` increments generation immediately, remembers the viewport's
source position and fraction within the line, then publishes only the latest result.
Its `hitTest`, `boxes`, `reveal` and `selectionChanged` reject stale generations.
The controller owns its engine and current layout. A layout returned by the controller
is borrowed until the next replacement; do not dispose it separately. Direct engine
results are caller-owned leases. `ReflowSurface.activeGeneration` can reject pointer
callbacks while a new layout is pending. Cross-chapter selection is an ordered list
of existing anchors supplied by the reading UI; this package does not own its gestures.

**Temporary position boundary:** GUL-573's domain types have not landed on the
baseline. Per the architecture owner's approved fallback, `hitTest` and `reveal`
use collapsed `mm_book.TextAnchor` values (`start == end`) as positions. No second
anchor or persistent position model exists in this package. This boundary must
switch to the final `mm_core` position/anchor types when GUL-573 lands.

Text is shaped once per leaf/cell. Pages clip those paragraphs at line boundaries;
rows joined by rowspan remain an indivisible group. Oversized groups expose
`PageSlice.scrollExtent`; the UI supplies `localScroll` to paint and geometry queries.
Code preserves whitespace and its natural line width. `LayoutPiece.contentWidth`
and `viewport` expose horizontal overflow; pass per-block `horizontalOffsets` to
`paint`, `boxes` and `hitTest` for local horizontal scrolling. Repeated headers are
paint-only copies, not additional canonical text or selection boxes. Bidi selection
rectangles remain separate. Hit testing snaps to grapheme boundaries, including
surrogates, combining marks and ZWJ sequences. Ruby is displayed in parentheses but
excluded from anchored selection rectangles. `links` exposes link/footnote ranges;
`target` resolves same-chapter fragments without executing navigation.

The typesetter consumes nested structure, relative font styles, decorations,
alignment, indent, whitespace, margins/padding, width/max-width and page breaks.
Chapter viewport metadata plus absolute block boxes are consumed as a fixed page,
scaled uniformly along with its text geometry. Unsupported publisher positioning
outside fixed pages follows normal block flow. The parser remains responsible for
CSS cascade and diagnostics; missing parser facts cannot be reconstructed here.

`LayoutResources` isolates three remaining GUL-574 IR gaps: container styles by
source path, repeated header-row counts by table block ID, and intrinsic image
sizes by resource path. Defaults are respectively no container box, no repeated
header, and bounded image placeholders. Supplying these facts exercises the same
layout paths that the future typed IR adapter will use. `imagesReady` permits one
batched late-dimension correction per generation and restores the source bookmark.
Change the resource revision when metadata changes. Decoded image identity also
participates in cache validation, so a replacement handle cannot reuse old artwork.

Layout yields to the event queue after approximately 4ms of work between leaf/cell
shaping operations. The requested visible leaf is measured first, followed by its
neighbours; the completed chapter is placed in source order. A single TextPainter
shape cannot be preempted, so very long individual paragraphs may exceed that budget.
`workTime`, `maxBatchTime` and the benchmark's total elapsed time distinguish work
from scheduler waiting. Current delivery is whole-chapter publication, not partial
geometry publication. Cache entries hold at most three layouts and an estimated
32MiB by default; an oversized chapter is returned uncached. Leases keep active
painters alive after eviction. Image storage is separate: admission defaults to
16 million pixels per chapter, and `MMBookImage.decode(maxPixels: ...)` bounds
raster allocation before decode. Evict/cache-clear and release all leases before
releasing borrowed image handles.

Tests: `flutter test --coverage` in this package. The original three-book probe is
in `example/`; Linux reproduction and measured limitations are under
`docs/evidence/gul-572/`. The synchronous `ChapterLayout.layout` factory is retained
for deterministic tests and offline probes; interactive readers use the async engine.
