# Reflow validation probe

This standalone laboratory app is not the product reader. Book buttons select the
three original EPUB fixtures. The book icon changes chapter; chevrons change page;
Aa toggles 16/22px; arrows toggle continuous scrolling. Drag in the text to select
and retain a highlight across font changes. Selection handles and cross-page drag
are not implemented.

From this directory, run `flutter run -d <device> --profile` for interactive use.
For the reproducible benchmark, build with `--dart-define=BENCHMARK=true`; see
`../../../docs/evidence/gul-570/README.md` for collection commands, raw results,
licensing, known rendering gaps and the current No-Go decision.

Scientific viewport/font/sample constants are deliberately distinct from the
product presets in phase-4-ui.md. The prototype does not register product commands.
