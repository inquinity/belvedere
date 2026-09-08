# Relative-asset fixture

Exercises the four reference shapes the preview must handle. Open it in both
surfaces — the app window and Quick Look — because they resolve assets by
different mechanisms: the app fetches over the `md-asset:` scheme, Quick Look
inlines images as `data:`/`cid:`.

## Sibling file in subfolder

> **EXPECT:** an image renders directly below.
> **FAIL IF:** broken-image placeholder. Containment (M4) confines resolution
> to this document's folder, and this file is inside it — a break here means
> containment is refusing legitimate assets.

![local](images/local.png)

## Sibling file with URL-encoded spaces

> **EXPECT:** an image renders directly below.
> **FAIL IF:** broken-image placeholder. The path is `images dir/two words.png`
> percent-encoded; this is the case most likely to break under a change to
> path handling, because it fails only when decoding is wrong.

![spaces](images%20dir/two%20words.png)

## Absolute http URL — must NOT load

> **EXPECT:** a broken-image placeholder.
> **FAIL IF:** the Apple logo renders. Remote images are blocked by CSP on
> both surfaces so that opening a document never tells its author you read it.
>
> This expectation was **inverted in M3b/F2**: the fixture previously said this
> image "must keep working". Blocking it is the deliberate cost of closing the
> tracking-pixel hole, and README badges are the visible casualty.

![remote](https://www.apple.com/ac/structured-data/images/knowledge_graph_logo.png?202210171354)

## Missing file, inside this folder

> **EXPECT:** `missing.png — load failed`, and **no Load button**.
> **FAIL IF:** a Load button appears. This file is inside the document's own
> folder, so resolution was already permitted and nothing blocked it — the
> load simply failed. A button there would offer to retry what just failed.
> **FAIL IF:** the app or the Quick Look preview crashes, hangs, or renders
> blank. A missing asset must be uneventful.

![missing](images/missing.png)

## Missing file, outside this folder

> **EXPECT:** `missing-outside.png` with a **Load** button. Click it and the
> label becomes `load failed: could not be read`.
> **FAIL IF:** no button appears. Containment refused this one, so the reader
> is owed the choice — that is the difference from the case above.
>
> The two cases look similar and are not: one was *blocked*, the other merely
> *broke*. Only the blocked one has a remedy.

![missing outside](../missing-outside.png)
