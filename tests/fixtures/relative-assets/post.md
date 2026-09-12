# Relative-asset fixture

Exercises the four reference shapes the preview must handle. Open it in both
surfaces — the app window and Quick Look — because they resolve assets by
different mechanisms: the app fetches over the `md-asset:` scheme, Quick Look
inlines images as `data:`/`cid:`.

## Sibling file in subfolder

> **EXPECT:** an image renders directly below.
> **FAIL IF:** a placeholder appears instead of the image. Containment (M4) confines resolution
> to this document's folder, and this file is inside it — a break here means
> containment is refusing legitimate assets.

![local](images/local.png)

## Sibling file with URL-encoded spaces

> **EXPECT:** an image renders directly below.
> **FAIL IF:** a placeholder appears instead of the image. The path is `images dir/two words.png`
> percent-encoded; this is the case most likely to break under a change to
> path handling, because it fails only when decoding is wrong.

![spaces](images%20dir/two%20words.png)

## Absolute http URL — must NOT load

> **EXPECT:** a placeholder reading **Remote image blocked — www.apple.com**.
> **FAIL IF:** the Apple logo renders. Remote images are blocked by CSP on
> both surfaces so that opening a document never tells its author you read it.
>
> This expectation was **inverted in M3b/F2**: the fixture previously said this
> image "must keep working". Blocking it is the deliberate cost of closing the
> tracking-pixel hole, and README badges are the visible casualty.

![remote](https://www.apple.com/ac/structured-data/images/knowledge_graph_logo.png?202210171354)

## Outside this folder, and really there — Load succeeds

> **In the app window — EXPECT:** `logo.png` with a **Load** button. Click it
> and the image appears in place of the placeholder.
> **In Quick Look — EXPECT:** `logo.png — outside this folder — Quick Look
> cannot load it`, and **no button**. Quick Look offers no grants at all, so
> there is nothing to click; the same file loads in the app window.
>
> **FAIL IF:** the app window's button reports a failure. This file exists and
> is a real PNG; containment refused it only because it sits outside the
> document's folder, which is precisely the case Load exists to resolve.
> **FAIL IF:** the image renders without a click, on either surface.
> Out-of-folder assets must not load on their own — that is the containment
> boundary doing its job, and a document should not be able to read across it
> just by naming a path.
> **FAIL IF:** Quick Look shows a Load button. It has no host to answer one,
> so it could only spin forever.
>
> This is the shared-image layout that motivated the whole design: a
> `shared-images/` folder one level up, referenced from several documents.
> Nothing is remembered, so reopening this file blocks it again. A durable
> grant is trusted folders (F3).

![shared logo](../shared-images/logo.png)

## Long name, outside this folder — the label must wrap

> **EXPECT:** the whole message, wrapped onto as many lines as it needs.
> **FAIL IF:** it ends in an ellipsis. These labels are explanations, and the
> clause that gets cut is the one that explains why — an elided
> `… Quick Look cannot loa…` tells the reader nothing.

![long name](../shared-images/a-deliberately-long-shared-image-filename.png)

## Missing file, inside this folder

> **EXPECT:** `missing.png — file missing`, and **no Load button**.
> **FAIL IF:** a Load button appears. This file is inside the document's own
> folder, so resolution was already permitted and nothing blocked it — the
> load simply failed. A button there would offer to retry what just failed.
> **FAIL IF:** the app or the Quick Look preview crashes, hangs, or renders
> blank. A missing asset must be uneventful.

![missing](images/missing.png)

## Missing file, outside this folder

> **In the app window — EXPECT:** `missing-outside.png` with a **Load**
> button. Click it and the label becomes `file missing`.
> **In Quick Look — EXPECT:** `outside this folder — Quick Look cannot load
> it`, and no button.
> **FAIL IF:** the app window shows no button. Containment refused this one,
> so the reader is owed the choice — that is the difference from the case
> above.
>
> The two cases look similar and are not: one was *blocked*, the other merely
> *broke*. Only the blocked one has a remedy.

![missing outside](../missing-outside.png)
