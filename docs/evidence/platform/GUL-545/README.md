# GUL-545 mobile Liquid Glass evidence

Captured on 2026-10-28 from branch `gul-545-liquid-glass` on the Mac worker:

- iPhone 17 Pro simulator (iOS 26.5), 402×874 pt.
- Android `mm_phone` emulator (API 36), 411×914 dp.

`apps/marginmind/integration_test/liquid_glass_test.dart` runs the real app, opens the bundled sample, adds eight empty study sets so the library scrolls, and visits Library, Source and Map in light and dark. System screenshots were taken at its `SHOT:` markers (`xcrun simctl io … screenshot`, `adb exec-out screencap -p`) and downscaled to 900 px JPEG. The iPhone set comes from `beb601a` and the Android set from `bb0dcfb`; the two differ only in the run's tap that clears a stray text selection before the reader shot.

| Screen | iPhone light | iPhone dark | Android light | Android dark |
| --- | --- | --- | --- | --- |
| Library: cards scroll beneath the glass toolbar and the floating tab bar | [Screenshot](iphone-light-library.jpg) | [Screenshot](iphone-dark-library.jpg) | [Screenshot](android-light-library.jpg) | [Screenshot](android-dark-library.jpg) |
| Reader: pages run under the bar, page controls stay above it | [Screenshot](iphone-light-reader.jpg) | [Screenshot](iphone-dark-reader.jpg) | [Screenshot](android-light-reader.jpg) | [Screenshot](android-dark-reader.jpg) |
| Map: canvas fills the window, controls clear of both bars | [Screenshot](iphone-light-map.jpg) | [Screenshot](iphone-dark-map.jpg) | [Screenshot](android-light-map.jpg) | [Screenshot](android-dark-map.jpg) |

## Frame timings

The same run wraps library scrolling, reader scrolling and map dragging in `watchPerformance`; the raw reports are in `perf/`. Reproduce from `apps/marginmind`:

```sh
flutter drive --no-dds [--profile] --driver=test_driver/perf_driver.dart \
  --target=integration_test/liquid_glass_test.dart -d <device-id>
```

Times in ms (average / p90 / p99); budget 16.7 ms.

| Run | Action | Frames | Build | Raster | Missed build / raster |
| --- | --- | ---: | --- | --- | --- |
| iPhone 17 Pro sim · this branch · debug | library scroll | 280 | 1.6 / 3.6 / 6.1 | 2.6 / 3.9 / 4.5 | 0 / 0 |
| iPhone 17 Pro sim · this branch · debug | reader scroll | 249 | 2.8 / 6.9 / 15.3 | 2.7 / 3.8 / 5.1 | 1 / 0 |
| iPhone 17 Pro sim · this branch · debug | map drag | 238 | 2.0 / 4.0 / 8.2 | 3.4 / 4.7 / 5.7 | 0 / 0 |
| Android `mm_phone` · this branch · profile | library scroll | 116 | 0.4 / 0.6 / 1.8 | 96.1 / 103.4 / 172.0 | 0 / 114 |
| Android `mm_phone` · this branch · profile | reader scroll | 112 | 1.1 / 1.8 / 5.8 | 122.7 / 188.8 / 231.7 | 0 / 111 |
| Android `mm_phone` · this branch · profile | map drag | 59 | 2.5 / 1.4 / 11.6 | 119.6 / 174.2 / 228.0 | 1 / 56 |
| Android `mm_phone` · `main` · profile | library scroll | 118 | 0.5 / 0.6 / 2.3 | 84.5 / 116.8 / 160.1 | 1 / 116 |
| Android `mm_phone` · `main` · profile | reader scroll | 120 | 1.1 / 1.8 / 5.8 | 92.6 / 153.3 / 184.2 | 0 / 114 |
| Android `mm_phone` · `main` · profile | map drag | 73 | 0.8 / 1.2 / 2.0 | 99.7 / 154.2 / 178.5 | 0 / 71 |

- **iOS simulator** (host GPU): every raster frame stays under 6.2 ms and no raster frame misses the budget. iOS simulators only run debug builds, so build times are pessimistic and the numbers are indicative, not a device profile.
- **Android emulator**: it renders in software (`emuglConfig: vulkan lavapipe, gles swangle`), so raster takes about 100 ms per frame even on `main`, which has no glass toolbar and an opaque tab bar. The emulator cannot show whether scrolling is smooth. The like-for-like comparison shows the cost of the two full-width glass bars on that CPU raster path: average raster library scroll +14%, reader scroll +33%, map drag +20% against `main`. Build times stay far below budget in both runs.
- Glass appears only on the toolbar, the tab bar, sheets and the existing floating controls. Library card badges skip the blur on touch platforms, so scrolling content carries no backdrop filters (asserted in `test/liquid_glass_test.dart`).

## Not covered

- Physical iPhone and Android devices: no profile run on real GPUs.
- Edge refraction through `ImageFilter.shader`: not implemented. The material is saturated blur, sheen and rim on every renderer.
- On iOS and Android, the system's Reduce Transparency setting is still not read (the platform layer reads it on macOS only). The opaque fallback is in place and tested through `MMAppearance`.

