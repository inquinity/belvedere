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

- **Load** now works for SVG images, including README badges from shields.io. Before, a click fetched the badge and then reported "load failed: not an image". An SVG is shown only as a picture: none of its scripts run and nothing it links to is fetched.
