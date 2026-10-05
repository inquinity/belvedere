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
- **Full Width is the default, and each window can have its own width.** Documents now use the
  whole window and follow it as you resize. The capped column, called Normal before, is now **Quick
  Look Width**, because it wraps lines where a Quick Look preview does. **View ▸ Content Width**
  changes the front window only and is not saved; **Settings › General › Default content width**
  is the width new windows and tabs open with, and windows that are already open keep theirs. Anyone who had chosen the old Normal width will see Full Width until they
  choose Quick Look Width.
- **Lines now run together by default, as in standard Markdown.** A single new line in the source is
  a space, so a hard-wrapped file reflows to the window the way GitHub and editor previews show it,
  in the app and in Quick Look. If you prefer every new line to show as a line break, choose
  *Keep as typed* in Settings › General › Reading › Line breaks; people who had chosen it before see
  *Join into paragraphs* until they choose it again.
- **Changing the width, font or line-break setting keeps your place** instead of jumping back to the
  top of the document, in the reading view and the editor.
- **Tab in a table cell selects the next cell's text.** Tab, Shift-Tab and Enter move to the
  neighbouring cell with its contents selected, so typing replaces them, as in Word and
  Numbers. Before, the cell was only shaded and nothing was selected.
