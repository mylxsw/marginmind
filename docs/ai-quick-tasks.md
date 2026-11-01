# Quick task integration (GUL-649)

Selection translation, dictionary/context lookup and automatic conversation titles register three `TaskDefinition<String>` contracts in `quickTaskRegistry()`. Application callers use `quickTaskExecutorProvider(studySetId)`, which freezes the function route with `PersistentTaskAssembly` and starts the shared SDK runtime. Completed, validated output is returned only after the run/result envelope is persisted in the study set. Each request gets its own run; title generation never inherits the conversation model.

Quick tasks expose no tools or knowledge reads. The runtime owns transport retries, one schema repair and policy compilation on every attempt. The application retains the existing 10-second title and 90-second selection/lookup deadlines. Truncation, tool calls, invalid dictionary JSON, empty output and invalid titles cannot be accepted as completed. Titles are bounded to 24 Unicode characters without silently truncating a model answer. Translation validates placeholders (including numeric placeholders), URLs, inline/fenced code, paragraph breaks and Markdown markers. This is deterministic format validation, not a claim of semantic translation quality.

The lookup cache is scoped to a study set and keyed by normalized term/lemma, sentence fingerprint, target language, explicit source language or automatic detection, and prompt version. Both aliases and context-only entries use that key. Existing saved vocabulary and sentence translations remain available without model calls; routing/credential edits clear only the in-memory lookup service. Explicit `online: false` further restricts the study-set preference. Admission uses the routed model's protocol, so an unrelated conversation/default model cannot authorize a remote request while offline.

Public changes are confined to these three entries: exported quick specs/registry/executor, `TaskParagraphTranslator`, `WordLookup.tasks(execute)` replacing the direct connection constructor, `generateAssistantTitle(execute, question)`, and study-set-scoped application factories. The optional lookup `model` argument remains source-compatible but cannot override task routing. No settings UI, shared provider policy, runtime contract or full-document scheduler is changed. `ModelParagraphTranslator` remains the document translator until the Heavy migration; selection translation uses its own explicit `selection_translate` adapter.

## Capability availability

Production uses the real catalog, existing SecretStore and capability registry. An unknown profile, missing credential or unsupported off policy fails before dispatch and offers the existing settings action. No model-name heuristic, fallback service or fixture profile is installed.

The current registry is process-local and has no persisted verified profile feed. Consequently these entries are wired to production services but cannot call a model whose exact identity is still unknown, including after restart. A subsequent capability integration needs to load independently justified semantic + wire evidence keyed by service revision, endpoint, protocol and adapter version, and invalidate it when any identity component changes. HTTP acceptance alone must not upgrade unknown. This PR does not implement that cross-domain policy/persistence change.

The shared runtime currently takes wire output limits from the selected capability profile. Per-task token ceilings (for example the legacy title's 64 tokens) need a coordinated runtime option; this migration does not invent a second model-config path. The title length/format contract and timeout still apply.

## Local checks

macOS arm64, Flutter 3.47.2 / Dart 3.13.2:

```sh
# packages/mm_assistant
 dart test test/quick_tasks_test.dart test/word_lookup_test.dart test/titles_test.dart test/translation_test.dart --reporter expanded
# apps/marginmind
 flutter test --no-pub test/quick_task_assembly_test.dart test/word_lookup_test.dart test/selection_translation_test.dart test/selection_lookup_test.dart test/vocabulary_screen_test.dart --reporter expanded
```

Loopback HTTP exercises the application executor, real catalog/routing/secret lookup and disk run store with synthetic test-only capability evidence. It checks initial, HTTP retry and repair payloads, title-specific routing and offline rejection. Widget tests cover preserved selection, language changes, cancellation, saved history, vocabulary add/undo and regeneration. No full suite, coverage run, CI rerun, real provider/Keychain call or physical device verification is claimed.

Remaining business inference calls found with `rg -n 'generate\(|\.stream\(' packages/mm_assistant/lib/src --glob '*.dart'`: document translation in `translation.dart`, map expansion in `expansion.dart`, map generation in `map_generation.dart`, study notes in `study_notes/organizer.dart`, and internal native-search inference in `network.dart` (provider implementation in `web_search.dart`). `runtime.dart` and `task_runtime/runtime.dart` are harness/transport calls; `model_policy/probe.dart` and `service_catalog.dart` are infrastructure probes. The migrated title and lookup adapters contain no raw generation call.
