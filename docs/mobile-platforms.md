# Mobile platform integration (GUL-539)

The iOS and Android applications use `io.github.mylxsw.marginmind`, matching macOS. iOS/iPadOS requires 17.0. Android requires API 24, the minimum of Flutter 3.47.2 and the locked `record_android` 2.2.0 plugin. The `--no-codesign` simulator build checks compilation. Runtime credential tests must retain `Runner.entitlements` and use a normally signed simulator build: a binary lacking simulated application-identifier/keychain-access-group entitlements returns Keychain OSStatus -34018. Release signing remains an owner configuration: select an Apple development team in Xcode; replace the generated Android debug signing configuration before distributing release builds.

## Capability contract

`MMPlatformCapabilities.current` in `mm_platform` describes implementations shipped with the app. It is independent of `MMInput`, window size and touch input. Tests and other hosts can construct `MMPlatformCapabilities(TargetPlatform.windows, web: true)` explicitly. GUL-543 can reuse this contract; a web host never inherits native capabilities from its OS.

| Capability | macOS | iOS / Android | Windows / Linux / Web |
| --- | --- | --- | --- |
| `secretStore`, `externalLink` | yes | yes | false |
| `articleParser`, `pdfOcr`, `mapExport`, `nativeMapClipboard` | yes | false | false |
| `shareFile` | false | yes | false |
| `desktopDrop` | yes | false | Windows/Linux only |

`articleParser` rejects unsupported hosts before invoking WebKit. OCR uses the existing `supported` contract. Mobile export offers Markdown/OPML; PNG/PDF are hidden. Structured clipboard/image paste remains macOS-only; Flutter text clipboard remains usable elsewhere.

## Credentials and links

The existing `marginmind/secret_store` read/write/delete contract is implemented on both mobile Runners. iOS stores generic-password entries in Keychain with `AfterFirstUnlockThisDeviceOnly`. Android uses a 256-bit AES-GCM key generated in Android Keystore, a fresh IV for each write and account-bound authenticated data. Only IV/ciphertext are written to private preferences; backup and device transfer exclude those preferences. Key or storage failures return `unavailable`; there is no plaintext fallback. `external_link` accepts absolute HTTP(S) URLs only and opens the system browser.

## Import and export

The locked `file_selector_ios` 0.5.3+7 opens documents with `asCopy: true`. `file_selector_android` 0.5.2+11 reads SAF URIs with `ContentResolver.openInputStream` and copies them to its cache before returning a path. Existing PDF/image import immediately copies these paths into the learning-set package, so permanent access does not depend on the external provider. Tests delete the source and reopen the package. Keep this copy contract when upgrading selectors.

`MobileFileShare.share(name, bytes)` sends a filename and encoded bytes through `marginmind/file_share`. iOS writes a unique temporary file and presents `UIActivityViewController`, with an iPad popover anchor; completion removes the file and reports cancellation. Android uses `ACTION_SEND`, a restricted `FileProvider` cache path and temporary read grants. Android reports chooser handoff (it cannot confirm a recipient saved the file); files remain available for receivers and are pruned after one day on the next export. OS cache cleanup may happen earlier. Desktop export retains its save dialog.

No sharing plugin was added. Android's explicit AndroidX Core 1.17.0 dependency (Apache-2.0, Android) supplies `FileProvider`. `integration_test` is a Flutter SDK development dependency (BSD-3-Clause). Native permission text is localized through `InfoPlist.strings`, matching the English/Chinese ARB entries.

`third_party/desktop_drop` preserves upstream 0.8.4 desktop code and its Apache-2.0 license. Only desktop platforms are registered; a runtime widget guard also avoids initializing the plugin on mobile. The generated mobile plugin lists contain no `desktop_drop`. iPad `UIDropInteraction` is deferred; import uses the system picker.

The app permits HTTP connections on Android to retain explicitly configured local/custom model services; HTTPS remains available. iOS permits local networking. Microphone permission is requested by `record`; full-screen iPad mode is disabled and all iPad orientations are declared. File sharing/open-in-place is enabled for Documents; the private application-support learning library is not exposed as a document browser.

## Validation

CI adds `flutter build ios --simulator --no-codesign` and `flutter build apk --debug`, alongside existing macOS checks. Run from `apps/marginmind`. Run `flutter pub get --enforce-lockfile`, `flutter analyze`, `dart format --set-exit-if-changed apps packages`, `python3 -m unittest discover -s tool/tests` and `python3 tool/coverage.py` from the workspace root.

`integration_test/mobile_test.dart` exercises real native credential read/write/delete, imports the bundled PDF into the app library, deletes its temporary source and displays the native share panel. For persistence, build `-t tool/mobile_probe.dart`, install once, then terminate and relaunch the same binary. This standalone entry avoids the iOS integration-test host handshake. Its marker switches the second launch to verification and prints `GUL539_PERSISTED_OK`. Separate `flutter test` runs uninstall the app and cannot test persistence. Use a disposable simulator; the probe creates a study set and dummy credential.

Third-party cloud file providers, physical devices and recipient-side file saving require manual acceptance. iPad drag-in, mobile OCR/article extraction and graphical export are intentionally deferred. See `evidence/platform/GUL-539/` for this run's results.
