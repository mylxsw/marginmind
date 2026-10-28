# Browser library storage (GUL-543)

Status: implemented for the first usable Web release.

## Decision

Use IndexedDB, with one `files` object store in the origin-scoped
`marginmind-library` database. Keys are existing package paths; values are byte
arrays. `library.json`, `sets/<id>.mmset/studyset.json`, content-addressed PDF,
image and research files retain the native names, JSON format and migrations.
The same `FileLibraryStore` implements domain ports on both hosts. A conditional
import selects either native IO or the small asynchronous file adapter; domain
models and format codecs do not fork.

IndexedDB provides transactional replacement of a named file and is available
without a worker or OPFS-specific file-handle integration. OPFS would suit larger
streaming libraries, but introducing a second async filesystem and worker
protocol is unnecessary for this minimum release. No third-party persistence
plugin is added; `package:web` is the typed browser API binding already resolved
in this workspace (BSD-3-Clause).

## Durability and failure behavior

Startup hydrates committed files before exposing the repository. The shared
per-study-set queue serializes edits; temporary-file rename atomically replaces
the target and deletes the temporary entry in one IndexedDB transaction.
In-memory bytes update only after transaction completion. A failed content write
keeps the previous graph and propagates the error. A crash between temporary
write and rename leaves the previous target intact; unused temporary entries
are ignored by the package scanner.

Each mutation compares current IndexedDB bytes against this tab's cached bytes
within its read/write transaction. A stale tab aborts rather than overwriting
another tab's file; reload the stale tab before editing again. This is conflict
rejection, not collaborative editing. The repository retains its existing
native metadata-write behavior; this change does not add distributed merging.

PDF selection exposes a browser blob URL. Imports immediately copy its bytes
into the package. Stored resources expose session-only blob URLs, recreated
from IndexedDB after refresh. PDFium opens browser PDFs from bytes rather than
calling its native file API. Markdown/OPML export uses `XFile.saveTo` (browser
download). PNG/PDF native encoding, assistant networking and external
credential settings are unavailable in this Web release.

## Capacity, privacy and cleanup

Storage belongs to the exact origin (scheme, hostname and port), not an account.
Changing deployment origin gives a separate library. Browser quota is dynamic;
this implementation promises no fixed capacity and requests no unlimited
storage. Quota failures abort writes. Private browsing, explicit clearing of
site data and browser eviction may remove the library. This is local storage,
not a backup or synchronization service. Users should retain their source PDFs;
text map downloads are not full package backups.

The initial backend holds the library's file bytes in memory, so very large
libraries are outside this minimum release. A later version can replace eager
hydration with lazy reads/OPFS without changing the domain format. Blob URLs
are cached per stored file and revoked when that file changes or the backend
closes. Data and credentials are not sent to a persistence server.

## Validation

`packages/mm_data/test/browser_library_store_test.dart` runs in Chrome against
real IndexedDB. It covers reopening the database, PDF/image bytes, map edits,
metadata, concurrent updates, deletion, failed-write retry, corrupted packages
and snapshot hashes. Native package tests continue to exercise the same codecs
and migrations. The browser UI evidence script and screenshots are under
`docs/evidence/platform/GUL-543/`.
