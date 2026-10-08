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

- **A file that changes on disk now reloads, every time.** Belvedere could stop noticing changes to an
  open file if another app deleted it and wrote it back a moment later, as some tools and syncing
  do; the window then kept showing the old text until you closed and reopened the file. It now keeps
  looking until the file is back.
- **Changes made by another app while you are editing are no longer missed.** With nothing unsaved,
  the editor takes the new text. With unsaved edits, a sheet asks what to keep: **Save As…** (your
  edits go to a new file and the other app's version stays), **Overwrite** (your edits replace the
  file), **Discard My Edits** (the file's text replaces them) or **Cancel**. Nothing is replaced until
  you choose.
- **Wide tables are readable in the editor.** In edit mode a table with one wide column squeezed the
  others to a letter each ("I" over "D"); each column now keeps at least its longest word, as in the
  reading view.
