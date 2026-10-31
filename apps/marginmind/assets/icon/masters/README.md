# Foliarc icon masters

- `paper_arc.png`: B / Paper Arc, the default app identity.
- `leaf_folio.png`: A / Leaf & Folio, optional.
- `folded_f.png`: C / Folded F, optional.

All three use the name **Foliarc**. The square masters intentionally have no
rounded outer corners or transparency; iOS supplies the mask. The packaging
script adds the macOS mask and padding and exports the other required sizes.
Flutter bundles only the three small previews, not these masters.

Generated with the built-in imagegen tool from the approved comparison board
on 2026-10-31. The approved board is `design/branding/foliarc/concepts.png`;
exact per-master prompts are in `prompts.json`. Each was generated separately
with this prompt template:

> Extract and faithfully reproduce only the [middle / left / right] app icon
> from the Foliarc comparison board. Preserve emblem geometry, proportions,
> colors, paper folds, material texture and lighting. Output one square opaque
> full-bleed master, at least 1024×1024. Extend the tile background to all four
> corners; remove the outer rounded mask, presentation margins, text, labels,
> other icons and exterior shadow. Center the emblem at the reference scale.
> Do not redesign or simplify the emblem.

Regenerate platform files with `./tool/icons.sh` (Python 3 + Pillow), or
`uv run --with pillow python tool/icon/generate_icon.py`.
