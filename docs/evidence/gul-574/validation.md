# Validation, 2026-10-30

Pure Dart acceptance checks pass. Ora waived macOS native testing for this task
in issue comment 01a188b2-df61-777b-aab2-b06e3e7534d5 (2026-10-29 17:26 UTC),
because the change touches no native code or plugin registration.

| Check | Result |
| --- | --- |
| `flutter analyze` | Exit 0, no issues (final source) |
| `dart analyze packages/mm_book` | Exit 0, no issues |
| `dart format --set-exit-if-changed apps packages` | Exit 0, 519 files unchanged |
| `python3 -m unittest discover -s tool/tests` | Exit 0, 17 passed |
| `python3 tool/coverage.py` | Exit 0, all 12 Dart/Flutter suites passed; app 774 passed / 21 skipped |
| mm_book `dart test --coverage=coverage` | Exit 0, final 36 tests passed; coverage directory cleared before final collection |
| mm_book `dart run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --report-on=lib` | Exit 0 |
| mm_book `CHROME_EXECUTABLE=... dart test --platform chrome` | Exit 0, 36 tests passed in Chrome (dart2js) |
| `python3 tool/coverage.py --report-only` | Exit 0, refreshed with final mm_book report |
| `git diff --check` | Exit 0 |
| External samples through `tool/inspect_book.dart` | All 7 parsed; source hashes and summaries in samples.json |

The full-suite run exercised mm_core, mm_book, mm_reflow, its example,
mm_research, mm_assistant, mm_layout, mm_data, mm_design, mm_platform, mm_pdf
and the app. After the Markdown review fixes, all 12 suites were run again,
along with the final 36 mm_book Chrome tests, analyze and format. The merged
coverage below comes from this full rerun, with coverage directories cleared
by the coverage script before collection.

| Package | Covered / lines | Coverage |
| --- | ---: | ---: |
| apps/marginmind | 17618 / 19799 | 88.98% |
| packages/mm_assistant | 1606 / 1659 | 96.81% |
| packages/mm_book | 968 / 1031 | 93.89% |
| packages/mm_core | 3318 / 3401 | 97.56% |
| packages/mm_data | 441 / 455 | 96.92% |
| packages/mm_design | 1912 / 2049 | 93.31% |
| packages/mm_layout | 165 / 165 | 100.00% |
| packages/mm_pdf | 1789 / 1876 | 95.36% |
| packages/mm_platform | 200 / 216 | 92.59% |
| packages/mm_reflow | 425 / 459 | 92.59% |
| packages/mm_research | 637 / 655 | 97.25% |
| **Total** | **29079 / 31765** | **91.54%** |

Required: 80%.

## Native verification (waived by Ora)

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

Ora confirmed that the LaunchServices issue is unrelated to this pure Dart
change and waived this check. No macOS source or plugin registration changed.
The final handoff therefore proceeds to ready / in_review, with the attempted
native commands and their incomplete results retained above.

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

## Markdown review follow-up

The previous Markdown adapter incorrectly applied EPUB archive-root rules to
image source paths. It now passes normalized paths relative to the selected
Markdown file directory to the caller-bound resolver, including literal `../`
references. Absolute and relative SourceBytes names use the same resolver
contract. Imported images and their HTML references use independent hashed
`images/` keys; source paths never become storage keys.

Unsafe paths, missing files, resolver exceptions and images exceeding the
resource byte budget retain placeholders with diagnostics. A bad image cannot
reject the entire document; explicit cancellation still aborts the parse.
Percent-encoded traversal/separators, backslashes, NUL and malformed URL/UTF-8
encoding are rejected before a resolver call. Invalid percent decoding can
raise ArgumentError in Dart; it is converted into an image-path diagnostic.
Resolver exception details are not included in diagnostics.

Nine new regression tests cover relative/absolute/POSIX/Windows source names,
parent-directory aliases and deduplication, unsafe image paths, partial read
failures, encoded spaces/resource limits, and cancellation on resolver failure.
Self-review checked source-directory binding versus stored-resource naming,
all image failure branches, immutable resource copying and unaffected EPUB
archive path restrictions. The optional MOBI malformed-UTF8 suggestion was
left outside this Markdown correction.
