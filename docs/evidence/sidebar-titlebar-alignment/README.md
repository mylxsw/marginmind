# macOS sidebar / window-button alignment

The collapsed sidebar button previously used a 44-point desktop tab row (center y=22), while the expanded sidebar and AppKit unified toolbar used center y=26. The macOS tab row now uses 52 points; Windows/Linux retain 44 points.

Verified with Flutter 3.47.6 in an isolated checkout of `0cc9e37c` plus this repair:

- `flutter test test/workspace_window_drag_test.dart test/workspace_tabs_test.dart --no-pub`: 22 passed.
- `flutter analyze --no-pub lib/features/workspace/widgets/workspace_desktop_shell.dart test/workspace_window_drag_test.dart integration_test/sidebar_titlebar_alignment_test.dart`: no issues.
- `flutter test integration_test/sidebar_titlebar_alignment_test.dart -d macos --no-pub`: passed, including repeated sidebar toggles, light/dark appearances, and 1280/1000-point window widths.
- Eight native window captures taken with `screencapture -x -o -l <window-id> <path>` through the test's optional `SIDEBAR_ALIGNMENT_SHOT_SERVER` callback. These include AppKit's actual buttons. `comparison.png` contains unscaled crops from the 1280-point captures.

The integration test resets the helper's synthetic screen size and pixel ratio before capture so the engine renders to the actual native window surface. All sidebar control centers are y=26 logical points. Native buttons appear inactive because the verification window was not foregrounded.

The test uses isolated in-memory sample content; the sample PDF placeholder is unrelated to this alignment check. This verifies the macOS Debug test application, not an installed Release application.
