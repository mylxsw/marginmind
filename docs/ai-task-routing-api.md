# Task routing integration (GUL-646)

`TaskModelResolver` implements the frozen `mm_core.ModelResolver`. It owns model selection and policy compilation. It does not execute business tasks. The application composition is in `assistant_routing.dart`; settings UI and Runtime migrations use these providers rather than the legacy catalog default.

```dart
final routing = await ref.read(assistantRoutingProvider.future);
final resolver = ref.read(assistantModelResolverProvider);
final request = TaskRequest<String>(
  spec: registeredTitleSpec, // Domain owner supplies schema and completion rule.
  input: {'question': question},
  inputFingerprint: fingerprint,
);
final row = await resolver.inspect(request, routing); // effective/source/issue
final snapshot = await resolver.resolve(request, routing); // throws on unready
// Runtime owns start/checkpoint and every SDK attempt. Before each dispatch:
await resolver.validateCurrent(snapshot);
// Use snapshot.policy with connectAssistant(callPolicy: ...), and
// policyModelConfig(snapshot.policy) for each request, repair and retry.
```

Selection is request override → explicit function binding → class default → unset. An invalid reference never inherits another model. Missing category defaults do not block explicitly bound functions. Quick policies always compile to `off`, including requests/configurations asking for stronger reasoning. A running snapshot stays immutable; a changed/removed/disabled service prevents its next dispatch. The Runtime decides how the user starts a new configuration phase.

`inspect()` returns `RoutingRowState`: the exact `RoutingSource`, reference, display labels, `RoutingIssue` and failure code. Capability issues include the compiler's capability kind (`tools:unknown`, for example). `reasoningOptions(profile)` only returns values the actual compiler accepts. Labels in `ResolvedTaskConfig` are optional additive fields on the existing DTO; the S2 persistence codec should retain them. IDs remain the sole lookup keys.

## Configuration and migration

`AssistantRoutingStore.load()` migrates the persisted legacy default to both defaults once, without reading or writing Keychain. It retains a deleted legacy reference rather than the compatibility catalog's first-enabled fallback. It writes `assistant.task-routing.v1`; old service/credential keys remain intact. The new routing does not consult the compatibility catalog default after migration.

`save(draft, expectedRevision: current.revision)` serializes with every store using the same preferences instance. Stale revisions throw `RoutingRevisionConflict`; other write failures propagate and reload the preferences cache. The controller publishes only successfully persisted state. Unknown document fields, task keys and default categories survive typed saves. Unsupported versions and malformed known bindings block writes without replacing the original text. A null/absent known default removes that default; a null/absent known binding restores inheritance.

Model maps in defaults/bindings store `serviceLabel` and `modelLabel`. Live labels refresh on save; absent services/models retain their old snapshots. Older references without labels display IDs. Routing data remains present if all services/models are removed or disabled; settings must use routing presence rather than enabled-model count to decide whether to show existing settings.

`AssistantServices` now owns a monotonic catalog revision. Configuration/model metadata edits and credential updates increase the service revision; no-op upserts keep it. Deletion advances the catalog clock so reusing an ID cannot reuse an old profile. Endpoints, protocols, adapter versions and service revisions participate in exact capability identity. Directly constructing/saving replacement catalogs is intended for migration/tests; production edits use the serialized services controller.

## Capability probing

`assistantCapabilityProfilesProvider` supplies the exact-identity `CapabilityProfiles` registry. There are no model-name profiles or default production admissions. A trusted catalog integration may insert an official/maintained profile with independent semantic and wire evidence; `userDeclared` and HTTP acceptance cannot satisfy the compiler. The registry is intentionally process-local: after restart, absent independently verified data remains unknown.

```dart
final cancellation = CancellationToken();
final result = await ref.read(assistantCapabilityProbeProvider).probe(
  reference,
  cancellation: cancellation,
);
// cancellation.cancel() cancels the SDK request and closes its transport.
// result.accepted only reports protocol acceptance. Check result.issue/profile;
// success does not change unknown capabilities into supported ones.
```

The infrastructure probe uses one controlled SDK request through `connectAssistant`, no transport retries, bounded timeout/output, and no registered/executed tools. A verified requested policy uses the S0 compiler and payload guard. An unknown profile permits only a diagnostic auto request; requesting off without evidence fails before network access. Changed catalog identity discards late results. Authentication/network failures propagate separately from capability evidence. The older catalog tool-acceptance probe also keeps unknown on HTTP success.

## Conversation and deletion usage ports

`migrateConversationRouting(viewJson)` adds `taskRouting: {version: 1, assistantChat: reference}` once, preserving all other fields. `conversationRoutingOverride(viewJson, type)` applies it only to `assistant_chat`. Setting `assistantChat: null` explicitly restores inheritance and prevents legacy-model resurrection. New conversations should start with that null marker. The archive owner calls this helper while loading/saving; this change does not rewrite controller/archive files owned by S2.

`ArchiveRoutingUsageIndex` is a concrete read-only adapter accepting two callbacks:

- `conversations`: all archived/live conversation views, keyed by stable conversation ID.
- `runs`: run manifests from the RunStore index. Only created/validating/running/awaitingUser/paused/interrupted runs are listed as recoverable.

Compose it where both indexes are available, then use `ref.read(assistantRoutingUsageProvider(index)).of(serviceId: id)` or `.of(model: reference)`. `RoutingUsage` adds quick/heavy defaults and explicit function bindings, including future task keys. The adapter never imports or constructs Runtime. Index read/corruption failures propagate; deletion UI must not treat a failed query as an empty list. S2 must supply its real archive/run index callbacks; no empty or throwing production fallback is installed here.

The legacy `quickModelFor`/`assistantTitleModel` helpers are compatibility identities; their name heuristics are removed. S3/S4 replace the remaining business callers with declared task requests. This PR does not claim those business paths already execute through the new Runtime or enforce wire policy before that migration.

## Local validation

On macOS arm64, Flutter 3.47.2 / Dart 3.13.2, run only these named tests:

```sh
# packages/mm_assistant
 dart test test/task_routing_test.dart test/capability_probe_test.dart test/services_test.dart test/titles_test.dart test/model_policy_test.dart --reporter expanded
# apps/marginmind
 flutter test --no-pub test/assistant_routing_test.dart test/assistant_services_test.dart --reporter expanded
```

The protocol fixtures require the package working directory. Tests use synthetic profiles/transports and mock preferences. No real credentials/model calls, device UI validation, full-suite tests or coverage runs are included.
