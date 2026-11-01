# Task runtime integration (GUL-647)

`SdkAgentRuntime` implements the frozen `AgentRuntime` port using `dart_agent_core 2.1.8`'s `StatefulAgent`. Register a `TaskDefinition<T>` once for each domain's `TaskSpec`, then pass that exact spec in requests. The definition owns input validation, output decoding, completion validation, encoding and checkpoint restoration. Invalid/missing scope is never reported as completed. Domain migration stays with the S3/S4 owners.

`createPersistentTaskRuntime` in the application assembles `FileRunStore` at `<study-set>/ai-runs/v1/`. Supply a `loadModel(RunContext)` callback that resolves the **frozen service/model identity**, verifies that the service is still enabled, and reads its current credential from the existing secret store. Return its service revision. Throw `ConfigurationFailure` when unavailable; dispatch pauses. Do not resolve the task's default again. The factory has a real SDK → guarded HTTP → file-store integration test with a loopback fixture; it is not a fake-only storage adapter.

For stateful tools/hooks, use `TaskDefinition.createBindings(context, sdkState, input)` to build fresh permission/citation/proposal hooks per run. `tools`/`hooks` on the definition are for stateless bindings only. Tool exposure is the intersection of host-provided tools, the task allowlist and pinned knowledge permissions. Preserve existing Policy/Proposal/atomic-commit hooks. The runtime never applies domain writes itself.

Quick tasks load no tools, skills, plans or knowledge prompts and permit at most one repair. Every initial call, transport retry and schema repair is compiled against the frozen capability identity, uses `policyModelConfig`, and enters `connectAssistant(callPolicy: ..., retryRequests: false)`. The runtime owns up to two retries for received 429/5xx; it does not retry authentication errors, dropped connections or partial results. Domain schedulers must disable their own transport retry multiplication. Transport retries and schema repairs are distinct attempt records.

Heavy tasks use the same SDK harness with registered tools and versioned knowledge. `standardKnowledgeRegistry()` and `standardKnowledgeVersions(spec)` provide the initial task-specific pack set. Completed child stages should be separate runs with `context.child(id)`; this keeps parent model, permissions/range and provenance. `schema_repair` is counted in the parent attempt ledger. Context compaction is deterministic archival, not a hidden LLM request, so it consumes no tokens. A future model-based compactor must enter this runtime with `RunPurpose.contextCompact` and a parent-derived context.

The initial task entry uses the SDK's non-streaming full-message path. `events` carries durable lifecycle transitions; domain output is released after validation. The existing conversation facade retains streaming. Domain migrations that need token-by-token drafts must extend this adapter rather than call a raw client. This change does not claim that the unrelated translation/map/note entry points have already migrated.

## Lifecycle and recovery

- `pause()` stops the next dispatch; an already in-flight response can finish validation and commit. `cancel()` signals cancellation and races providers that ignore it; late responses cannot commit.
- Disk errors retain the encoded validated result. `events` reports `paused/save_failed`; `persistenceError` is available in memory. `resume()` retries saving, not model generation. A durable validating checkpoint contains the pending result, so restart can also finish committing without repurchasing it.
- `recover(request, context)` checks task/input/schema/prompt/SDK identity and persists `interrupted` without any model request. Explicit `resume()` is needed. A crash with no durable validated result does not auto-replay an unknown request or pending tool call: prior SDK history is archived and a fresh user-authorized attempt begins. Domain write receipts remain governed by the existing idempotent commit layer.
- `useConfiguration(nextContext)` requires pause, no in-flight call and `phase + 1`. It appends a configuration phase, preserves prior attribution and archives old protocol history. The UI must explicitly request this action. Subsequent settings edits alone never rewrite a run snapshot.
- `RunReader.resumable()` exposes model references to routing usage queries; `loadResult()` reads committed staging output. Unknown envelope versions and invalid/linked paths fail closed without overwriting data. CAS and atomic manifest/result replacement protect duplicate completion and concurrent stores.
- `RunUsage.quality` is reported/estimated/unknown; absent usage is unknown, not actual zero cost. All-zero SDK default usage without provider provenance remains unknown.

## Conversation correctness

The compatibility facade now uses a persistent evidence ledger, immutable SHA-256 evidence identities and message → marker/evidence mappings. Changing a document or a page excerpt cannot rebind an old marker. Legacy histories without reliable mappings are archived, never guessed; data-only archive recall removes obsolete short citation markers. The stored original protocol blocks are unchanged.

`TurnContextCompressor` archives complete older user/tool rounds. The assistant exposes bounded `read_history` recall; no source text is inserted into system instructions. All read/search results share the request budget. Oversized branch/search results expose JSON fragments and `nextCursor`; source paragraphs admit only returned text into the evidence registry. `read_more` cursors belong to the current run. Partial page rows expose a continuation cursor. Whole jobs have no newly imposed total-document quota.

Retry forks from the checkpoint immediately before the target question, archives the old visible/model branch and retains execution receipts. Later questions are absent from the new active branch and actual model request. Model identity changes archive signed history rather than replay it into another model. Translate skill prompts no longer inherit the summary-style instruction.

## Limits and local evidence

General Responses encrypted-reasoning replay and Gemini multi-tool signature replay remain blocked by S0's `historyReplay` admission. No capability was upgraded on the basis of a fake. No real provider credential/model, browser store or physical mobile device has been validated here. Request capacity uses a conservative character estimate when tokenizer information is unavailable; oversized current inputs require domain splitting instead of silent truncation.

Local environment: macOS arm64, Flutter 3.47.2, Dart 3.13.2. Named regression files cover actual retry request history, evidence identity, 65,000-character history/branch inputs, task prompt isolation, SDK Quick repair/Heavy tools, pause/cancel/configuration phases, missing ranges, save failure/crash recovery, file CAS/idempotency/version/path safety, and production loopback HTTP + persistent storage. No full-suite test, global coverage or CI rerun is required by this change.
