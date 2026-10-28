# GUL-544 mobile polish evidence

Captured on 2026-10-28 from this branch using the committed iOS/Android runners:

- iPhone 17 Pro simulator (iOS 26.5): 402×874 pt portrait, 874×402 pt landscape.
- Android `mm_phone` emulator (API 36): 411×914 dp portrait, 914×411 dp landscape.

| Screen | iPhone | Android |
| --- | --- | --- |
| Portrait library: complete “All Study Sets”, search below toolbar | [Screenshot](iphone-portrait-library.png) | [Screenshot](android-portrait-library.png) |
| Portrait reader: existing floating page navigation | [Screenshot](iphone-portrait-reader.png) | [Screenshot](android-portrait-reader.png) |
| Landscape reader: page navigation outside the PDF viewport | [Screenshot](iphone-landscape-reader.png) | [Screenshot](android-landscape-reader.png) |

`apps/marginmind/integration_test/mobile_polish_test.dart` runs the real app, opens the bundled sample PDF, rotates the device and checks that the landscape page controls do not overlap the PDF viewport. Both device runs passed without FlutterError. System screenshots were captured at its `SHOT:` markers with `xcrun simctl io <device> screenshot` / `adb exec-out screencap -p`.

Run on a disposable, fresh simulator install from `apps/marginmind`:

```sh
flutter test integration_test/mobile_polish_test.dart -d <device-id>
```

The eight widget cases in `test/mobile_polish_test.dart` cover all four requested sizes, safe areas, actual title ellipsis detection, search filtering, navigation clearance and resizing back to portrait. The existing phone search-width assertion now checks the full-width field below the toolbar; iPad and desktop assertions are unchanged.

On phones shorter than 500 pt the PDF viewport reserves an 80 pt bottom navigation lane. The visible document is shorter and scrolls within that viewport; page controls remain available. Tall phones, tablets and pointer windows retain the existing floating layout. The compact library layout follows the search-below-toolbar arrangement in `design/prototype/cross-platform.html` (audit M3/M6).

Physical devices, non-default text scaling and native macOS interaction were not exercised manually in this run. Desktop/iPad widget regressions are included in the full suite.
