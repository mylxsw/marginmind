# Validation, 2026-10-30

Code is available for review; acceptance remains blocked on macOS native verification.

| Check | Result |
| --- | --- |
| `flutter analyze` | Exit 0, no issues (final source) |
| `dart format --set-exit-if-changed apps packages` | Exit 0, 518 files unchanged |
| `python3 -m unittest discover -s tool/tests` | Exit 0, 17 passed |
| `python3 tool/coverage.py` | Exit 0, all 12 Dart/Flutter suites passed; app 774 passed / 21 skipped |
| mm_book `dart test --coverage=coverage` | Exit 0, final 27 tests passed; coverage directory cleared before final collection |
| mm_book `dart run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --report-on=lib` | Exit 0 |
| mm_book `CHROME_EXECUTABLE=... dart test --platform chrome` | Exit 0, 27 tests passed in Chrome (dart2js) |
| `python3 tool/coverage.py --report-only` | Exit 0, refreshed with final mm_book report |
| `git diff --check` | Exit 0 |
| External samples through `tool/inspect_book.dart` | All 7 parsed; source hashes and summaries in samples.json |

The full-suite run exercised mm_core, mm_book, mm_reflow, its example,
mm_research, mm_assistant, mm_layout, mm_data, mm_design, mm_platform, mm_pdf
and the app. Subsequent parser review fixes were rechecked with the final 27
mm_book VM/Chrome tests, analyze and format. The merged coverage below uses
the fresh final mm_book LCOV report, without stale pre-edit coverage JSON.

| Package | Covered / lines | Coverage |
| --- | ---: | ---: |
| apps/marginmind | 17618 / 19799 | 88.98% |
| packages/mm_assistant | 1606 / 1659 | 96.81% |
| packages/mm_book | 942 / 1005 | 93.73% |
| packages/mm_core | 3318 / 3401 | 97.56% |
| packages/mm_data | 441 / 455 | 96.92% |
| packages/mm_design | 1912 / 2049 | 93.31% |
| packages/mm_layout | 165 / 165 | 100.00% |
| packages/mm_pdf | 1789 / 1876 | 95.36% |
| packages/mm_platform | 200 / 216 | 92.59% |
| packages/mm_reflow | 425 / 459 | 92.59% |
| packages/mm_research | 637 / 655 | 97.25% |
| **Total** | **29053 / 31739** | **91.54%** |

Required: 80%.

## Native verification blocker

Executed from `apps/marginmind`:

```sh
xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner \
  -configuration Debug -destination 'platform=macOS' -enableCodeCoverage YES
```

The first run exited 65: generated FlutterInputs.xcfilelist and
FlutterOutputs.xcfilelist were absent. `flutter build macos --debug --config-only`
succeeded and generated them. The retry built the app but stalled for several
minutes at `RegisterWithLaunchServices` / `lsregister -f -R -trusted`.
Sampling its exact child PID showed directory enumeration in `getattrlistbulk`.
The built bundle contained 83 files with ordinary framework symlinks; no source
or build changes were made to the macOS project. That attempt was cancelled
(exit 75). A retry with `REGISTER_APP_WITH_LAUNCH_SERVICES=NO` still executed
the same registration command and stalled; it too was cancelled (exit 75).
Only the exact task-owned child processes were stopped. No daemon or system
service was restarted, and no native test pass is claimed.

Native acceptance must be completed on a working macOS test runner. The issue
stays blocked and the PR stays draft until Ora resolves this verification gap.

## Self-review

Reviewed the dispatch → adapter → IR chain, UTF-16 offsets/source maps/TOC and
byte-based MOBI links, malformed and encrypted input, size/record/recursion
limits, resource ownership, cancellation and serialization consistency.

Fixed during review: EXTH 121 points at the KF8 header (not the preceding
BOUNDARY record); ZIP CRC verification needs explicit checks rather than the
archive decoder's verify flag; inline containers must preserve one text block;
ruby must exclude script text; recursive HUFF phrase caches need an aggregate
byte bound; multi-PDF Print Replica must fail rather than omit later PDFs.
Regression cases cover these paths where locally constructible.

The library performs no I/O and cannot leave staging files. Resource buffers
are copied into immutable views; metadata and container lists are immutable.
Markdown resolvers never receive remote URLs; unsafe archive references and
active link schemes are rejected/removed. No secrets or external book binaries
were added. Persistence transactions remain GUL-573's responsibility.
