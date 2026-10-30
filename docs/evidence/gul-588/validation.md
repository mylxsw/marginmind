# GUL-588 validation

- `flutter analyze --no-pub`: no issues.
- `dart format --set-exit-if-changed apps packages`: 672 files, no changes.
- `python3 -m unittest discover -s tool/tests`: 26 passed.
- `python3 tool/coverage.py`: all 12 suites passed; merged coverage **91.51%** (38,937 / 42,548 lines). The design suite passed 174 tests. The app suite passed 975 tests; 34 existing conditional tests were skipped.
- `python3 tool/study_notes_evidence.py`: macOS integration scenario passed and captured the four native-window PNGs in this directory.
- In `apps/marginmind`: `xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug -destination 'platform=macOS' -enableCodeCoverage YES FLUTTER_TARGET=lib/main.dart`: 24 native tests passed. The explicit target resets the entry point after the integration test build.

Self-review covered the complete setup → organization → save → render → source navigation → edit/undo → export path, empty scopes, unavailable sources, export cancellation/failure, queued edits, timers and native resources, attachment path traversal/symlinks, and Chinese/English copy. Fixed narrow-window note visibility, touch-toolbar overflow, source text loading for menu/sidebar exports, and source citations exposing internal chapter IDs. Annotation-row regression tests now verify selection separately from source-link navigation; the taller map menu is scrolled before its actions are tested.

Review revision:

- Sources now group by document identity, with sorted unique PDF pages and one text-document entry. Missing source records keep an explicit status instead of an empty source title.
- The title uses `studyNote`; regular toolbar controls use labels and chevrons, while the compact More menu owns cascading TOC and layout submenus plus export.
- Quote citations include the 11pt source icon and chapter tooltip; own-note metadata includes the margin page or map-node title.
- Added three app widget cases and three shared menu cases. Self-review found and fixed sibling submenus remaining open together, and missing sources displaying empty book-title brackets. Checked source navigation, menu dismissal, disabled source links, null source records, page deduplication, localization, and narrow-window overflow.
- Re-ran the macOS integration scenario and refreshed all four screenshots; visually checked both note themes. Re-ran all 24 native tests successfully after restoring the application entry point.

Rebased onto main `98b4cca` (including GUL-589). The design index conflict retained both entries; the application changes in this revision are unchanged by the rebase. Analysis, formatting and all 12 coverage suites were rechecked successfully on the rebased tree; the totals above are from this final run.
