# Unreleased

<!--
Add a bullet below in the same commit as any change that alters what a
`brew`-installed user sees or does. A change to what Belvedere carries on top of
Markdown Preview also updates ON-TOP-OF-UPSTREAM.md. At release,
bin/compose-release-notes.sh builds <version>.md from both files; this comment
and the heading above are dropped. See docs/RELEASE-AUTOMATION.md.
-->

- Opening a project folder widens where a document's images may load from: a
  document inside the opened folder can now reach anywhere within it, not just
  its own folder. The Inspector's new **Folder Access** row names the folder in
  effect. Matches [Markdown Preview #337](https://github.com/pluk-inc/markdown-preview/pull/337).
- Clicking a link is no longer bound to the document's folder — matching
  Markdown Preview, the click is the decision. A link to a program, script,
  installer or disk image is still shown in Finder rather than started,
  wherever it points.
