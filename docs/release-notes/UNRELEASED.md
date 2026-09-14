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
  preview instead of scrolling the document. The trade: to select and copy the
  rendered text with ⌘A / ⌘C, click into the preview first — until then they copy
  nothing, as in Apple's own text and PDF previews. The **Copy** button still copies
  the Markdown without that click.
- **Remote images can now be loaded with a click.** Nothing is fetched when a
  document opens, so opening one still never tells its author that you read it.
  A placeholder names the host, and **Load** fetches that one image — no
  cookies, nothing remembered, and the next remote image asks again. **Load all**
  stays local-only, and Quick Look still names remote images without offering to
  load them.
- Settings › Privacy now describes a blocked remote image the way it actually
  appears — a placeholder naming the host — instead of calling it broken.
- The toolbar **Save** button is icon-only, like the other toolbar buttons.
- **Security fix.** A crafted Markdown document could close the internal element
  that holds unsanitised content early — by spelling its end tag in uppercase —
  and run script in the preview before the sanitiser saw it, on open or Quick Look
  preview. Belvedere's content policy already blocked such a document from reaching
  the network; the script could still alter the open file through the preview's
  edit bridge. The document body is now escaped so the element cannot be closed,
  whatever the tag's case.
- **New from Markdown Preview 0.0.57:** bare `http://` and `https://` addresses are
  clickable; `.mdx` files open as Markdown, with their JSX, imports and expressions
  shown as text rather than compiled; clicking a folder row in the project navigator
  expands or collapses it; bullet markers keep their spacing; and the full-screen
  toolbar keeps a custom theme colour.
