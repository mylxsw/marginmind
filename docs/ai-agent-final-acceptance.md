# AI task routing integration acceptance

Local acceptance on Linux arm64, Flutter 3.47.2 / Dart 3.13.2, 2026-11-01. This report distinguishes deterministic behavior from live provider quality.

## Production integration

Settings now imports the same twelve immutable TaskSpecs used by domain dispatch, including capability requirements. Quick tasks are selection translation, word lookup and title generation. Heavy tasks are assistant chat, conversation/document summary, document translation, map expansion/generation, research, study notes and review cards.

Settings saves only the revision-controlled routing document. The legacy catalog default remains migration input and is no longer rewritten. A missing default remains repairable through model selection. Unknown capability profiles remain inadmissible. Repeated unknown warnings are shown once on an inherited category, while feature-specific missing capabilities remain visible when the category itself resolves.

Owner-bound registries deliberately remain in domain factories. Assistant owners, map stage validators and note organizers all use PersistentTaskAssembly with their frozen knowledge versions; replacing them with a static universal handler registry would lose ownership and validation boundaries. Shared exports include every domain contract and factory dependency.

The production audit traced all twelve entry points through task routing and SDK Runtime. Direct generate/stream remains inside controlled runtime transport and legacy package constructors/tests/smoke tools. The old assistantRunFactory has test consumers only. Native search requires injected controlled bindings; it has no untracked model fallback. Model catalog HTTP and external content retrieval are not model execution bypasses.

## Local validation

From apps/marginmind:

```sh
flutter test --no-pub test/ai_task_settings_test.dart test/assistant_routing_test.dart test/task_runtime_assembly_test.dart --reporter expanded
flutter analyze --no-pub lib/features/assistant/settings/ai_task_settings.dart test/ai_task_settings_test.dart
flutter build linux --debug --no-pub
```

36 tests passed, targeted analysis clean, native Linux build passed. Settings tests cover exact twelve-task coverage, production capability eligibility, feature warnings under a usable category, byte-for-byte unchanged legacy preferences, revision conflicts, failed saves, narrow layouts and model removal. The first integration run exposed two duplicate-warning assertions; the production deduplication was corrected and the original assertions retained, with an additional feature-specific warning test.

From packages/mm_assistant:

```sh
dart test test/quick_tasks_test.dart test/task_runtime_test.dart test/proposals_test.dart --reporter expanded
```

23 tests passed. Includes Quick off on each schema-repair attempt, frozen output ceilings through transport retry and archive recovery, unknown usage, partial coverage, cancellation, saving verified results without another purchase, owner-bound tools, proposal validation/idempotency/revision conflicts and preservation of user-controlled writes.

GUL-652 final review: 72 named app tests (map_concurrent_review, map_task_ownership, map_task_recovery, map_task_assembly, map_generation_flow, map_generation_ui, expansion) passed; seven-file targeted analysis clean. Original duplicate-purchase regression is retained. Cross-container/isolate/process ownership and pending-save retention passed. After concurrent main changes, three affected map files reran: 27 tests passed. Final reviewed head ba53603b4603748bc5f8610196a277b9edeec98c merged as 45f17357249800671b7d608d9e02520172281401. The merge resolved additive public exports and localized strings without dropping either side.

Earlier independently reviewed child evidence remains on GUL-643: assistant recovery/stream/search/image wiring, translation repeated-storage failures, note local-mode and route repair, map source/Unicode preservation, capability atomic publication, key-storage fencing, citations and proposal/undo behavior. No full-suite run, coverage collection, CI rerun or protection-rule change was used for acceptance.

## Native UI acceptance

Built and launched the actual debug desktop binary under Linux Xvfb with isolated XDG config/data/cache directories. Operated Settings → Models → Add Service → Ollama → manually add `ui-acceptance-local` → Save, then Settings → AI Features → Quick default picker → choose the saved model → Save. The catalog persisted across an app restart. Routing revision advanced to 1, Quick remained Off, unknown capability was visibly reported, and the legacy catalog default remained unchanged. Opened the built-in sample study set, opened the actual assistant pane, verified that a missing credential leaves the composer and model repair picker accessible, and selected the unverified local model without granting it capabilities. The document-summary task picker likewise accepted a repair selection but kept Send disabled for unverified capability. Scrolled through all nine Heavy feature rows and checked the supported 960×600 minimum desktop window as well as 1280×900.

A forced 390×844 **desktop** resize bypassed the native 960×600 minimum-size hint in the window-manager-free Xvfb session and produced overflow in the desktop library/settings layout. This is not a phone validation: phone mode is selected by the host OS. Restoring the supported desktop minimum rendered correctly. The actual phone layout is covered by the named iOS-platform widget test, not a physical device test. No claim is made that desktop layouts support widths below their declared minimum. Screenshots retain both observations.

## Explicit validation limits

No live model-quality claim is made. Loopback HTTP and SDK fixtures validate payloads, lifecycle, usage and persistence, not model reasoning or output quality. No real native-search service quality, macOS/iOS physical device, or successful real Keychain write was verified. Linux has no configured secret service; failure/repair behavior is covered locally.

Only the maintained exact official gpt-4.1-2025-04-14 Chat Completions identity has tools/historyReplay admission. Other model/endpoint/protocol combinations remain restricted by their actual maintained profiles; unknown combinations fail closed. Profiles were not broadened to make fixtures pass.
