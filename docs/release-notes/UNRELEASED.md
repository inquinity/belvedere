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
- **Belvedere is English only.** The Chinese translation is removed, because no one here can keep it
  current and a half-translated interface is worse than a consistent one. Documents in any language
  still display normally.
- **Lines now run together by default, as in standard Markdown, and each window can choose.** A single
  new line in the source is a space, so a hard-wrapped file reflows to the window the way a README
  shows on GitHub, in the app and in Quick Look. The setting is now **Single new lines**, with
  **Reflow (like a README)**, the default, and **Break (like a comment)**, which shows every new
  line as a line break. **Settings › General** holds the default for new windows and tabs, and
  **View › Single New Lines** changes the front window only, without saving it. Anyone who had
  chosen the old *Keep as typed* sees Reflow until they choose Break again.
- **Changing the width, font or line-break setting keeps your place** instead of jumping back to the
  top of the document, in the reading view and the editor.
- **Tab in a table cell selects the next cell's text.** Tab, Shift-Tab and Enter move to the
  neighbouring cell with its contents selected, so typing replaces them, as in Word and
  Numbers. Before, the cell was only shaded and nothing was selected.
- **⌘N always opens a new window.** With *Prefer tabs* on in macOS, or Belvedere's own *Open documents in
  tabs*, a new document used to join the front window as a tab. ⌘T is still the way to ask for a tab.
- **Hover a link to see where it really goes.** A small bar at the bottom of the window shows a link's
  actual destination, as a browser's status bar does, not the words the document used for it. A web
  address keeps its whole host, a relative link shows the file it points to, and an internationalised
  address appears in its safe `xn--` form.
- **Go to File no longer offers names that only contain your letters scattered about.** Typing `man`
  used to offer `remote-beacon.md`. Abbreviations such as `ug` for `user-guide.md` still work.
- **A clearer outline setting.** *Highlight outline section under the pointer* now explains itself with an
  info popover in Settings.
