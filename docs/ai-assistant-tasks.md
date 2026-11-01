# Assistant domain migration (GUL-650)

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
explicitly. Sources and intermediate results remain in the runtime checkpoints.
`PersistentAssistantSummary` owns a separate deterministic parent manifest, stage
attempt index, leaf coverage and validated pending/final aggregate. A child
finishing cannot complete the parent. Partial parents resume through immutable
successors; committed children are verified and reused across restarts. Parent
CAS claims precede inference. A pending aggregate save retries storage only.

`AssistantTaskSession` binds pause, resume, model selection and pending-save
retry to the same owner/Runtime handle. Explicit model changes freeze a new
configuration phase without raising the original output ceiling. The controller
is still the only conversation archive writer. Its task record pins the input,
source scope, images, context and any durable configuration intent. Reopening an
archive does not call a model; the latest unfinished answer has an explicit
resume action. A resumed summary uses its stored source snapshot, not newly read
or changed documents. Existing branch retry, references, confirmation and undo
remain controller-owned.

## Runtime ports and network ownership

The production factory consumes the merged `docs/runtime-ports.md` contract.
Authorized local images become `TaskImage` inputs; unknown multimodal capability
is rejected by Runtime. Chat/review drafts consume `modelStarted` resets and
`draftDelta` events with citation buffering. Only `handle.result` supplies the
validated final answer. Structured research/summary JSON is not exposed as prose
drafts. There is one Runtime/SDK Agent, with no direct-model fallback.

Controlled bindings inject `scope.nativeSearch` through the existing network
factory and `webSearchProvider`. Network grants, keyword limits, URL safety,
actual body snapshots and citation checks remain in the existing host/tools.
Search request slots are claimed in the parent checkpoint before Runtime reserves
its provider child. Repeated/recovered requests reconcile that same child.
Pending provider writes use `ProviderSteps.retrySave/recoverSave`; interrupted
children without a durable result fail explicitly rather than repurchasing an
unknown outcome. Pending children are reconciled before parent recovery resumes
inference. Linked provider usage is aggregated once, retaining unknown quality;
workflow parent totals include their verified stage attempts without double
counting the parent aggregate. Totals are archived as `assistant.taskUsage.v1`.

`PersistentTaskAssembly.createCapabilityProbe()` is the public durable probe
entry point; semantic admission remains unchanged. This domain does not alter
shared provider registration or synthesize capability evidence.

## Targeted verification

Package tests cover exact summary coverage, bounded reduction, deterministic
parent recovery/CAS, lost child/parent acknowledgements, pending aggregate saves,
controlled search child reuse, usage aggregation, evidence and review validation.
App tests exercise all five production task routes plus Quick translation over a
loopback SDK transport and FileRunStore, inline image/stream drafts, actual
research search/fetch and review proposal tools, disk reopen without inference,
same-owner configuration phases, pending Runtime result saves, narrow control UI,
and existing controller confirmation/undo behavior.

No trusted production profiles are synthesized. No real provider credentials,
model quality, physical device, native application UI or OS Keychain operation
have been validated by the synthetic transports.
