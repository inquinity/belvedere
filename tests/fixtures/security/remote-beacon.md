# Remote references that disclose the reader

Every reference below is a tracking pixel. Rendering this document tells
`example.invalid` that the file was opened, from which IP, and at what time —
and the query strings show how an author can identify *which* document and
recipient without any cooperation from the reader.

Both surfaces block these, and neither does it with the sandbox — both targets
must keep `com.apple.security.network.client` or WKWebView renders nothing at
all, so the block lives in the page:

- **Quick Look** — `QuickLookContentPolicy`. Guarded by
  `QuickLookContentPolicyTests`.
- **The app window and editor** — `PreviewContentPolicy`. Guarded by
  `PreviewContentPolicyTests`.

The two policies are deliberately separate and must not be merged. Quick Look
inlines its vendor bundles and carries images as `data:`/`cid:`; the app page
fetches scripts and images over the `md-asset:` scheme. A single shared policy
would have to permit the union of both, which is weaker than either.

DOMPurify still keeps these `<img>` elements in the DOM — `ALLOWED_URI_REGEXP`
permits `http`/`https` — so they appear as labelled placeholders rather than
vanishing.
The load is what is refused. Tightening that regexp is the belt to this braces
and is on the upstream contribution track.

**Reading this by eye:** every reference below must fail to load. A placeholder
reading **Remote image blocked — example.invalid** is the passing result: the
element survives sanitisation, only the network request is refused.

## Image beacons

> **EXPECT:** two placeholders, each reading
> **Remote image blocked — example.invalid**.
> **FAIL IF:** either image renders. `example.invalid` cannot resolve, so a
> loaded image would mean something rewrote the URL — but the real point is
> that no request should leave the machine at all. To check that properly,
> see the Little Snitch / `tcpdump` step in docs/MANUAL-TEST-CHECKLIST.md.

![](https://example.invalid/pixel.png?doc=quarterly-results&reader=alice)

![](http://example.invalid/plain-http.png)

## Referenced via inline HTML

> **EXPECT:** one placeholder reading **Remote image blocked — example.invalid**.
> **FAIL IF:** it renders. Raw HTML is a second route to the same beacon and
> is covered by the CSP rather than by the sanitiser.

<img src="https://example.invalid/inline.png?via=raw-html">

## Remote stylesheet and font

Both are denied by `default-src 'none'` in the Quick Look policy.

> **EXPECT:** this page keeps the app's own styling — normal fonts, normal
> spacing, readable.
> **FAIL IF:** the page suddenly looks unstyled or differently styled. A
> remote stylesheet that loaded would be able to restyle the document, and
> the request itself already told the server you opened the file.

<link rel="stylesheet" href="https://example.invalid/theme.css">
