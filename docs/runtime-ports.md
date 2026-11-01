# Public Runtime ports (GUL-657)

This contract extends the S2 runtime under `ai-agent-refactor-plan.md` v1.1. It does not register domain tasks or admit any additional production model profile. The SDK remains pinned to 2.1.8 and owns the single Agent loop, message accumulation, tool rounds and signed/opaque history.

## Multimodal input and events

`TaskRequest<T>` adds optional `images: List<TaskImage>` and `streamDrafts: bool` (default false). Existing `AgentRuntime.start`, `SdkAgentRuntime.recover`, and `RunHandle` consumers remain source-compatible. `TaskImage` accepts inline base64 plus PNG/JPEG/WebP/GIF MIME; remote image URLs are deliberately excluded. The host must authorize/read the source using its existing scope before supplying the bytes.

The runtime sends images as SDK `ImagePart`s beside the JSON user input, never in system instructions. Images travel on the initial turn, remain in SDK history on repair, and are reattached on explicit interrupted recovery. Image data and history are stored in the existing private, versioned RunStore checkpoint, never diagnostics. Recovery and unfinished retries reject changed images even if a caller reused the input fingerprint. Unknown multimodal support is rejected at dispatch even when the domain forgot to request that capability in its spec. This does not relax thinking evidence or the Responses/Gemini history replay restrictions.

The existing context compressor still archives complete turns, including tool IDs, signatures and opaque blocks. Interrupted recovery archives the interrupted SDK history and starts a fresh input; it does not replay pending tools. Large inline images are subject to the conservative existing serialized-input capacity check and can return `inputRequiresSplit`; there is no new image tokenizer or claim of model-specific vision capacity estimation.

With `streamDrafts: true`, consume `handle.events`:

- `RunEventKind.modelStarted`: reset the draft for the new model attempt/repair/tool round.
- `draftDelta`: append `event.draft`. Text only, unvalidated; thinking/signatures and raw tool arguments are not UI events.
- `toolStarted` / `toolCompleted`: tool progress; the start stage names the tool.
- `lifecycle`: existing lifecycle events. Only `handle.result` is the domain-validated result; completed is published after the final atomic write.

A partial stream is never automatically retried once a chunk has arrived. Before the first chunk, existing bounded 429/5xx transport retry applies. Cancellation suppresses late drafts/results. A terminal save error leaves the validated result pending; `resume()` retries persistence without purchasing another result. Recovery of a pending result similarly never calls the model. Event sequences are monotonic but not contiguous: each dispatch persists a reserved sequence watermark so a restart cannot reuse an already emitted ephemeral draft ID. Do not assume sequence equals manifest revision.

Output ceilings remain the minimum of request, spec, frozen policy, capability and previous phase limits, on both SDK generate and stream paths. Changing configuration cannot raise the original ceiling.

## Controlled provider steps and #170 integration

`SdkAgentRuntime` creates `ProviderSteps(store: store)` by default. Native search is a single infrastructure SDK generate request, not another Agent or tool loop. It uses the same guarded connection, freshly loaded credentials, exact service revision, compiled thinking policy and provider payload verification. The SDK has no typed native-search tool in 2.1.8, so this closed adapter adds only Anthropic `web_search_20250305`, Responses `web_search_preview`, or Gemini `google_search` to the SDK-encoded request. It never adds arbitrary model extras.

Use the optional `TaskDefinition.createControlledBindings` factory:

```dart
createControlledBindings: (scope) {
  // scope.context/state/input have the same ownership as old createBindings.
  // Pass scope.nativeSearch to the host's existing authorized network factory.
  // On PR #170's consumer interface:
  final search = webSearchProvider(
    settings: settings,
    model: model,
    modelKey: modelKey,
    nativeSearch: scope.nativeSearch,
  );
  return existingPermissionAndCitationBindings(scope, search);
}
```

