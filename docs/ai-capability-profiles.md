# Production capability evidence and request limits (GUL-655)

## Supported matrix

Reviewed 2026-11-01. The allowlist is executable in `maintained.dart`; matching is
exact, not substring-based. Only HTTPS port 443 without credentials, query or
fragment matches. Trailing slashes are normalized. The stored fingerprint still
binds the exact configured endpoint. No network response adds semantic support.

| Exact model | Host / protocol / allowed configured paths | Quick off | Heavy reasoning | Context / output ceiling |
| --- | --- | --- | --- | --- |
| `gpt-4.1-2025-04-14` | `api.openai.com`, Chat Completions: empty, `/v1`, `/v1/chat/completions` | Omit reasoning (non-reasoning model) | auto/off; standard/deep unsupported | 1,047,576 / 32,768 |
| `gpt-4.1-2025-04-14` | `api.openai.com`, Responses: empty, `/v1`, `/v1/responses` | Same | Same | Same |
| `gpt-5.1-2025-11-13` | `api.openai.com`, same Chat Completions/Responses paths above | Explicit effort `none` | auto/off/standard (`medium`)/deep (`high`) | 400,000 / 128,000 |
| `gemini-2.5-flash` | `generativelanguage.googleapis.com`, Gemini GenerateContent: empty, `/v1beta` | `generationConfig.thinkingConfig.thinkingBudget: 0` | auto/off; standard/deep unsupported | 1,048,576 / 65,536 |

All other model IDs (including undated GPT-4.1 alias), proxies, custom paths,
Anthropic, Ollama, Vertex and Interactions remain unknown. GPT-4.1 Chat Completions now admits `tools` and `historyReplay` together;
all other combinations retain unknown tool support. Structured-output and
multimodal requirements remain unknown: they have no completed SDK-specific
admission evidence in this change. Chat Completions history
replay uses the existing tested codec; Responses/Gemini history replay remains
unsupported because of the existing SDK replay gaps. The GPT-4.1 Chat Completions rule has a real SDK Agent tool declaration → returned
call → executable tool → result message → final answer test, plus persisted
AgentState replay in `maintained_tools_wire_test.dart`. The mocked HTTP responses
are encoder/loop evidence, not independent semantic evidence; official function
calling documentation supplies the latter.

The approved plan (§7/§9/§10) requires controlled tools and history for Heavy
assistant/research/document workflows. The audited combination now satisfies
`requiredCapabilities={tools,historyReplay}` without removing requirements or
silently downgrading Heavy. Native structured output is optional in the plan,
with local schema validation retained; tasks explicitly requiring native
structured output or multimodal input still fail closed. Responses/Gemini's
known replay gaps still block general Heavy history, regardless of vendor claims.

Sources:

