# Installing the internal build

This is the internal build of Belvedere maintained at
[inquinity/markdown-preview](https://github.com/inquinity/markdown-preview). It makes no
network connections of any kind — see [FORK-NOTES.md](FORK-NOTES.md) for what was removed
and why.

**Requires macOS 15 or later.**

## Install

1. Download the `.dmg` from the corporate share or Dropbox.
2. Open it and drag **Belvedere** to your `Applications` folder.
3. **Launch the app once.** This step is not optional — see below.

That's it. Double-click any `.md` file, or set Belvedere as your default handler
for Markdown in Finder's *Get Info* panel.

## Quick Look needs step 3

Pressing space on a `.md` file in Finder will show the plain text, not a rendered
preview, until **the app has been moved to `/Applications` and launched at least once**.

macOS registers Quick Look extensions through `pluginkit`, and that only happens for an
app in a standard location that has been run. An app sitting in `~/Downloads`, or one
that has been copied but never opened, will not have its extension registered no matter
how many times you press space.

If Quick Look still shows plain text after launching the app once:

```bash
qlmanage -r && qlmanage -r cache
```

Then log out and back in. To confirm the extension is registered at all:

```bash
pluginkit -m -p com.apple.quicklook.preview | grep -i markdown
```

## If Gatekeeper blocks the app

You should not see a Gatekeeper warning — internal builds are signed with a Developer ID
certificate and notarized by Apple, which is what lets them open normally on a Mac that
has never seen them before.

If you do get "cannot be opened because the developer cannot be verified", **stop and
report it** rather than working around it. It means the build was not notarized
correctly, and the fix belongs in the build, not on your machine. Do not strip the
quarantine attribute — that disables the check that would tell us something is wrong.

## Updates

There is no automatic updater. Sparkle was removed along with the rest of the outbound
network traffic, so new versions are distributed the same way as the first one: a new
`.dmg` on the share.

To see which version you have: **Belvedere → About Belvedere**.

## Reporting problems

File an issue at [inquinity/markdown-preview](https://github.com/inquinity/markdown-preview/issues).

If the problem also reproduces in the upstream build, it belongs
[upstream](https://github.com/pluk-inc/markdown-preview/issues) instead — this fork
carries no rendering changes of its own.
