# GUL-543 platform evidence

Validated on 2026-10-28 with Flutter 3.47.2 / Dart 3.13.2.

## Builds and checks

- `flutter pub get --enforce-lockfile`: passed; `web` was already resolved in the workspace lockfile.
- `flutter analyze`: passed (no issues).
- `dart format --set-exit-if-changed apps packages`: passed.
- `flutter build web --release`: passed.
- `flutter build linux --release`: passed on Ubuntu 24.04 ARM64 in an isolated Docker container, using the same Flutter SDK revision. Linux dependency resolution did not modify the macOS checkout.
- `flutter build macos --debug`: passed. Existing Swift Keychain deprecation and Flutter Assemble warnings remain.
- `python3 -m unittest discover -s tool/tests`: 17 tests passed.
- `python3 tool/coverage.py`: full package suite; package-by-package results in `coverage.md`.
- `dart test --platform chrome test/browser_library_store_test.dart` in `packages/mm_data`: 6 tests passed against real IndexedDB, including stale-tab conflict rejection.
- `desktop_shortcuts_test.dart`: Windows F11 dispatch reaches the window-manager channel, Windows/Linux find remains Ctrl+F, macOS modifiers remain unchanged, browser-owned shortcuts are excluded.
- `map_export_test.dart`: native encoder tests explicitly run as macOS; Windows and Linux offer and export Markdown/OPML without PNG/PDF options.

## Browser end-to-end reproduction

Build `apps/marginmind` for Web, then from the repository root:

```sh
python3 -m pip install playwright==1.64.1
python3 docs/evidence/platform/GUL-543/browser_smoke.py --chrome /path/to/chrome
```

`--chrome` can be omitted when `CHROME_EXECUTABLE` is set, `google-chrome` is on
PATH, or Chrome is installed in the standard macOS location. The script starts
and closes its own local HTTP server and fresh headless Chrome context.

The script uses the real UI and browser file chooser to create a study set from
the bundled PDF, renders its page, adds and renames a node, waits for committed
IndexedDB content, refreshes, reopens the study set, checks the PDF and node,
and downloads a Markdown export. It checks that native PNG/PDF choices and
the assistant sidebar are absent, and fails on browser console/page errors.

- `01-library.png`: initial library.
- `02-import-and-edit.png`: selected PDF and renamed node.
- `03-after-refresh.png`: reopened PDF and retained node.
- `browser-result.json`: browser version and successful checks.

CI repeats both the IndexedDB tests and the UI script and uploads the evidence.

## Limits

Windows has no build host in this task: code paths are tested with
`TargetPlatform.windows`, not a Windows executable. Linux build evidence is
ARM64; CI builds the Ubuntu runner's architecture. Real model services, Web
assistant networking/credentials/OCR, and browser PNG/PDF encoding are not
provided by this minimum Web release. Browser storage is origin-local and is
not a backup. See `docs/decisions/0003-browser-library-storage.md` for quota,
eviction, memory and concurrent-tab behavior.

GUL-539 had no merged PR at delivery. Its eventual unified capability interface
can replace the small policies in `shared/platform_support.dart`; this task
does not redefine `mm_platform.dart` or the shared providers.
