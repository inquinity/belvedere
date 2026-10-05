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

- **Tab in a table cell selects the next cell's text.** Tab, Shift-Tab and Enter move to the
  neighbouring cell with its contents selected, so typing replaces them, as in Word and
  Numbers. Before, the cell was only shaded and nothing was selected.
