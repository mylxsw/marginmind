# GUL-588 macOS evidence

Run `python3 tool/study_notes_evidence.py` on macOS to build and run `integration_test/study_notes_test.dart`. The test imports a temporary Markdown document, makes two source highlights and a map note, then generates a local study note through the setup form. It runs with in-memory repositories and isolated preferences.

The host captures only the test application's native window after each settled frame. This avoids changing application sandbox entitlements. `note-light.png` / `note-dark.png` show the note beside its original document; `export-light.png` / `export-dark.png` show Markdown and Obsidian previews.

The review revision merges the source footer by document identity, sorts and deduplicates PDF pages, restores the study-note toolbar icon and compact cascading menus, and adds quote and own-note source metadata. The refreshed screenshots show the compact toolbar, the document-level footer, and the map-node source line. Widget tests cover PDF page lists, text-document merging, the regular toolbar, submenu selection and sibling hover, and unavailable source records.
