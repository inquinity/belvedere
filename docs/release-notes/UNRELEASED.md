# Unreleased

<!--
Add a bullet below in the same commit as any change that alters what a
`brew`-installed user sees or does. A change to what Belvedere carries on top of
Markdown Preview also updates ON-TOP-OF-UPSTREAM.md. At release,
bin/compose-release-notes.sh builds <version>.md from both files; this comment
and the heading above are dropped. See docs/RELEASE-AUTOMATION.md.
-->

- **The app and its Quick Look extension can now share settings.** Releases
  through 1.2.4 were signed without access to the storage the two share, so
  appearance and theme changes made in Belvedere could not reach Quick Look
  previews. Your existing reading settings — appearance, theme, font, spacing
  and custom colors — carry over when you update.
- **Tighter folder boundary for a document's images.** An image is now checked
  and read as one step, so a file swapped for a link at the wrong moment cannot
  slip past the boundary, and a document cannot make Belvedere open a device or
  pipe and hang. The boundary also follows a document that is renamed or moved
  while open, and applies in the editor when you open a folder mid-edit.
- **Line breaks.** Settings › General › Reading lets you choose how a single
  new line in the source is shown: *Keep as typed* (the default) or *Join into
  paragraphs*, with an ⓘ that explains both. Applies to the reading view and
  Quick Look.
- **Acknowledgements, in the About box and Settings › About.** It lists
  Markdown Preview and every open-source component Belvedere includes, with the
  license each is used under, linked to that license. The app also now ships
  every license text in full; Markdown Preview's own notice and swift-cmark's
  were missing before. The About box's "Forked from" line is gone, since
  Acknowledgements credits Markdown Preview instead.

### From Markdown Preview 0.0.59 to 0.0.63

**New**

- **Search for Document** — File › Search for Document… (⇧⌘O) finds a file in the
  open folder by part of its name.
- **Code blocks** have rounded corners, a language label, and buttons to copy the
  code or wrap long lines.
- **Formatting controls** float over the document in Liquid Glass on macOS 26, with
  native popovers.
- **Documents open faster.**
- **The reading view is read-only.** Tick tasks and edit tables in Edit Mode, where
  task checkboxes are now clickable and lists continue as you type.
- **Themes with fixed colors** keep the light or dark appearance they were made for.

**Fixed**

- Scrolling no longer stalls over wide content in the reading view.
- Colors follow the system when it switches between light and dark on its own.
- The Original theme remembers its appearance, and document backgrounds match the
  system's.
- List markers and list accents take the theme's colors.
- Dotted arrows in Mermaid diagrams draw correctly.
- The back and forward toolbar buttons look right again.
- In Edit Mode: search highlighting and navigation work; the first click lands the
  cursor where you expect; selecting with the pointer no longer jumps while Markdown
  syntax is showing; text size changes apply; and Chinese, Japanese and Korean input
  methods compose correctly.
- Switching between reading and editing keeps your place, without overlapping text.
- Switching files in the sidebar while editing keeps the right document in the
  editor, and pending edits are saved when you leave Edit Mode.
- Formatting buttons align on macOS 27, and the sidebar toolbar and editor
  background are right on macOS 15.
- In Search for Document, long paths shorten in the middle, and the search field and
  sidebar collapse line up.
