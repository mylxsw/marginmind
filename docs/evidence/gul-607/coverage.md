GUL-607 validation

PR added executable lines: 872/920 (94.78%).
Review changes: 74/76 (97.37%).

| Source | Covered / added lines | Coverage |
| --- | ---: | ---: |
| `apps/marginmind/lib/app/app_commands.dart` | 13 / 13 | 100.00% |
| `apps/marginmind/lib/features/assistant/assistant_controller.dart` | 3 / 3 | 100.00% |
| `apps/marginmind/lib/features/assistant/assistant_writes.dart` | 3 / 3 | 100.00% |
| `apps/marginmind/lib/features/assistant/expansion_context.dart` | 69 / 69 | 100.00% |
| `apps/marginmind/lib/features/assistant/expansion_controller.dart` | 164 / 167 | 98.20% |
| `apps/marginmind/lib/features/assistant/widgets/assistant_quick_actions.dart` | 8 / 8 | 100.00% |
| `apps/marginmind/lib/features/assistant/widgets/expansion_widgets.dart` | 327 / 342 | 95.61% |
| `apps/marginmind/lib/features/workspace/widgets/map_pane.dart` | 70 / 80 | 87.50% |
| `apps/marginmind/lib/features/workspace/widgets/mind_map_cache.dart` | 17 / 17 | 100.00% |
| `apps/marginmind/lib/features/workspace/widgets/mind_map_canvas.dart` | 168 / 186 | 90.32% |
| `apps/marginmind/lib/features/workspace/widgets/outline_view.dart` | 1 / 1 | 100.00% |
| `apps/marginmind/lib/features/workspace/workspace_controller.dart` | 24 / 26 | 92.31% |
| `packages/mm_design/lib/src/widgets/search_field.dart` | 5 / 5 | 100.00% |

Commands passed:

- `flutter analyze` (no issues).
- `dart format --set-exit-if-changed apps packages` (669 files, no changes).
- `python3 tool/coverage.py` (all package tests passed; fresh LCOV).
- `flutter test --no-pub test/research_controls_test.dart` in `packages/mm_design` (9 passed; includes optional length enforcement without a counter).
- `MM_SCREENSHOTS=../../docs/evidence/gul-607 flutter test --no-pub test/expansion_test.dart` in `apps/marginmind` (11 passed; seven PNGs including dark review).

| Package | Covered / lines | Coverage |
| --- | ---: | ---: |
| apps/marginmind | 23973 / 26581 | 90.19% |
| packages/mm_assistant | 2076 / 2132 | 97.37% |
| packages/mm_book | 1300 / 1364 | 95.31% |
| packages/mm_core | 5040 / 5184 | 97.22% |
| packages/mm_data | 542 / 558 | 97.13% |
| packages/mm_design | 2004 / 2218 | 90.35% |
| packages/mm_layout | 165 / 165 | 100.00% |
| packages/mm_pdf | 1814 / 1941 | 93.46% |
| packages/mm_platform | 575 / 618 | 93.04% |
| packages/mm_reflow | 1058 / 1115 | 94.89% |
| packages/mm_research | 637 / 655 | 97.25% |
| **Total** | **39184 / 42531** | **92.13%** |

Required: 80%.
