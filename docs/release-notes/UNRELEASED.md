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
- **Export as EPUB**: *File → Export…* saves a reflowable book, with a table of contents from the headings and each picture as the reader shows it.
- Drag the edge between two header cells to resize a table column, or double-click it to fit the column to its heading. In the Expand Table window the header row stays in view while you scroll.
- **Text alignment** in *Settings → General → Reading*: left, centred, right or justified prose, in the app and Quick Look.
- Math renders live in Edit Mode, and opens to its source when you click it.
- **Show Markdown Source** (*View* menu, ⇧⌘E, or the source button on the formatting bar) edits the plain Markdown text, with nothing hidden or rendered.
- The inspector counts the words and characters of the selected text.
- **Copy as Plain Text** (*Edit* menu, ⌥⇧⌘C) copies the selection without Markdown.
- The file navigator has a filter field, a recent-files toggle and a **+** menu for new files and folders. In a folder Belvedere can only read, it asks before writing, and the permission lasts until you quit.
- Opening a file that is still downloading from a cloud folder shows a Loading panel instead of a blank window.
- Fixed: wrapped inline code no longer makes the page scroll sideways, and a sentence that follows a display formula stays on one line.