`webSearchProvider(nativeSearch: ...)` is the **#170 consumer signature**, not a change to the domain files in this PR. The public port supplied here is a ready `SearchProvider`; it can also be used directly by the host network factory. Existing `createBindings(context, state, input)` continues to work. If both factories are supplied, controlled bindings take precedence. `RuntimeRunHandle.nativeSearch` exposes the same live-parent port for hosts that assemble outside the registry.

The host retains network grants, search mode selection, short-query policy, page fetching and citation verification. This adapter is not an authorization grant. It returns discovery URLs from provider result/annotation/grounding fields only, filters URL syntax through `UrlPolicy`, and leaves snippets empty; discovery hits cannot become cited evidence without the existing fetch/validation flow. Unverified tool profiles, Quick tasks and unsupported protocols fail closed.

Each invocation reserves a child ID in parent SDK metadata (`runtime.providerChildren.v1`) before dispatch. The child inherits the current parent identity, phase, branch, scope and cancellation. Its output limit is at most the already narrowed parent limit and 1024. Active substeps block parent configuration changes. Child manifests use `stage: nativeSearch`, retain `parentRunId`, and record actual reported input/output/reasoning usage; missing or cancelled usage stays unknown. Parent usage excludes child tokens to avoid double counting: aggregate the linked children when displaying a task total.

`ProviderSteps.retrySave(runId)` retries a pending write in-process. `recoverSave(runId)` commits a durable pending result after restart. Neither dispatches a model request. In-flight interrupted steps are not automatically replayed. Reusing an existing child ID fails rather than silently buying another search. Callers must reconcile failed steps explicitly.

## Capability probes and production assembly

`RoutingCapabilityProbe` now uses the same ProviderSteps lifecycle and usage record; its public constructor and `probe()` remain compatible. The result additionally exposes `runId` and `usage`. A diagnostic unknown profile may issue a 16-token heavy/auto connectivity request under an explicit omitted policy, never an off/Quick request. A successful response records wire acceptance only; it cannot change semantic admission, model profiles or Quick availability. Catalog identity is checked again after key retrieval and after the response.

`PersistentTaskAssembly.createCapabilityProbe()` supplies the runtime's study-set `FileRunStore`, secret store and resolver. Its successful and failed provider steps are durable alongside task runs. Standalone legacy/settings `RoutingCapabilityProbe` construction still works and retains records on `probe.steps.records` for that instance; it has no study-set owner and does not claim durable study-set storage. Hosts requiring durable records use the assembly factory or inject `ProviderSteps(store: ...)`. No sibling settings/provider registration is changed here.

`createPersistentTaskRuntime`, `PersistentTaskAssembly.start`, and `persistentTaskAssemblyProvider` already construct the extended runtime, so images, streaming and controlled bindings require no replacement factory or independent Agent.

## Verification and limits

Named offline coverage (43 passing cases: 4 core, 37 Runtime/probe, 2 production assembly):

- `packages/mm_core/test/agent_contracts_test.dart`: existing SDK-independent task/run protocol compatibility.
- `packages/mm_assistant/test/runtime_ports_test.dart`: actual SDK image wire bodies for Chat/Anthropic/Responses/Gemini; streamed deltas and real SDK signed/opaque persistence; cancellation, late events, partial-stream failure, transport retry; pending recovery and write retry; parent-bound native search, all three native wire formats, identity, usage, ceilings and admission refusal.
- `packages/mm_assistant/test/task_runtime_test.dart`: existing start/recover/retry/configuration and output-ceiling regressions.
- `packages/mm_assistant/test/capability_probe_test.dart`: unknown remains unknown, off policy, cancellation and changed service identity.
- `apps/marginmind/test/task_runtime_assembly_test.dart`: production localhost SDK connection, inline image streaming and FileRunStore, durable probe factory, unknown-profile refusal after successful probe.

Fixtures establish protocol/lifecycle behavior, not model quality. No external model service, real image understanding, native-search service behavior, device UI, latency or semantic thinking-off claim was verified. No production capability profile was broadened. No full-suite/coverage run or CI trigger/rerun/wait is part of this delivery.
