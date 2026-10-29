# GUL-572 validation

For subsequent theme, image-budget and controller-geometry fixes, see
[review validation](review.md). The measurements below retain their original baseline.

Baseline: `7aa0c27`. Flutter 3.47.2 / Dart 3.13.2 / engine a804b26164.
Linux ARM64, Ubuntu 24.04.5, shared Oracle host (4 × Neoverse-N1 cores). The native release probe runs
under Xvfb with Mesa software rendering; it is not an Android/GPU result.

Reproduction from the repository root:

```bash
python3 docs/evidence/gul-570/fetch_books.py
flutter pub get
(cd packages/mm_reflow/example && flutter build linux --release --no-pub --dart-define=BENCHMARK=true)
xvfb-run -a python3 docs/evidence/gul-572/run_linux.py
python3 docs/evidence/gul-572/summarize.py
xvfb-run -a python3 docs/evidence/gul-572/cold_starts.py
dart run packages/mm_reflow/tool/contract_probe.dart > docs/evidence/gul-572/contract-probe.json
```

The three original EPUBs use GUL-570's pinned hashes and licenses. The probe now
calls the asynchronous production engine with caching disabled for measurements;
two warmups then 30 measured repeats at widths 320/768/1200 and fonts 16/22.
It reports total elapsed time (including scheduling waits), active work time and
maximum uninterrupted batch separately. Cold/hot image loading and real rendered
page changes still use the original probe. Native FrameTiming covers 200 flips
per cold/hot state per book. Five rounds of ten chapter switches per book sample
settled PSS/RSS without forcing GC. Synthetic long-chapter, single-paragraph and
100,000×100,000 intrinsic-image cases are reported separately, not represented as
real books or folded into normal-chapter results. The huge intrinsic-image case
measures layout; the decode pixel cap is independently covered by mm_design tests.

`linux.jsonl.gz` retains the raw events. `chapters.csv` retains every measured
chapter/width/font group. `summary.json` summarizes those events; timing failures
are not filtered. `linux-stderr.log` is a local diagnostic and not committed.
PSS is sampled approximately once per second and at each settled switching round;
the sampled peak is not a guarantee of the process's instantaneous peak. The
probe's legacy `decode` event times chapter decode **and layout**, not an isolated
decoder or font-loading operation.

Final run: 55 chapters × 3 widths × 2 font sizes × 30 repeats = **9,900**
measured layouts. Every chapter/parameter group's total-time p95 is below 100ms:

| Original EPUB | Chapters | Worst group p95, total | Worst group p95, active work | Maximum batch |
| --- | ---: | ---: | ---: | ---: |
| 7337 — 道德经 | 3 | 26.545ms | 24.096ms | 8.319ms |
| 33283 — Calculus Made Easy | 37 | 99.714ms | 86.734ms | 11.380ms |
| 28885 — Alice's Adventures in Wonderland | 15 | 30.057ms | 23.371ms | 8.648ms |

The worst final group is Calculus chapter index 23, width 320, font 22:
23,486 UTF-16 units, 181 blocks, 305 decoded image handles and four tables.
Its p50/p95/max are 53.334/99.714/103.848ms; the margin to the p95 target is small.
The `*-before-index.*` artifacts retain the initial complete run, whose Calculus
worst p95 was **168.775ms**. After that failure, link-anchor creation changed from
repeated grapheme-prefix scans to one lazy per-chapter boundary index and binary
lookup. Both runs use the same full sampling parameters; shared-host variability
also affects the comparison. No failing sample was discarded within either run.

The separate synthetic p95s are 376.393ms for the 500-paragraph long chapter,
151.261ms for the 42,000-unit single paragraph, and 0.019ms for the huge-image
layout (60 samples each, combining fonts 16 and 22). The longest uninterrupted
single-paragraph batch was **191.662ms**. The 4ms scheduler is cooperative, not a
hard latency bound; this remaining limitation must be considered by the reader.

The probe requested 1,200 page changes and captured 1,184 FrameTiming events
(chapter-load frames and page-change frames are not one-to-one). Xvfb reports
refresh rate **0**, so 60Hz is only an explicit comparison reference:

| State | Frames | Build p95 | Raster p95 | Over 16.667ms reference |
| --- | ---: | ---: | ---: | ---: |
| Cold | 568 | 2.262ms | 17.305ms | 5.81% |
| Hot | 616 | 2.316ms | 15.523ms | 4.38% |

The reference over-budget rate does **not** meet the architecture's <1% target.
These software-rendered Linux measurements do not establish an Android/device
performance Go decision. Device/GPU frame evidence and long-paragraph latency
remain outstanding even though normal-chapter p95 meets 100ms in this run.

All image-failure events and anchor-check failures were zero. Across each book's
five rounds / 50 chapter switches, settled PSS baseline → final was
256.92→256.75MiB (Chinese), 317.83→315.63MiB (Calculus), and
303.09→296.75MiB (Alice); no sustained growth appeared in these rounds.
The once-per-second sampled peak was 430.25MiB, 173.33MiB above the first settled
Chinese baseline, including the other books and synthetic stress. The initial
process-creation PSS in JSON is not a warmed baseline. Five fresh starts through
first-chapter parse/decode/layout took 376.513, 440.282, 360.888, 324.468 and
420.648ms; these are not first-paint measurements.

Validation on this baseline:

- `flutter analyze --no-pub`: no issues. `dart format --set-exit-if-changed apps packages`: 527 files, unchanged.
- `python3 -m unittest discover -s tool/tests`: 17 passed.
- All 12 package/application suites in `tool/coverage.py` were run with coverage.
  `mm_reflow`: 27 passed; probe: 2 passed; `mm_design`: 163 passed.
  The application run finished with 773 passed, 21 skipped and one existing
  wall-clock assertion failure: `mind_map_cache_test.dart`'s 500-node p95 was
  17.499ms against a 16ms limit while this shared host was compiling/testing.
  After this task's builds/tests stopped, a single isolated rerun of the entire
  file passed all 16 tests with p95 9.065ms; the threshold was not changed.
- `python3 tool/coverage.py --report-only`: 29,697/32,412 lines, **91.62%**.
  `coverage.md` retains the merged report (the mm_reflow row includes its example).
  The production mm_reflow library alone covers 757/775 lines (**97.68%**).
- Native Linux and Web probe Release builds passed. Web used
  `flutter build web --release --no-pub --no-wasm-dry-run`.

Current baseline dependency gaps are captured by `contract-probe.json`: mm_book
still omits container styles, table header identity and intrinsic resource sizes.
The engine tests both absence and supplied facts through the isolated
`LayoutResources` adapter. GUL-573's final domain types are also pending: the
approved temporary position boundary is a collapsed existing mm_book.TextAnchor.
No duplicate domain model or storage format has been introduced.

Environment limitations: no connected Android device/AVD was available in
`flutter devices`; Android profile/real-device evidence remains outstanding.
macOS native window tests cannot run on Linux and are delegated to repository CI,
as directed in the issue handoff. The separate cold-start harness measures five fresh processes through initial
EPUB parse/decode/layout, not first paint; it does not flush OS file caches. Extremely long individual paragraphs are a nonpreemptible
TextPainter operation; the scheduling budget is cooperative at leaf/cell boundaries.
