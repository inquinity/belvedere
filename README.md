<h1 align="center">Belvedere</h1>

<p align="center">
  <img src="docs/app-icon.png" width="128" alt="Belvedere icon" />
</p>

<p align="center">
  Belvedere is a native macOS app for reading Markdown files — fast, no Electron, no browser
  tab — hardened so that opening a file someone else sent you is safe by default: nothing in
  a document can reach the network, run something, or fake a sign-in prompt.
</p>

<p align="center"><img alt="Platform" src="https://img.shields.io/badge/platform-macOS%2015%2B-blue" />&nbsp;<img alt="Swift" src="https://img.shields.io/badge/swift-6.0-orange" />&nbsp;<img alt="License" src="https://img.shields.io/badge/license-MIT-green" />&nbsp;<img alt="Latest release" src="https://img.shields.io/github/v/release/inquinity/homebrew-tap?label=belvedere" /></p>

---

> Drop a `.md` on the icon (or set Belvedere as your default handler) and get a clean,
> scrollable preview with a real document outline — and nothing the document does reaches
> the network.

## Installation

```sh
brew tap inquinity/tap
brew trust inquinity/tap          # or: brew trust --cask inquinity/tap/belvedere, to trust only this cask
brew install --cask belvedere
```

`brew tap` adds [`inquinity/homebrew-tap`](https://github.com/inquinity/homebrew-tap) as a
software source — it's a public repository you can read before trusting it. `brew trust`
records that review: without it, `brew install` refuses to load a cask from a non-official
tap at all (`Error: Refusing to load cask … from untrusted tap …`). Homebrew records where
the app came from either way, and `brew upgrade --cask belvedere` is how updates arrive
(there is no auto-updater — see below). Each release is signed with a Developer ID and
notarized by Apple, so Gatekeeper verifies it before install without a manual override.

You can also download the latest release directly, as a DMG, from the tap's
[Releases](https://github.com/inquinity/homebrew-tap/releases) page.

## Screenshots

<p align="center">
  <img src="docs/screenshot-main.png" width="820" alt="Main window with document outline sidebar" />
</p>

<p align="center">
  <em>Edit Markdown directly with a native formatting toolbar:</em>
</p>

<p align="center">
  <img src="docs/screenshot-edit-mode.png" width="820" alt="Edit Mode with document outline and Markdown formatting toolbar" />
</p>

<p align="center">
  <em>Quick Look preview — spacebar a <code>.md</code> in Finder:</em>
</p>

<p align="center">
  <img src="docs/screenshot-quicklook.png" width="640" alt="Quick Look preview from Finder" />
</p>

<p align="center">
  <em>Customize the toolbar — drag in Print, Copy, Zoom and the rest from <em>View → Customize Toolbar…</em></em>
</p>

<p align="center">
  <img src="docs/screenshot-toolbar-customize.png" width="820" alt="Native macOS toolbar customization sheet showing draggable items" />
</p>

## Belvedere

Reading, editing, printing, PDF export and Quick Look are the core experience, and work the
way you'd expect from a native Mac app. Everything below is what's added on top:

**It never connects on its own** — no crash reporting, no usage analytics, no auto-updater.
The code that would have sent any of that is gone, not just disabled; new versions arrive
only through `brew upgrade`.

**A document can't reach the network, or read files outside its folder, just by being
opened.** Remote images, stylesheets, fonts and scripts are blocked in the app, the editor,
and Quick Look — a remote image shows as a placeholder naming its host instead of loading,
so opening a document never tells its author that you read it. Local images load from the
document's own folder, or from a wider folder you explicitly opened; anything outside that
boundary shows a placeholder with a one-click, not-remembered **Load** button.

**A document can't draw a fake sign-in prompt.** Text fields, dropdowns, and other form
controls are stripped from rendered content — a `<form>` that survives sanitization
elsewhere as inert markup renders as nothing here. Task-list checkboxes still work.

**A link never runs or installs something on a click.** A link to an app, script, installer,
or disk image is shown in Finder instead of started, wherever it points. Links to ordinary
documents open as usual.

**A Save button** — in the toolbar, lit whenever the document has unsaved changes. Leaving
edit mode asks Save / Revert… / Continue instead of discarding silently; ⌘S and Save As…
work after leaving edit mode too.

## Features

- **Native rendering** — `WKWebView` pipeline backed by [swift-markdown](https://github.com/swiftlang/swift-markdown), with heading anchors and link handling. Bare `http://` and `https://` URLs are clickable in the app and Quick Look previews.
- **Edit Mode** — edit Markdown in place with a formatting toolbar for headings, emphasis, lists, quotes, code, and links. Toggle it from the toolbar or with <kbd>⌘E</kbd>.
- **Mermaid diagrams** — fenced `mermaid` code blocks render as diagrams in both the app and Quick Look previews, using a bundled renderer so previews work offline without a CDN request.
- **Math equations** — LaTeX inline (`$x_1 + x_2$`), display (`$$\int_0^1 x^2\,dx$$`), and fenced `math` blocks render with a bundled KaTeX. Selecting a rendered formula and copying yields the original LaTeX source.
- **Document outline** — sidebar TOC that mirrors your headings; click to jump.
- **File navigator** — browse Markdown files in the sidebar. Opening a folder (rather than a single file) also sets the containment boundary described above.
- **Inspector panel** — toggleable side panel with file metadata.
- **In-document search** — toolbar search field plus standard <kbd>⌘F</kbd> / <kbd>⌘G</kbd> / <kbd>⌘⇧G</kbd> for next/previous match.
- **Open With** — switch to your real editor (VS Code, Cursor, Zed, Sublime, BBEdit, Nova, CotEditor, TextMate, MacVim, Xcode, TextEdit) without leaving the preview. The list filters to apps that actually declare an editor role for Markdown, and remembers your pick.
- **Open in LLM** — send the current Markdown file to Codex, Claude, or ChatGPT from the toolbar. Supported apps open with file or folder context where possible, with a copy-and-open fallback for longer prompts.
- **Text zoom** — bump preview text up or down with trackpad pinch, the toolbar's <kbd>A A</kbd> control, or <kbd>⌘+</kbd> / <kbd>⌘−</kbd> / <kbd>⌘0</kbd>. Discrete Safari-style stops from 50% to 300%.
- **Customizable toolbar** — drag in the items you actually use via *View → Customize Toolbar…* Standard AppKit affordance, your layout sticks across launches.
- **Share = copy the source** — the share toolbar feeds the picker the Markdown text itself, so **Copy** writes the raw source to the clipboard, and Mail, Messages, and Notes get the content in the body instead of a file URL.
- **Quick Look extension** — system-wide `.md` previews from Finder spacebar, Spotlight, and Mail attachments without launching the app. Subject to the same network and containment restrictions above.
- **URL scheme** — open a file or folder from a browser link or another app with `md-preview://file/<absolute path>` (e.g. `md-preview://file/Users/me/project/README.md`). Percent-encode special characters in the path.
- **Default handler** — offers to register itself as the default `.md` opener on first launch.

Not in Belvedere: the command-line tools installer (`mdp`, `md-preview`) is removed, along
with the permission to control Terminal it needed.

## Supported file types

`.md`, `.markdown`, `.mdown`, `.mdx`, `.txt`
UTI: `net.daringfireball.markdown`

## Requirements

- macOS 15 or later
- Apple Silicon or Intel

## Building from source

```sh
git clone git@github.com:inquinity/belvedere.git
cd belvedere
just build
```

Requires [`just`](https://github.com/casey/just) (`brew install just`). `just --list` shows
the rest of the fork's build/release tasks, which wrap the scripts in `bin/`. Swift Package
Manager resolves [swift-markdown](https://github.com/swiftlang/swift-markdown) on first
build — Sparkle and Sentry are not dependencies here; both were removed entirely.

## Project layout

```
md-preview/         Main app target (AppKit, WKWebView)
quick-look/         Quick Look extension (.appex)
bin/                This fork's build & release scripts (build.sh, publish-release.sh, …)
scripts/            Upstream's own tooling, untouched so syncs apply cleanly
Version.xcconfig    Marketing & build version (single source of truth)
```

## Releasing

Releases are cut locally and published to the Homebrew tap — see
[docs/RELEASE-AUTOMATION.md](docs/RELEASE-AUTOMATION.md) for the full flow. In short:

```sh
just release revision   # or minor / major — builds, signs, notarizes, commits, tags
just publish --go       # pushes the release and bumps the tap's cask
```

### Contributing

Pull requests are welcome. For larger changes, please open an issue first to discuss what
you'd like to change.

1. Fork the repo and create your branch from `main`.
2. Run the app and verify the change end-to-end (UI changes need a manual smoke test — there's no UI test suite yet).
3. Keep PRs focused; one logical change per PR.
4. Match the existing Swift style (no formatter is enforced; mirror nearby code).

A fix that belongs in Markdown Preview itself — rather than being specific to this fork's
hardening — is usually better sent there directly; see the upstream contribution track in
[docs/FORK-NOTES.md](docs/FORK-NOTES.md) for how this fork handles that split.

## Credits

- [swift-markdown](https://github.com/swiftlang/swift-markdown) — Markdown parser (Apple, cmark-gfm-backed)
- [Mermaid](https://mermaid.js.org/) — Bundled diagram renderer for `mermaid` fenced code blocks
- [KaTeX](https://katex.org/) — Bundled math typesetter for inline `$…$`, display `$$…$$`, and ` ```math ` blocks

## About this fork

Belvedere is a fork of [Markdown Preview](https://github.com/pluk-inc/markdown-preview) by
[pluk-inc](https://github.com/pluk-inc), hardened to remove its outbound network connections
and tighten how it handles untrusted documents. See
[docs/FORK-NOTES.md](docs/FORK-NOTES.md) for exactly what differs and why. For upstream's
own branding, screenshots, and ways to support that project, see its repository directly.

Belvedere and upstream Markdown Preview install side by side — different bundle ID, different
icon — so having one doesn't remove or conflict with the other. Markdown Preview itself is
`brew install --cask markdown-preview` from the
[official cask repository](https://formulae.brew.sh/cask/markdown-preview).

## License

[MIT](LICENSE)
