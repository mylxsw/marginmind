# Assistant domain migration (GUL-650, integration in progress)

Production `assistantDependenciesForProvider.runFactory` calls `createPersistentAssistantRun`.
It composes `PersistentTaskAssembly` with the real routing/services/SecretStore and
FileRunStore. There is no direct-model fallback. Explicit translate actions reuse
`quickTaskExecutorProvider(selectionTranslate)` and its frozen off policy.

The domain exports `assistantTaskSpecs` (assistant_chat, conversation_summarize,
document_summarize, research, review_cards), `registerAssistantTasks`,
`assistantTaskKnowledgeBundles` and `assistantTaskKnowledgeRegistry`. The parent
integration should aggregate these specs with the other domains in
`aiTaskRoutingSpecsProvider`; this branch does not replace the shared provider or
PersistentTaskAssembly factory.

The controller remains the only conversation archive writer. `Conversation`
preserves unknown archive fields and migrates routing during its ordinary
load/save lifecycle, rather than a second read-modify-write migration. New
conversations follow settings; choosing/clearing a chat model updates only the
assistant_chat override. Dedicated actions preview their own route and may carry
a per-message override. Conversation summaries persist explicitly selected active
message IDs; replaced branches are excluded.

One AssistantTaskOwner supplies permission, policy, citation and proposal bindings
to the Runtime's SDK agent. It copies trusted history only for the exact prior
model identity, keeps retry checkpoints and mirrors evidence back to the existing
conversation owner. There is no second Agent loop. Review proposals require read
citations and remain pending until the existing controller/executor confirms them.
Research JSON distinguishes body-supported claims, unverified claims, conflicts
and unresolved questions. A metadata citation cannot validate a body claim.
These checks validate provenance, not the truth of a generated claim.

Summaries read the selected source range, split by encoded request size derived
from the frozen capacity, then reduce bounded groups. Every stage validates exact
assigned coverage IDs. Oversized/nonreducing outputs and unread ranges fail
explicitly. Sources and intermediate results remain in the runtime checkpoints;
the final leaf coverage is also retained in the conversation metadata. The
in-memory final result is not yet a durable aggregate job result (see below).

## Public Runtime work required before acceptance

This branch is a partial integration, not a completion claim. It needs the parent
to coordinate these shared contracts, which the domain ownership rules reserve:

- A controlled infrastructure/provider substep API for native_search and
  capability_probe. It must accept a parent-derived context, enforce current
  identity, policy, cancellation and output limits, record actual usage, and
  support diagnostic unknown profiles without granting semantic admission.
  `webSearchProvider` now requires an injected native port; absent that port it
  fails closed. It no longer constructs an untracked native model request.
  RoutingCapabilityProbe still uses its existing controlled connection outside
  AgentRuntime and therefore remains an explicit acceptance gap.
- A deterministic workflow/aggregate lifecycle: a document summary can have many
  successful child stages followed by a failed merge. The current public runtime
  only runs model-backed TaskDefinitions. The root must retain a durable workflow
  checkpoint and final leaf coverage, expose partial status and recover completed
  stages without repurchasing them. Current summary stages are recorded, but the
  first stage is the root; its completed status describes that stage only.
- Typed multimodal input and SDK event/draft bindings on the existing runtime.
  The facade currently publishes validated full answers and tool events. Image
  selections explicitly fail with multimodalRuntimeInputRequired rather than
  silently dropping image content. No alternate streaming Agent is installed.
- Run-panel recovery/configuration controls must bind to this same owner, and
  pending validated results after disk failure need a reachable save retry.
  Current UI shows lifecycle status and offers the existing stop/retry branch
  actions; it does not yet expose arbitrary Runtime resume/configuration phases.

No trusted production profiles are synthesized. No real provider credentials,
model quality, physical device, native application UI or OS Keychain operation
have been validated by the synthetic transports.
