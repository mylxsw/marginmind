# GUL-540 adaptive layout evidence

Captured on 2026-10-28 with debug builds on the iPad Pro 13-inch (M5) and iPhone 17 Pro simulators (Xcode 27.1), opening the bundled sample study set. The iOS runner was generated in a scratch copy and is not part of this change; for the capture only, its `Info.plist` set `UIRequiresFullScreen` so the probe could rotate the iPad. iPadOS 26 still shows the app in a window, so the iPad shots show a 1032×1376 / 1376×1032 pt window on the simulator screen.

The probe ([`probes/simulator_probe_test.dart.txt`](probes/simulator_probe_test.dart.txt), driven by [`probes/run_probe.sh.txt`](probes/run_probe.sh.txt)) collected layout errors in portrait and landscape: **0 on both devices** (GUL-538 measured 3 RenderFlex overflows on the iPhone).

| Device | Portrait | Landscape |
| --- | --- | --- |
| iPad Pro 13" (safe area 32 / 25) | [library](ipad13-portrait-library.jpg), [source above map](ipad13-portrait-workspace.jpg), [sidebar drawer](ipad13-portrait-drawer.jpg), [floating assistant](ipad13-portrait-assistant.jpg) | [desktop split](ipad13-landscape-workspace.jpg), [assistant beside the panes](ipad13-landscape-assistant.jpg) |
| iPhone 17 Pro (safe area 62 / 34; landscape 62 left and right) | [library](iphone17pro-portrait-library.jpg), [source](iphone17pro-portrait-workspace.jpg), [map](iphone17pro-portrait-map.jpg), [sidebar drawer](iphone17pro-portrait-drawer.jpg), [assistant](iphone17pro-portrait-assistant.jpg) | [one pane, no split](iphone17pro-landscape-workspace.jpg), [drawer](iphone17pro-landscape-drawer.jpg), [assistant](iphone17pro-landscape-assistant.jpg) |

The iPad shots come from commit `a535c44`, the iPhone shots from `9bfb6b9`; later commits merge `main` (tighter reader tool row from upstream, keyboard inset) without changing the size-class layouts. The phone's bottom tabs and sheets are GUL-542.
