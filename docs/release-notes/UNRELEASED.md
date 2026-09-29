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
