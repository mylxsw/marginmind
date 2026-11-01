# Browser tabs redesign — 2026-11-01

Implemented the selected document-conversion popover and independent webpage tabs.
Each page owns its native browser session, history, DOM, and reading position. Opening an already open URL activates its tab without reloading it. Closing or converting one page leaves other sessions intact. Tabs remain window-local and are not restored after leaving the workspace.

The tab strip shortens labels before scrolling, keeps the active tab visible, and provides scroll controls, a new-webpage action, and a searchable open-tabs list with a count. The title bar reserves the right action area before laying out tabs. Reader/map layout controls retain their positions but are disabled for live webpages.

The browser toolbar contains back/forward, refresh (Stop during loading), address, and an icon-only conversion action. The old history-looking refresh icon, standalone webpage close action, and document switcher were removed. Closing a webpage uses its tab close button. The conversion prompt floats beneath the conversion icon on macOS/iOS/Android. On Windows it reserves space above the native webpage: WebView2 child HWNDs cannot be drawn beneath a Flutter overlay.

## Evidence

These are system captures of the native macOS test app, using generated local article fixtures and an in-memory library, not a production website or the user's library.

- `01-conversion-popover-dark.png`: loaded article with the selected conversion popover.
- `02-many-tabs-dark.png`: 15 webpage tabs plus the document/map tab, with the right controls unobstructed.
- `03-all-tabs-dark.png`: searchable all-tabs list anchored at the strip's trailing edge.

## Verification

- 45 targeted widget tests passed: browser, independent webpage tabs, workspace tabs, tab strip, conversion behavior, and conversion layouts.
- Native macOS integration test passed: real WKWebView loading, independent DOM and history, retained scroll position, no reload on tab activation, popover dismissal, 16-tab overflow, searchable switching, and isolated close/disposal.
- macOS Debug application compiled successfully during the integration run.
- Analysis of application source and the affected tests passed; `git diff --check` passed.
- Full application analysis still reports two pre-existing test signature mismatches in `integration_test/study_notes_ai_test.dart:87` and `test/translation_controls_test.dart:31`. Those files are unchanged by this task.
- No installed release replacement or physical-device verification was performed. Windows native rendering was not exercised on a Windows machine.

Run the native test from `apps/marginmind`:

```sh
flutter test integration_test/browser_tabs_test.dart -d macos
```

`BROWSER_TABS_SHOT_SERVER` is an optional local HTTP capture endpoint. The native test also runs without it. Native verification used a temporary checkout to avoid concurrent work sharing the same build directory.
