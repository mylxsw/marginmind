# GUL-574 parser verification

Implementation uses pure Dart archive 4.5.2, xml 7.0.1, html 0.15.7,
markdown 7.3.1, characters 1.4.1 and the workspace's crypto dependency.
No platform plugins, subprocess conversion or network code enter mm_book.
Existing license copies for the parser dependencies are in ../gul-570/licenses.

The tests create original binary fixtures in `packages/mm_book/test/fixtures.dart`:
EPUB2/3, nav/NCX, DRM, IDPF/Adobe font obfuscation, fixed viewport, Markdown,
PalmDB/MOBI/EXTH, PalmDOC backreferences, literal/recursive/cyclic HUFF/CDIC,
KF8 skeleton/fragment/FDST/hybrid, obfuscated/compressed FONT and AZW4 PDF.
They also exercise 240 seeded mutations, every truncation of a small MOBI,
source maps, grapheme anchors, resource privacy, CSS, limits and cancellation.

External sample binaries were downloaded only into an untracked working directory.
No new external book or library sample binary is committed. `samples.json`
records original URLs, SHA-256, byte lengths and parsed summaries, sufficient to
refetch and verify the exact bytes. The Gutenberg work is Laozi's historical
public-domain text; the existing EPUB contains its Gutenberg license. libmobi
samples are test inputs from its public source repository; their binary contents
are not redistributed here.

Reproduce external parsing with:

```sh
dart run packages/mm_book/tool/inspect_book.dart <downloaded-sample-paths>
```

Format interpretations were checked against the original implementations:
[KindleUnpack headers](https://github.com/kevinhendricks/KindleUnpack/blob/master/lib/mobi_header.py),
[compression](https://github.com/kevinhendricks/KindleUnpack/blob/master/lib/mobi_uncompress.py),
[KF8](https://github.com/kevinhendricks/KindleUnpack/blob/master/lib/mobi_k8proc.py),
[indexes](https://github.com/kevinhendricks/KindleUnpack/blob/master/lib/mobi_index.py).
They were consulted for binary format behavior; no external source files are
included as runtime dependencies or distributed in this change.

Validation results are recorded in `validation.md` after the checks finish.
