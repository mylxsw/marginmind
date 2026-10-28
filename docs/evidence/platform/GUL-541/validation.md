# GUL-541 validation

Validated after syncing main at `e8cca98` on 2026-10-28.

| Check | Result |
| --- | --- |
| `flutter pub get --enforce-lockfile` | Passed; lockfile unchanged |
| `flutter analyze` | No issues |
| `dart format --set-exit-if-changed apps packages` | 354 files; no changes |
| `python3 -m unittest discover -s tool/tests` | 17 passed |
| `python3 tool/coverage.py` | All package suites passed; app: 518 passed, 8 existing skips |
| `flutter build ios --simulator --debug --no-pub` | Passed in separate copy with a generated runner |
| `git diff --check` | Passed |

| Package | Covered / lines | Coverage |
| --- | ---: | ---: |
| apps/marginmind | 12787 / 14564 | 87.80% |
| packages/mm_assistant | 1331 / 1376 | 96.73% |
| packages/mm_core | 2418 / 2487 | 97.23% |
| packages/mm_data | 402 / 414 | 97.10% |
| packages/mm_design | 1204 / 1318 | 91.35% |
| packages/mm_layout | 121 / 123 | 98.37% |
| packages/mm_pdf | 1050 / 1117 | 94.00% |
| packages/mm_platform | 180 / 191 | 94.24% |
| packages/mm_research | 637 / 655 | 97.25% |
| **Total** | **20130 / 22245** | **90.49%** |

Required: 80%.

Self-review covered the complete selection/menu/drag and excerpt paths, cancellation and multiple pointers, timer and overlay disposal, focus restoration, input changes, keyboard visibility, localization and security. Fixed route-induced pointer cancellation, Escape leaking into the assistant, multi-touch claiming the drag arena, and the selection button overlapping the map toolbar. No credentials or new external requests were introduced.

See [manual evidence and limitations](README.md).
