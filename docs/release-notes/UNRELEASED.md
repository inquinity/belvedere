# Unreleased

Add a bullet here in the same commit as any change that alters what a
`brew`-installed user sees or does. At release, this file is renamed to
`<version>.md` and a fresh stub takes its place. See `docs/RELEASE-AUTOMATION.md`.

- A **Save** button in the toolbar, next to Edit, lit whenever the document has unsaved
  changes — in edit mode or after leaving it.
- Leaving edit mode with unsaved changes now asks **Save / Revert… / Continue**. Continue,
  also on Escape, keeps the changes unsaved as before; Revert… asks for confirmation first.
  To keep the old silent behaviour, turn on Settings › General › Editing › *Leave edit mode
  without asking to save*.
- **File › Save As…** now works for any open document, and **Revert to Saved** (⌘R)
  whenever there are unsaved changes. Both were always disabled before.
- **⌘S** now works after leaving edit mode with unsaved changes. Before, the only way to
  write them was to close the window.

From upstream Markdown Preview, through its 0.0.56 release and the changes after it:

- The system type scale and semantic colours, code highlighting done at render time,
  and **Copy as Source**.
- A new reading layout, with better alignment for right-to-left text, and tighter
  reader margins as an option.
- Obsidian-style `==highlight==` syntax.
- The sidebar has a pane picker and the system sidebar toggle in place of its pulldown.
- A setting to open Markdown links in new windows; a working link context menu (Open
  Link, Open Link in New Window, Copy Link); and the Window menu tells apart documents
  with the same file name. In Belvedere, a link outside the document's folder gets no
  context menu, just as clicking it does nothing.
- Optional highlighting of the outline section under the pointer.
- Simpler application-menu grouping, and fixes to toolbar and search-bar backgrounds
  on macOS 15 and 26.
