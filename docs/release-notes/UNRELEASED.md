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

- Command-1 to Command-8 switch to that tab of the window, and Command-9 to the last tab, as in Safari.
- A document can load only images and other media from its folder. Before, a page could be made to read any file there, such as a `.env` file or a private key, if something got past the sanitizer.
- Links to headings, such as `[Setup](#setup)`, now scroll to the heading in Quick Look. Repeated headings are numbered as on GitHub.
- References written `\[18\]` or `\[3, 4\]` show as text instead of as an equation.
- Export as PNG shows the whole document instead of an enlarged corner of it.
- Ordered lists numbered 100 and up, and footnotes numbered 10 and up, keep each number on one line.
- Images keep their description as alt text, for screen readers and images that fail to load.
- Zooming in or out no longer makes the page jump sideways or down for a moment.
- Clicking in the document or the search field no longer moves search on to the next match.
- On macOS 27, the formatting bar no longer presses against the tab bar, and the selected file or heading in the sidebar keeps its normal text.
