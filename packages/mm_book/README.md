# mm_book

Pure Dart book parsing. `BookParser.parse(SourceBytes, resolver:, cancellation:)`
selects EPUB, MOBI/AZW/AZW3/AZW4 or Markdown by filename. The individual
`EpubParser`, `MobiParser` and `MarkdownBookParser` adapters remain available.
`EpubParser.parseHtml` is the shared HTML-to-IR entry point for web captures.

No parser reads files, writes staging files, launches tools or requests URLs.
`ResourceResolver` receives package-relative paths for Markdown images; the
caller must restrict resolution to the selected document's import sandbox.
Remote images keep a U+FFFC placeholder and `remoteUrl`, with a diagnostic;
they never reach the resolver. `BookCancellationToken` checks before/after
parsing and between asynchronous resource reads. Run synchronous decoding in
a worker; cancellation of CPU work is owned by the worker's lifecycle.

`BookParseException.kind` distinguishes DRM, damaged input, unsupported
formats/variants, cancellation and configured limits. Limits cover compressed
and expanded bytes, ZIP entries/PalmDB records, CSS rule count, DOM depth,
HUFF expansion work and recursion. ZIP paths, duplicate aliases, symlinks,
header consistency and CRCs are checked. No partially parsed book is returned
on a fatal error. Atomic persistence/cleanup belongs to mm_data (GUL-573).

`Book.toJson()` emits schema/normalization version 1, content revision,
metadata, spine, TOC and hashed resource descriptors. Resource bytes accompany
the manifest separately. `test/fixtures/book-v1.json` is a concrete consumer
example. Existing flat `chapter.blocks` stays usable by mm_reflow;
`chapter.structure` additionally preserves source containers/nesting.
Offsets and source-map destinations are half-open UTF-16 ranges in canonical
text; source ranges refer to decoded DOM text nodes, before whitespace
normalization, not original ZIP/XML bytes. Source-map entries can therefore
map several collapsed source characters to one canonical character. Block
text is separated by LF, cells by TAB, rows by LF; ruby annotation is metadata.
Styles contain the computed cascade with CSS length units retained for the
layout engine's viewport/user-font calculation. Viewport and position/box
properties preserve fixed-layout inputs; this package performs no drawing.

EPUB supports container/OPF, metadata, spine, nav/NCX, archive resources and
IDPF/Adobe font deobfuscation. Font-face family/resource mappings, linked stylesheets and common element/class/id/
descendant selectors participate in the cascade. Unsupported CSS emits
diagnostics; complex selectors/layout, other at-rules and vertical writing are outside
the architecture's CSS subset. MIME detection recognizes raster/font signatures;
XML/CSS resource types retain their package extensions.

MOBI reads PalmDB, PalmDOC/MOBI/EXTH, UTF-8/Windows-1252, uncompressed,
PalmDOC and HUFF/CDIC text, FONT resources, trailers and filepos links. KF8
uses INDX/TAGX/IDXT skeleton/fragment reconstruction and FDST flows, rewrites
kindle resource/position URLs and prefers the KF8 section in hybrid files.
Missing required indexes and unsupported variants fail explicitly. KFX and
nonzero encryption types are rejected. Print Replica returns `Book.pdf` for
the existing PDF importer instead of pretending its PDF is reflow text. Multi-PDF Print Replica books
are rejected explicitly rather than silently dropping later PDFs.

Tests construct small original samples in Dart; no copyrighted book binaries
are included. External interoperability checks and provenance are documented
in `docs/evidence/gul-574/README.md`. `tool/inspect_book.dart` accepts local
sample paths and prints a JSON summary for each successfully parsed book.
