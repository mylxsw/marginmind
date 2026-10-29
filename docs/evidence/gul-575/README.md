# GUL-575 — embedded browser

The browser uses an app-owned `marginmind/browser` native bridge: WKWebView on Apple platforms, Android WebView, and WebView2 on Windows. UI/platform plugins do not enter feature code. Web and Linux have no entry point.

`BrowserSession` in `mm_platform` exposes navigation/history/reload/stop, app-wide `clearData()`, state notifications, and `capture(navigationId:)`. Captures contain URL, title, UTC timestamp, current serialized DOM and image/stylesheet resource URLs. They do not re-fetch the page or export cookies. Navigation, SPA URL changes, disposal and a 15-second capture timeout invalidate stale results. The converter can override `browserConverterProvider` to open its format sheet; saving formats, Readability and authenticated resource bytes belong to GUL-577. Until then, the default action previews the captured page title and URL without claiming to save a document.

Each Apple app uses its persistent default WK website store (separate from Safari). Android uses app-sandbox WebView/CookieManager. Windows uses `%LOCALAPPDATA%\MarginMind\Browser`. Clearing closes native views and clears cookies, storage and cache; it also closes the temporary sidebar entries. Windows initializes a hidden controller if clearing before opening a page in this launch.

No JavaScript-to-app bridge is registered. WK scripts use a private content world; Android has no `addJavascriptInterface`; WebView2 disables web messages and host objects. Navigation permits only HTTP(S), including subframes where supported. Downloads, popups to external protocols, file access and permission requests are denied. Capture strings are capped at 16 MiB; platform and navigation errors leave conversion disabled.

Readiness requires main-frame completion and 800 ms without observed DOM/resource activity. A PerformanceObserver avoids the browser's resource-timing buffer limit. At 15 seconds, the browser offers manual capture of the partially loaded page. This is a heuristic: unfinished fetches, cross-origin frames and long polling cannot all be observed through DOM/resource timing. The automatic prompt appears at most once per navigation.

The nonmodal prompt stays immediately under the browser toolbar, above the native content. This avoids placing a Flutter overlay over the Windows child HWND. Windows hides the child surface when a dialog covers the route or the browser tab is hidden. A narrow toolbar exposes close, URL, reload/stop and conversion; Android back first uses browser history, then closes the tab. iOS enables native back/forward gestures.

## Reproduction

From `apps/marginmind`:

```sh
flutter test integration_test/browser_test.dart -d macos --reporter expanded
flutter test integration_test/browser_test.dart -d 1415C442-DE9B-4F38-823D-1CAF69BB9926 --reporter expanded
JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home PATH=/opt/homebrew/opt/openjdk@21/bin:$PATH flutter test integration_test/browser_test.dart -d emulator-5554 --reporter expanded
```

The fixture is a local HTTP server inside the test app: it changes DOM after loading, serves a local image, and sets a persistent cookie. Assertions exercise quiet readiness, captured live DOM/resources, navigation invalidation, cookie retention after recreating the view, and cookie removal after clearing data. Windows runs the same fixture in GitHub Actions after `flutter build windows --debug`; no external website or account is required.

Final validation results are recorded in the PR and task comment.
