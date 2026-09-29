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
  previews. After updating, you may need to choose your appearance and theme
  once more.
- **Acknowledgements, in the About box and Settings › About.** It lists
  Markdown Preview and every open-source component Belvedere includes, with the
  license each is used under, linked to that license. The app also now ships
  every license text in full; Markdown Preview's own notice and swift-cmark's
  were missing before. The About box's "Forked from" line is gone, since
  Acknowledgements credits Markdown Preview instead.
