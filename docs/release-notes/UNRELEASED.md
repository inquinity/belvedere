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

### Upstream features included in release

- **Expand Table**, above a table in the reading view or the editor, opens it read-only in a full-screen window.
- In a printout, a PDF or a PNG, a table too wide for the page is fitted to it: words stay whole, text wider than the page wraps, and a table that still doesn't fit is scaled down, instead of being cut off.
- The print dialog's Belvedere pane has a Scale setting, applied before the pages are laid out, so a scaled print refits its tables and keeps every column.
- Printing and exporting no longer switch the page you are reading into print mode while the dialog is open.
- Printing a document from Finder opens the print dialog instead of quitting Belvedere.
