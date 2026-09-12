# Asset references that reach outside the document folder

The rendered page's `<base href>` is an `md-asset:` URL mirroring the document's
folder, so WebKit resolves every reference below *before* it reaches
`MarkdownAssetSchemeHandler`. An `md-asset:` URL's path is therefore the
absolute path of a file on disk.

`MarkdownAssetResolution.fileURL(for:containedIn:)` now takes the document's
folder and refuses anything resolving outside it. Before that fix it returned
whatever absolute path it was handed, which — combined with the app's
`temporary-exception.files.absolute-path.read-only` entitlement of `/` — let
document content cause any file the user could read to be read off disk and
handed to WebKit.

Reported upstream as GHSA-vgmc-h5g6-xh2q, submitted as PR #337, and carried on
this fork ahead of that merge (M4).

**The tests over this file assert containment.** They previously asserted the
permissive behaviour and were written to fail the moment it changed; it changed,
and they were inverted rather than left stale. See `AssetContainmentTests`.

**Reading this by eye:** no image below may load. Each shows a placeholder
naming the file, with a **Load** button, because these paths sit outside the
document's folder. The passing result is that clicking Load never puts file
contents on screen — these are not images, so it reports a failure.

## Traversal out of the document folder

> **EXPECT:** two placeholders naming `passwd` and `secrets.txt`, each with a
> **Load** button. No file contents, before or after clicking Load.
> **FAIL IF:** you see the contents of a file, or any image renders. These
> point at `/etc/passwd` and a sibling project's secrets — anything visible
> here is a file this document had no right to read.

![escaping upwards](../../../../etc/passwd)

![sibling folder](../other-project/secrets.txt)

## Root-absolute paths

Resolved against the `md-asset:` origin, not the document folder.

> **EXPECT:** two placeholders naming `hosts` and `id_rsa`, each with a **Load**
> button that never yields contents.
> **FAIL IF:** anything renders. No traversal is needed for these — they name
> absolute paths directly, so they are the shortest route to the same escape.

![absolute](/etc/hosts)

![user data](/Users/someone/.ssh/id_rsa)

## Protocol-relative, which must stay rejected

`fileURL(for:)` rejects URLs carrying a host, so this must not alias a local
file. That check is real and worth keeping a test on.

> **EXPECT:** a placeholder naming `pic.png`. Load reports `load failed` — a
> URL carrying a host never resolves to a local file.
> **FAIL IF:** it renders. A URL carrying a host must never alias a local file.

![protocol relative](//evil.invalid/pic.png)
