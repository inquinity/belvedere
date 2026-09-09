# Unreleased

Add a bullet here in the same commit as any change that alters what a
`brew`-installed user sees or does. At release, this file is renamed to
`<version>.md` and a fresh stub takes its place. See `docs/RELEASE-AUTOMATION.md`.

- The About box — both the Apple-menu panel and **Settings → About** — now says
  what Belvedere is and where it came from: a one-line description, the fork's
  network posture ("Belvedere never connects on its own. Remote content stays
  blocked until you allow it."), a link to `github.com/inquinity/belvedere`, and
  credit to the upstream project it was forked from.
- **The build number is no longer shown.** The version now reads "Version 1.1.0"
  rather than "1.1.0 build 8". This reverses the change announced in 1.1.0: the
  build number moves in lockstep with the version and never on its own, so it
  never distinguished two builds you could actually be holding. `CFBundleVersion`
  is unchanged in the bundle; it is only no longer displayed.
