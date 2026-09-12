# Unreleased

<!--
Add a bullet below in the same commit as any change that alters what a
`brew`-installed user sees or does. A change to what Belvedere carries on top of
Markdown Preview also updates ON-TOP-OF-UPSTREAM.md. At release,
bin/compose-release-notes.sh builds <version>.md from both files; this comment
and the heading above are dropped. See docs/RELEASE-AUTOMATION.md.
-->

- **Arrow keys and space work in Quick Look again.** The preview no longer takes
  keyboard focus, so the keys move the Finder selection and space dismisses the
  preview instead of scrolling the document.
- **Remote images can now be loaded with a click.** Nothing is fetched when a
  document opens, so opening one still never tells its author that you read it.
  A placeholder names the host, and **Load** fetches that one image — no
  cookies, nothing remembered, and the next remote image asks again. **Load all**
  stays local-only, and Quick Look still names remote images without offering to
  load them.
- Settings › Privacy now describes a blocked remote image the way it actually
  appears — a placeholder naming the host — instead of calling it broken.
