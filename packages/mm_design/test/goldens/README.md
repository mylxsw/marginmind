# Toolbar density goldens

`toolbar_density_test.dart` checks desktop controls in light and dark themes at
2× resolution, using Flutter's default widget-test fonts. The `mac-controls`
name describes the controls under test, not the host running the test.

Keep separate strict pixel baselines for the host renderers, following
`apps/marginmind/test/note_rich_export_test.dart`:

- `linux/`: Ubuntu 24.04 x64, Flutter 3.47.2 (the Analyze and test CI environment).
- This directory: macOS arm64, Flutter 3.47.2.

From `packages/mm_design` on the corresponding host, update and then verify:

```sh
flutter test test/toolbar_density_test.dart --update-goldens
flutter test test/toolbar_density_test.dart
```

Inspect the failure images before updating. Do not copy one host's baselines to
the other or relax the comparator tolerance. Geometry and touch interaction
assertions run alongside the pixel comparisons.

GUL-612 reproduced CI run 41086693491's exact differences (1929 light pixels,
1890 dark pixels) on Linux x64 with the pinned SDK. Inspection showed renderer
differences around icon strokes and rounded/blurred edges, with unchanged control
geometry. The refreshed macOS snapshots differ from the original baselines by
only 12 light pixels and 10 dark pixels. No production widgets were changed.
