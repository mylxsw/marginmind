# GUL-572 review validation

Review fixes on top of `ac683c4`, tested on 2026-10-29 with Flutter 3.47.2 /
Dart 3.13.2 on the same Linux ARM64 host as the original evidence.

- `LayoutSpec.readerStyle` participates in cache identity. Body ink, highlights
  and both inline/block image placeholders use its reader palette. Pixel tests
  cover white, dark, paper and green, including theme changes and cache reuse.
- Image admission throws `ImageBudgetExceeded(decodedPixels, budget)`.
  Tests verify its fields and a successful placeholder retry; the package README
  documents smaller decode limits, placeholders and image ownership.
- Controller `hitTest`, `boxes` and `reveal` forward page, local scroll and
  per-block horizontal offsets. Code/table tests check matching hit/selection
  geometry, transformed reveal carets and stale-generation rejection.

Validation after these changes:

| Check | Result |
| --- | --- |
| `flutter analyze --no-pub` | No issues |
| `dart format --set-exit-if-changed apps packages` | 528 files, unchanged |
| `python3 -m unittest discover -s tool/tests` | 17 passed |
| `python3 tool/coverage.py` | All 12 suites passed: 1,700 passed, 22 skipped |
| `mm_reflow` tests | 30 passed |
| Application suite | 774 passed, 21 skipped |
| Merged repository line coverage | 29,702 / 32,417 (91.62%) |
| Production `mm_reflow/lib` line coverage | 762 / 780 (97.69%) |
| Probe Linux Release build | Passed |
| Probe Web Release build | Passed |

Build commands, from `packages/mm_reflow/example`:

```bash
flutter build linux --release --no-pub --dart-define=BENCHMARK=true
flutter build web --release --no-pub --no-wasm-dry-run
```

The complete current coverage report is [review-coverage.md](review-coverage.md).
Its `mm_reflow` row includes the example; the production-only figure above
filters LCOV to `packages/mm_reflow/lib/`. The existing 500-node mind-map timing
test passed on its first run, p95 9.509ms against the unchanged 16ms limit.
macOS native window tests cannot run on this Linux host and remain assigned to CI.

The performance data in [README.md](README.md) and its raw artifacts belong to
the original `ac683c4` implementation; performance measurements were not rerun
for these contract fixes. Normal-chapter p95 was accepted by review. Android
profile evidence and the 191.662ms uninterrupted single-paragraph limit remain
follow-up work in GUL-576. Formal parser fields remain pending GUL-584, with
`LayoutResources` retained as the approved adapter.
