<!--
Everything Belvedere changes on top of the Markdown Preview release it is built on,
written for someone deciding whether to install it. bin/compose-release-notes.sh
copies this into every release's notes under "Changes on top of Markdown Preview
<version>", and generates the heading, the "Based on" line and the list of later
upstream commits itself.

Keep it true, the same way as README.md: a change to what Belvedere carries — a new
fork change, or a carried fix that upstream has since merged and released — updates
this file in the same commit. When an item under "Ahead of Markdown Preview" lands in
an upstream release that main has synced, delete it here.

HTML comments like this one are dropped from the release notes.
-->

Belvedere is Markdown Preview with its network connections removed and its handling
of untrusted documents tightened. Reading, editing, printing, PDF export and Quick
Look are upstream's work.

**It never connects on its own**

- No crash reporting and no usage analytics. The code that sent them is gone, so
  Settings › Privacy states this instead of offering switches.
- No automatic updates, and no *Check for Updates…*. New versions come through
  Homebrew: `brew upgrade --cask belvedere`.

**A document cannot reach the network, or files outside its folder**

- Remote content — images, stylesheets, fonts, scripts — is blocked in the document
  window, the editor and Quick Look. A remote image shows as a placeholder naming its
  host, so opening a document never tells its author that you read it.
- Images load only from the document's own folder. One outside it shows as a
  placeholder with a **Load** button: one click, checked to be a real image first,
  and not remembered. Quick Look names these without offering Load.
- A link outside the document's folder does nothing when clicked, and has no context
  menu.
- A document cannot draw form controls — no text fields, dropdowns or other inputs
  that could imitate a sign-in prompt. Task-list checkboxes still work.

**Ahead of Markdown Preview**

Proposed to Markdown Preview and carried here until it merges them:

- A **Save** button, lit whenever the document has unsaved changes. Leaving edit mode
  with unsaved changes asks **Save / Revert… / Continue**, with a setting to keep the
  old silent exit; **Save As…** and **Revert to Saved** work, and ⌘S works after
  leaving edit mode.
- Mermaid diagrams draw in the document window. On Markdown Preview's current `main`
  they collapse to an empty gap.

**Its own app**

- Named Belvedere, with its own icon and bundle identifier, so it installs alongside
  Markdown Preview instead of replacing it.
- The command-line tools installer is removed, along with the permission to control
  Terminal that it needed.
- The About box states the network posture above and credits Markdown Preview.
- Signed with Belvedere's own Developer ID, notarized by Apple, and distributed
  through the Homebrew tap `inquinity/tap/belvedere`.
