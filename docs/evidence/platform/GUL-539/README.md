# GUL-539 validation

Local environment: Flutter 3.47.2 / Dart 3.13.2, Xcode 27.1, iOS 26.5 iPhone 17 Pro and iPad Pro 13-inch (M5), Android SDK 36 / JDK 21 / Pixel 8 AVD (API 36). Main synchronized through `c03275c`.

- `flutter pub get --enforce-lockfile`: passed.
- `flutter analyze`: passed, no issues.
- `dart format --set-exit-if-changed apps packages`: passed, 370 files unchanged.
- `python3 -m unittest discover -s tool/tests`: 17 passed.
- Package Flutter/Dart tests passed. After syncing main, application tests reran: 571 passed, 8 existing skips. `mm_platform`: 29 passed. Data persistence regression: 4 passed.
- `python3 tool/coverage.py` ran package suites; after correcting desktop test platform assumptions, the affected suites reran with coverage and `--report-only` merged all results: 90.75% overall; app 87.91%, platform 94.29%, data 97.10%. See `coverage.md`.
- `flutter build ios --simulator --no-codesign`: passed.
- `xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug -destination "platform=iOS Simulator,id=<iPad>" -only-testing:RunnerTests -parallel-testing-enabled NO`: passed; xcresult reports 1 native Keychain test, 0 failures.
- `flutter build apk --debug`: passed; no desktop_drop Android registration/KGP warning.
- `flutter build macos`: passed (release); existing macOS Keychain deprecation warnings remain.
- `flutter test integration_test/mobile_test.dart -d <device>` passed on iPhone, iPad and Android, using real credentials, bundled PDF import, source deletion, app startup and native sharing. Logs included.
- Android, iPhone and iPad standalone cold relaunch preserved credential and PDF bytes; see restart logs. `flutter test` uninstalls afterward, so it cannot validate persistence across separate test invocations. The standalone probe uses one installation.

The native share screenshots are OS screenshots, not Flutter mockups. Markdown and OPML cancellation/failure paths are also covered by widget tests. The signed iOS build includes explicit Keychain access-group entitlements; an unsigned scratch build without them returned -34018, as expected from securityd.

Not covered: physical devices, third-party cloud document-provider UI, recipient-side file saving. Import tests use provider-equivalent temporary paths; plugin source inspection confirms iOS `asCopy: true` and Android URI-to-cache copying. iPad drag-in, mobile OCR/article extraction and graphical export are deferred by the agreed scope.
