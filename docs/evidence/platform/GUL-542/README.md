# GUL-542 phone layout evidence

Captured on 2026-10-28 with debug builds of `1b873a6` (the branch head before this README) on:

- **iPhone 17 Pro simulator** (Xcode 27.1): 402×874 pt, safe area 62 / 34.
- **Android emulator** `mm_phone` (API 36, 1080×2400 @ 420 dpi): 411×914 dp, safe area 50 / 24.

The iOS and Android runners come from the GUL-538 scratch copy and are not part of this change (GUL-539 owns them). The probe ([`probes/phone_probe_test.dart.txt`](probes/phone_probe_test.dart.txt), driven by [`probes/run_probe.sh.txt`](probes/run_probe.sh.txt)) runs the real app from a fresh install and takes system screenshots. It reported **0 layout errors on both devices**.

| Step | iPhone | Android |
| --- | --- | --- |
| Library; study set tabs wait for a set | [01](iphone17pro-01-library.jpg) | [01](pixel8-01-library.jpg) |
| Source tab | [02](iphone17pro-02-source.jpg) | [02](pixel8-02-source.jpg) |
| Excerpt: the source stays, the HUD offers View | [03](iphone17pro-03-excerpt-toast.jpg) | [03](pixel8-03-excerpt-toast.jpg) |
| View → Map tab with the new card | [04](iphone17pro-04-map.jpg) | [04](pixel8-04-map.jpg) |
| Long press on the card → action sheet; back closes it | [05](iphone17pro-05-node-action-sheet.jpg) | [05](pixel8-05-node-action-sheet.jpg) |
| Assistant as a bottom sheet over the tabs; back closes it | [06](iphone17pro-06-assistant-sheet.jpg) | [06](pixel8-06-assistant-sheet.jpg) |
| Card details as a bottom sheet | [07](iphone17pro-07-details-sheet.jpg) | [07](pixel8-07-details-sheet.jpg) |
| Typing the title: full height on the keyboard, tabs hidden | — (see below) | [08](pixel8-08-details-keyboard.jpg) |
| Review tab; tap the card to turn it | [09](iphone17pro-09-review.jpg), [10](iphone17pro-10-review-answer.jpg) | [09](pixel8-09-review.jpg), [10](pixel8-10-review-answer.jpg) |
| Back: review → study set → library | [11](iphone17pro-11-library-after-back.jpg) | [11](pixel8-11-library-after-back.jpg) |

Notes:

- The excerpt is made by `WorkspaceController.excerpt` with a fixed selection, and the HUD is shown with the same `showNotice` the selection toolbar uses. The probe does not drag-select PDF text on the simulator.
- Android back presses are real key events (`adb shell input keyevent 4`). iOS has no back key, so its run sends the same `popRoute` through the binding.
- The iOS simulator has a hardware keyboard connected, so no on-screen keyboard appears there (the probe measured a keyboard inset of 0). Android measured 336 dp. Widget tests cover both.
- The first runs of this probe found two bugs that are fixed in this change. A HUD with a long study set title overflowed and pushed View off screen. On Android, the system back key sent the app to the background, because Android only delivers back to an app that declares it can pop.