- [OpenAI GPT-5.1 model](https://developers.openai.com/api/docs/models/gpt-5.1):
  pinned snapshot, none/medium/high effort support and token limits. No Codex,
  dated sibling or undated alias is included.

- [OpenAI GPT-4.1 model](https://developers.openai.com/api/docs/models/gpt-4.1):
  identifies the pinned snapshot, non-reasoning behavior, function calling support and token limits. The
  rule deliberately excludes aliases. This older snapshot is marked deprecated;
  availability must be checked separately with the existing probe.
- [Gemini GenerateContent thinking](https://ai.google.dev/gemini-api/docs/generate-content/thinking?hl=en)
  and [Google's 2.5 Flash announcement](https://developers.googleblog.com/en/start-building-with-gemini-25-flash/):
  the Flash thinking budget supports zero; not applicable to Pro or newer families.
- [Gemini 2.5 Flash model](https://ai.google.dev/gemini-api/docs/models/gemini-2.5-flash):
  stable ID and token limits. The page currently restricts access to established
  users; a semantic rule is not an availability or account entitlement guarantee.

## Evidence and SDK boundary

`CapabilityEvidence.semanticBasis/reference` describe the independent semantic
source. `wireVerified` refers to the pinned SDK encoder regression, **not** a live
provider call. `dart_agent_core` 2.1.8 encodes Chat Completions/Ollama-compatible
limits as `max_completion_tokens`, Responses as `max_output_tokens`, Anthropic as
`max_tokens`, Gemini as `generationConfig.maxOutputTokens`. Gemini's `extra` map
is merged into `generationConfig` (SDK `gemini_client.dart`); OpenAI non-reasoning
requests contain no reasoning knobs. Sources are the installed SDK 2.1.8 client
implementations and final-body tests, not assumptions from model names.

`maintained_capabilities_test.dart` exercises these production rules through the
real SDK with a recording HTTP adapter, including retry and payload rejection.
`model_policy_test.dart` covers all five protocols' off encoding and replay.
These are local encoder tests. No real service credentials were used and live
quality, availability, credentials, semantic translation accuracy and unsupported
combinations have not been validated.

`RoutingCapabilityProbe` still sends a single fixed infrastructure request. A
successful response persists only identity + acceptance time + requested reasoning.
For unknown profiles it returns `accepted: true`, `issue: unknown`,
`admissionFailureCode: maintainedEvidenceRequired`; retrying connectivity cannot
supply semantic evidence. Select an allowlisted model/official endpoint, or add a
reviewed exact rule with documentary and SDK wire evidence. Off probes against
unknown profiles fail with `unverifiedCapabilities`. No absence of thinking text
is treated as proof that thinking was disabled.

## Persistence and UI API

`assistantCapabilityProfilesProvider` keeps its existing `Provider<CapabilityProfiles>`
type and override entrypoint. Production delegates to `assistantCapabilityStoreProvider`
(`AssistantCapabilityProfiles`). `TaskModelResolver.inspect/resolve` and the probe
await `refresh()` before reading profiles; a helper that nobody calls is not the
loading path.

UI integration for GUL-648 (no settings UI changed here):

1. Await `ref.read(assistantCapabilityProfilesProvider).refresh()` before a direct
   synchronous `lookup(identity)` or reasoning-options query. Resolver/probe calls
   already do this. Re-query after service edits; the controller's service revision
   fences credentials and model edits, including deletion and reused IDs.
2. Use the existing `assistantCapabilityProbeProvider.probe(reference,
   cancellation: ..., reasoning: ...)`. Successful probes save automatically.
3. For the independent acceptance badge, read
   `ref.read(assistantCapabilityStoreProvider).probeObservation(identity)` after
   refresh/probe. Its `acceptedAt` and `reasoning` are not semantic evidence.
4. On completion, refresh the page's own async row state; the compatible Provider
   is deliberately not changed to an AsyncNotifier. Surface persistence errors.

Schema 1 stores only service/model identity, service revision, model revision slot,
endpoint fingerprint, protocol, adapter version, maintained-rule revision, and
optional acceptance observation. Semantic capabilities are reconstructed from the
reviewed rule, never trusted from arbitrary persisted claims. Model edits increment
the service revision; the model revision slot remains null for the current catalog.
No key, endpoint URL, user prompt or raw request is persisted by this cache.

Writes across instances sharing the preferences object are serialized. Identity
checks reject late probes; refresh prunes removed/changed identities. A service edit
while a preferences write is pending fails that refresh without publishing stale
memory. Cached preferences are reloaded after write failure, and later queued work
can retry. Rule revision v2 rebuilds known v1 records from current evidence and discards their
old acceptance observations. Corrupt or future-version documents fail closed, remain byte-for-byte
intact and never bootstrap admission. This is the existing single-process
SharedPreferences storage model, not a multi-process transactional database.

## Frozen per-call output limits

`TaskSpec.maxOutputTokens` is a default ceiling; `TaskRequest.maxOutputTokens` may
further reduce it. Resolution compiles the minimum of these and the capability
output ceiling into `ProviderCallPolicy.maxOutputTokens`. Nonpositive limits fail.
The public Runtime also narrows supplied snapshots against request/spec/capability
limits at start, child retry and recovery. `useConfiguration` intersects the next
policy with the current admitted ceiling: model/reasoning switches cannot raise
it. Recovery retains the minimum recorded phase ceiling even if the caller omits
the original request override. The actual narrowed value is archived in both the
current context and new configuration phase before dispatch. Completed prior
phases retain attribution. Invalid ceilings fail before reserving a run ID.
Every Runtime attempt (initial, HTTP retry, schema repair and resumed run) uses the
frozen policy, not mutable model defaults or SDK-provided extras. The outbound
verifier checks the exact limit as well as reasoning fields. There is no aggregate
Heavy token quota. Old archives without the new policy field retain their previous
capability output limit (or null when previously unspecified).

Quick PR #166 was consumed from main (`5bdcd063`), not copied from a branch. Minimal
adapter wiring is included: title 64; dictionary 8192; context-only lookup 4096;
selection translation carries its original `maxTokens` as input `maxOutputTokens`.
`quickTaskOutputLimit(type, input)` converts this to the public TaskRequest field.
All repairs share that resolved ceiling and Quick remains forced off.

## Initial PR validation

macOS, Flutter 3.47.2, Dart 3.13.2, dart_agent_core 2.1.8.

- From `packages/mm_assistant`: `dart test test/maintained_capabilities_test.dart test/model_policy_test.dart test/capability_probe_test.dart test/task_runtime_test.dart test/quick_tasks_test.dart test/task_routing_test.dart` — 75 passed.
- From `apps/marginmind`: `flutter test --no-pub test/assistant_capabilities_test.dart test/assistant_routing_test.dart test/quick_task_assembly_test.dart test/task_runtime_assembly_test.dart test/runtime_review_regression_test.dart` — 26 passed.
- From `packages/mm_core`: `dart test test/agent_contracts_test.dart` — 4 passed.
- `dart analyze` on changed Dart files and the model-policy directory: no remaining issues. `dart format` and `git diff --check` clean.

No full-suite tests, repository coverage, live-service requests or CI waits/reruns.

## Review regressions

The review attachment `capability_review_regression_test.dart` is included unchanged.
Both assertions failed at the original head (8192 instead of 64; tools:unknown)
and pass with the Runtime and tool-rule corrections. No assertions were removed
or skipped. Same macOS / Flutter 3.47.2 / Dart 3.13.2 environment.

- From `packages/mm_assistant`: `dart test test/capability_review_regression_test.dart test/maintained_tools_wire_test.dart test/task_output_boundary_test.dart test/model_policy_test.dart test/task_runtime_test.dart --reporter expanded` — 43 passed. Run from this package directory so the existing policy fixture paths resolve.
- From `apps/marginmind`: `flutter test --no-pub test/assistant_capabilities_test.dart test/runtime_review_regression_test.dart` — 15 passed (including rule-v1 migration and failed configuration-save rollback).
- Targeted `dart analyze` of changed implementation/test files: no issues; formatting and diff checks clean. No full-suite/coverage run or CI wait.
