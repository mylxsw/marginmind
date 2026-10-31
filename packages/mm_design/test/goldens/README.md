# Host-specific widget goldens

`toolbar_density_test.dart` checks desktop controls in light and dark themes at
2× resolution, using Flutter's default widget-test fonts. The `mac-controls`
name describes the controls under test, not the host running the test.

Keep separate strict pixel baselines for the host renderers, following
`apps/marginmind/test/note_rich_export_test.dart`:

- `linux/`: Ubuntu 24.04 x64, Flutter 3.47.2 (the Analyze and test CI environment).
- This directory: macOS arm64, Flutter 3.47.2.

From `packages/mm_design` on the corresponding host, update and then verify:

```sh
flutter test test/toolbar_density_test.dart test/phone_glass_test.dart --update-goldens
flutter test test/toolbar_density_test.dart test/phone_glass_test.dart
```

Inspect the failure images before updating. Do not copy one host's baselines to
the other or relax the comparator tolerance. Geometry and touch interaction
assertions run alongside the pixel comparisons.

GUL-612 reproduced CI run 41086693491's exact differences (1929 light pixels,
1890 dark pixels) on Linux x64 with the pinned SDK. Inspection showed renderer
differences around icon strokes and rounded/blurred edges, with unchanged control
geometry. The refreshed macOS snapshots differ from the original baselines by
only 12 light pixels and 10 dark pixels. No production widgets were changed.

`phone_glass_test.dart` checks phone regular/thick materials and their opaque
fallbacks at 393×852. It uses the same strict host-directory selection:
`Platform.isLinux ? 'goldens/linux' : 'goldens'`. The optional `MM_SCREENSHOTS`
mode is for human-readable documentation images, not comparison baselines.

For GUL-630, generate Linux snapshots on Ubuntu 24.04 x86_64 with Flutter
3.47.2 (framework d3b14c876900e553bc736ca19295fc09e3853e8e, Dart 3.13.2),
then rerun without `--update-goldens`. Do not set `MM_SCREENSHOTS` while
regenerating comparison baselines. macOS snapshots remain unchanged.

Before generating the Linux phone snapshots, GUL-630 reproduced CI's exact
1875 light / 1797 dark differing pixels. The isolated diff shows default test
font edges and rounded material edges; size and interaction assertions pass.
