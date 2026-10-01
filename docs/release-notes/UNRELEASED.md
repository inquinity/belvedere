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

- **Belvedere will not change its own files.** Editing or saving a document that is part
  of the application, such as the Acknowledgements page, is refused with an
  explanation, because it would break the app's signature. Save As… to a copy still
  works.
- **Images from an opened folder keep loading after you save** or leave edit mode.
  Before, a document from outside the folder you had opened lost them again.
