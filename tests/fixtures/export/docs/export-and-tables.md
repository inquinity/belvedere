# Export, print and tables

A hand test for printing and export, which work from a hidden copy of the page,
and for tables. Each section says what to do, what to expect (**EXPECT**) and
what is a failure (**FAIL IF**).

## 1. Images and the folder boundary

Two images: one beside this file, one in `../shared/`, outside this file's
folder.

![Beside the document](beside-the-document.png)

![Outside the document's folder](../shared/outside-the-document-folder.png)

**a. Open this file on its own** (File ▸ Open, this file).
EXPECT: the first image shows; the second is a placeholder with a **Load**
button. File ▸ Export… as PDF, then as PNG, and File ▸ Print…: the first image
is in each, and the second is a placeholder in each.
FAIL IF: the second image appears in any output without having been loaded.

**b. Click Load** on the placeholder, then export and print again.
EXPECT: both images are in every output.
FAIL IF: an image you loaded is missing from the output.

**c. Open the folder** `tests/fixtures/export` (File ▸ Open Folder…), then this
file from the sidebar.
EXPECT: both images show without a click, and both are in every output.
FAIL IF: the second image shows in the reader but not in the output; the
export is using a different boundary from the page.

## 2. Wide tables

| Measure | Meaning |
| --- | --- |
| Static | ordinary words of prose ordinary words of prose ordinary words of prose ordinary words of prose ordinary words of prose ordinary words of prose |

| Category | Value |
| --- | --- |
| Stable | WideValueWideValueWideValueWideValueWideValueWideValueWideValueWideValueWideValueWideValueWideValueWideValueWideValueWideValueEnd |

| # | First | Second | Third | Fourth | Fifth | Sixth | Seventh |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Northern region | Southern region | Eastern region | Western region | Central region | Coastal region | Mountain region |
| 2 | quarterly figures | quarterly figures | quarterly figures | quarterly figures | quarterly figures | quarterly figures | quarterly figures |

| Setting | Key | Description |
| --- | --- | --- |
| Line breaks | `belvedere.strictLineBreaks` | Whether a single new line in the source is a line break, or runs on into the next line as standard Markdown does |
| Flavor | `belvedere.markdownFlavor` | Which quotations that start with a tag become callouts |

**In the reader.**
EXPECT: no column is squeezed so that a short label breaks letter by letter;
a table wider than the window scrolls sideways in its own box.

**Printed, and exported as PDF and PNG.**
EXPECT: every column of every table is on the page. Ordinary words stay whole;
the long `WideValue…End` string wraps; the seven-column table is scaled down if
it cannot otherwise fit. The text after this section is at its normal size.
FAIL IF: a column is cut off at the page edge, a word like "region" is
split, or the Key column's code breaks letter by letter.

**Scale.** In File ▸ Print…, in the Belvedere pane, set Scale to 200%, then
50%.
EXPECT: the preview updates each time, with every column still on the page.

**While the print or export dialog is open,** look at the document window
behind it.
EXPECT: the page you are reading does not change: same colours, same width,
same scroll position.

## 3. Expand Table

Each table above has an expand control (⛶) at its top right. Click one.
EXPECT: a full-screen window titled "2. Wide tables" shows only that table,
read-only. Press Escape: the window closes and the document is as you left it.
Do the same in Edit Mode (⌘E).
EXPECT: the same kind of window, titled "Table"; the document is unchanged and
not marked as edited.

## 4. Printing from Finder

With Belvedere as the default app for Markdown files, quit it. In Finder,
select this file and choose File ▸ Print.
EXPECT: Belvedere opens the file and shows the print dialog.
FAIL IF: Belvedere quits, or prints without showing the dialog.

The text after the tables ends here.
