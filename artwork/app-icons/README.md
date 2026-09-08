# Production app-icon artwork

The two selected icon families share one generator but use different production
sources:

- `rendered-fold/` is the public `markdown-preview` artwork (concept 1).
- `mdview/` is the private Belvedere artwork (concept 2 / Split Signal) and is the
  design wired into `md-preview/AppIcon.icon`.

Each directory contains:

- `AppIcon.icon/`: an Icon Composer package with a 1024 px RGBA layer and native
  treatment;
- `AppIcon.iconset/`: conventional macOS PNG assets from 16 through 1024 px;
- `AppIcon.icns`: the compiled conventional macOS icon;
- `preview-1024.png`: a flattened preview of the generated design;
- `design-reference.png`: the approved source artwork. For Belvedere this is the
  production master; Rendered Fold retains it only as a visual reference.

Regenerate both sets:

```bash
swift scripts/make-icon.swift
```

Regenerate both sets and install Split Signal into the application:

```bash
swift scripts/make-icon.swift --install-mdview
```

Install Rendered Fold instead — the fallback if upstream adopts Split Signal for
themselves (see `docs/FORK-NOTES.md`):

```bash
swift scripts/make-icon.swift --install-rendered-fold
```

Rendered Fold is drawn from deterministic AppKit paths. Belvedere is resampled
from its approved checked-in master so the dimensional lighting, shadows, glow,
and disconnected B cannot drift between output formats. The generator removes
only the neutral checkerboard connected to the master image's outer edges,
makes that area transparent, and derives every 16–1024 px raster, the Icon
Composer layer, preview, and ICNS from the same processed image.

Refinement prompt summaries:

- **Rendered Fold:** preserve the aubergine field and three coral source lines
  folding into one rendered surface; simplify to one clear fold; flatten excess
  gloss; regularize spacing and rounded ends; remove edge artifacts.
- **Split Signal / Geometric B:** preserve the forest-green field and the size
  and placement of both opaque ivory panels. Keep exactly three left-panel
  grooves and place the custom geometric B in the lower two-thirds of the right
  panel. Use one lowered, circular yellow light behind both panels—not a painted
  seam—so it is visible through the split, the groove ends, and the B knockout,
  while producing no bloom above the panel tops.
