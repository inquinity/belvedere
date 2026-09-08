# Markdown Preview — agent guide

> ## ⚠️ FORK STATUS — read before acting on anything below
>
> This is **[inquinity/markdown-preview](https://github.com/inquinity/markdown-preview)**,
> a fork of pluk-inc/markdown-preview. Read
> **[docs/FORK-NOTES.md](docs/FORK-NOTES.md)** first — it is the source of truth for how
> this repository differs from the document below.
>
> - **Releases go through `scripts/build.sh --release`.** It builds, signs, notarizes
>   and packages a DMG into `dist/`, with no `CHANGELOG.md` requirement, and composes
>   with `--update` to bump the version first. Upstream's `release.sh`,
>   `rollback-release.sh` and the whole Amore pipeline drove *their* account and have
>   been removed. **Ignore the `release-process` skill and the Releasing section below** —
>   both describe upstream's pipeline, which does not exist here.
> - **`DEVELOPMENT_TEAM` is different here, on purpose.** The Signing section below says
>   never to change `5P3TSMNV42`. That is upstream's team and correct advice *in their
>   repo*. This fork builds as `com.altmansoftwaredesign.belvedere` under team
>   `45GJWJVQN2` — that change is deliberate, and reverting it to match the text below
>   would break signing here. The surrounding warning still applies: never let Xcode
>   silently rewrite it to some *other* team.
> - **`Version.xcconfig` is bumped by `scripts/build.sh --update`**, not by
>   `scripts/release.sh`, which no longer exists. The fork versions on its own `1.0.x`
>   line, independent of upstream's `0.0.x`.
> - **Sparkle is excised**, so the EdDSA key, the notary-profile pairing, `SUPublicEDKey`
>   and the `SUFeedURL` "Known issue" below are all moot here. The Sparkle
>   `mach-lookup` entitlements are gone too. The read-only filesystem exception is not
>   moot — see F3 in the fork notes.
> - The fork carries **deliberately dead code** — an orphaned CLI installer and stubbed
>   telemetry reporters. This is load-bearing for cheap upstream merges. Do not remove it.
> - **The "No git remote yet" known issue below is stale here.** This fork has `origin`
>   (inquinity) and `upstream` (pluk-inc).
> - Sync with `git merge upstream/main`. **Never rebase `main`** — it is published.
>
> Everything after this block is upstream's documentation, preserved as-is.

A macOS app for previewing Markdown files. AppKit, sandboxed, ships with a Quick Look extension. Updates via Sparkle, distributed via Amore.

## Project facts

| Thing             | Value                                                       |
| ----------------- | ----------------------------------------------------------- |
| Bundle id         | `doc.md-preview`                                            |
| Product name      | `Markdown Preview`                                          |
| Scheme            | `md-preview`                                                |
| Quick Look target | `quick-look` (embedded extension)                           |
| Min macOS         | 15.0                                                        |
| Sandboxed         | yes — uses Sparkle XPC services for updates                 |
| Auto-updater      | Sparkle 2.x (Swift package)                                 |
| Distribution      | Amore (managed) with custom domain `storage.md-preview.app` |

Version is managed centrally in `Version.xcconfig` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`). Both the app and the quick-look extension inherit from it.

## Signing & secrets — do not touch without asking

- `DEVELOPMENT_TEAM = 5P3TSMNV42` (`project.pbxproj`, both targets) is the
  maintainer's Apple Developer Team ID, hardcoded in the shared Xcode project.
  Never change it, regenerate signing, or let Xcode "fix" it automatically —
  building locally without the team's certificates can make Xcode silently
  rewrite `DEVELOPMENT_TEAM` to your own personal team on save. Check
  `git diff` on `project.pbxproj` before committing anything and revert that
  hunk if it shows up.
- `CODE_SIGN_IDENTITY` / `CODE_SIGN_STYLE = Automatic` — same story, leave as-is.
- Secrets (currently `POSTHOG_PROJECT_TOKEN`) live in `Secrets.xcconfig`,
  gitignored — copy `Secrets.xcconfig.example` to `Secrets.xcconfig` locally.
  Never hardcode a real token into a tracked file, Info.plist, or a commit.
- The Sparkle/Amore signing material (EdDSA key, notary keychain profile) is
  documented in the `release-process` skill. Don't touch `SUPublicEDKey` in
  `Info.plist` or the entitlements' `mach-lookup` names without reading that
  skill first — they're paired with private material outside the repo (login
  Keychain / Amore), so an unmatched change breaks Sparkle updates silently.
- `md-preview.entitlements` / `quick-look.entitlements` — the sandbox
  `temporary-exception` entries (Sparkle XPC mach-lookup names, the read-only
  filesystem exception) are narrowly scoped, notarization-review-sensitive
  capabilities. Don't broaden or "clean up" them without understanding why
  they're there (see the inline comments in each file).
- `Version.xcconfig` (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`) is
  bumped only by `scripts/release.sh` — don't hand-edit it.

## Releasing

See the `release-process` skill for branch/PR naming, exactly what `scripts/release.sh` and `scripts/rollback-release.sh` do, and the Amore config already wired for this project.

## Known issues
- **`SUFeedURL` mismatch**. Info.plist points to `https://storage.md-preview.app/appcast.xml` but Amore actually publishes to `https://storage.md-preview.app/v1/apps/doc.md-preview/appcast.xml`. This matters for **any release run that isn't `--draft`** — the default run, `--beta`, and `--skip-github` all publish to Amore's live appcast, which — due to the mismatch above — is not yet the URL already-installed copies poll; `--draft` is the only mode that doesn't publish. Fix Info.plist before any of those ship to real users — already-installed copies will check the wrong URL forever. Either change `SUFeedURL` to the `/v1/apps/...` path, or configure a CDN rewrite at `storage.md-preview.app` to map `/appcast.xml` → the real path.
- **No git remote yet**. `git remote -v` is empty. Run `gh repo create` before relying on the GitHub release portion of `scripts/release.sh` (it auto-skips when no remote exists).

## Common Xcode tasks
```bash
xcodebuild -project md-preview.xcodeproj -scheme md-preview -configuration Debug build
xcodebuild -resolvePackageDependencies -project md-preview.xcodeproj
```
Sparkle helper tools (sign_update / generate_keys / generate_appcast) live at:
`~/Library/Developer/Xcode/DerivedData/md-preview-*/SourcePackages/artifacts/sparkle/Sparkle/bin/`
