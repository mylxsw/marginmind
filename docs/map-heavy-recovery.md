## Continue a map task

The map pane offers **Continue saved map task** when no task is running, including
after a failed or stopped preview. Select the original generation or expansion
task and confirm. Loading the list never starts model work. A recovered preview
still requires the existing Keep/Apply confirmation and revision check; writes
continue to use proposal receipts, protected-node validation and undo.

The domain journal lives in the study set at `ai-map-tasks/v1/<root-id>.json`.
It records the original command, proposal ID, source revision, frozen RunContext,
stable stage IDs, request fingerprints and repair inputs. Generation also saves
complete chapter points with their original IDs and source fingerprint, so
clearing the optional shared digest cache does not invalidate completed synthesis.
Runtime's `ai-runs/v1` envelopes remain authoritative for paid results and usage.
No credentials are written to either domain metadata or model inputs.

Continuation rebuilds parsers and previews from those results. Completed stages
do not call the model. Partial replies rebuild accepted references and missing
items before repair. Each explicit continuation permits one additional bounded
repair for unresolved content; it does not regenerate accepted content. Frozen
model, policy, prompt and knowledge versions remain attached to the same root.
Changes to the original map or sources refuse continuation before new paid work.

## Concurrent continuation

Each root has one live execution owner, including across ProviderContainers,
isolates and processes. The owner publishes a prepared nonempty directory by
atomic rename under `ai-map-tasks/v1/owners`. Competing recovery instances receive
`mapTaskActive` before dispatch. A later attempt re-reads the stage transactionally
and reuses its recorded run ID/result instead of allocating another child.
Known terminal retries retain earlier run IDs in `previousRuns` for accounting.

Ownership lasts until all executing calls and Runtime handles have settled,
including pending saves after a preview stops. Different roots and parallel
stages inside the owning session can still run concurrently. A separate short
journal transaction serializes only metadata I/O, including between isolates;
it never holds a global lock while waiting for a model result.

There is no expiry that can take a slow request away from a live process.
Only an owner confirmed to have exited can be reclaimed. Unknown liveness,
permission errors and PID reuse fail closed. A lost isolate in a still-live
process therefore requires restarting that process before recovery. Reclaiming
ownership does not authorize model replay: an unknown in-flight request still
requires the continuation confirmation described above.

## Saving failures

When Runtime publishes `save_failed`, the session retains the same pending handle
and displays **Retry saving**. Repeated failures keep that control available.
Retry only flushes the result; it cannot buy another model call or add usage.
The save wait is separate from the model request timeout. Stopping a preview
does not cancel/flush or discard its pending paid result.

After a process exit, a durable Runtime pending checkpoint is recovered and
flushed on explicit continuation. An in-memory result whose disk writes all
failed cannot survive a process exit. A checkpoint without a verified pending
result is therefore treated as an unknown paid request. The continuation dialog
explains that retrying it can call the model again and incur another charge.
There is no automatic replay on startup. Discarding or applying a preview retires
its domain entry; Runtime retains its accounting records.
