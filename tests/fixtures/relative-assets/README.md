# Quick Look relative-asset fixture

Manual verification fixture for the Quick Look extension's relative-link
support. Not consumed by any automated build target — kept in the repo so
contributors can reproduce the QL test described in the PR.

## How to use

```bash
xcodebuild -project md-preview.xcodeproj -scheme md-preview \
    -configuration Debug build
qlmanage -r && qlmanage -r cache
open -R tests/fixtures/relative-assets/post.md   # reveal in Finder
# then press space on post.md
```

Expectations:

- `images/local.png` renders.
- `images dir/two words.png` renders (URL-decoded path).
- `../shared-images/logo.png` does **not** render on its own — it sits outside
  the document's folder, so containment refuses it. It shows a placeholder with
  a **Load** button, and clicking that button renders it. Both halves matter:
  loading without a click would mean the boundary is not holding, and a failure
  after the click would mean the remedy is broken.
- ~~The remote https image renders (network entitlement already granted).~~
  **Changed in this fork: the remote image must NOT render.**
  `QuickLookContentPolicy` denies remote origins in the preview page, so a
  document cannot disclose that it was opened when a reader merely presses
  space in Finder. The extension still holds the network entitlement — it
  renders blank without it — so the block is enforced by the page's
  Content-Security-Policy rather than by the sandbox. A gap where this image
  used to appear is the correct result. See `docs/FORK-NOTES.md`.
- `images/missing.png` shows a placeholder reading `missing.png — file missing`,
  with no Load button: nothing blocked it, it simply is not there. The preview does not
  crash.

If sandbox denials show up in Console.app filtered by `quick-look`, the
extension's read access to siblings is being refused before the
`cid:`/`QLPreviewReply.attachments` rewrite can read the files.
