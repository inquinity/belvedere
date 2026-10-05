# Unreleased

<!--
Add a bullet below in the same commit as any change a Belvedere user would
notice or want -- the test for every line is whether a reader cares. Not what
Belvedere declined, not upstream's version numbers, not About-box or license
housekeeping. Changes that come from a Markdown Preview sync go under a
"### Upstream features included in release" heading. At release,
bin/compose-release-notes.sh builds <version>.md from this file; this comment
and the heading above are dropped. See docs/RELEASE-AUTOMATION.md.
-->

- **File ▸ Open Folder….** A folder picker of its own, which also works with no
  window open. Dropping a folder on the Dock icon opens it too, and the button in
  Go to File's empty state uses the same picker.
- **Search for Document is now Go to File…**, in the Go menu, still on ⇧⌘O. It jumps to a
  file in the opened folder by name, so the new name says what it does and leaves ⇧⌘F free
  for a search of file text later.
- **Tab in a table cell selects the next cell's text.** Tab, Shift-Tab and Enter move to the
  neighbouring cell with its contents selected, so typing replaces them, as in Word and
  Numbers. Before, the cell was only shaded and nothing was selected.
- **Wide tables are readable again.** Since 1.3.0, a table with one long column squeezed the short
  columns to a single letter per line. Short columns now keep their words and the table scrolls
  sideways instead.
