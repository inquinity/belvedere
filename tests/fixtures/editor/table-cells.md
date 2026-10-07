# Table cell editing

Manual fixture for editing a table in edit mode. It exists because nine automated
tests about this failed on macOS 27 for a reason in the test harness, and nobody has
tried the same actions by hand in the real app on that system.

**How to use:** open this file in Belvedere, press **⌘E**, and follow each section.
Do it on macOS 27, and on macOS 26 if you have it.

## 1. Click into a formatted cell

> **EXPECT:** clicking the middle of `target words` in the **Bold** row makes the
> cell show its Markdown, `**target words**`, with the caret where you clicked and
> not at the start of the cell. Clicking away shows it rendered again.
> **FAIL IF:** the cell keeps showing plain `target words` after the click, or the
> caret jumps to the start of the cell.

| Style | Cell |
| --- | --- |
| Bold | **target words** |
| Italic | *target words* |
| Strikethrough | ~~target words~~ |
| Code | `target words` |
| Highlight | ==target words== |
| Link | [target words](https://example.com) |
| Mixed | **before *target words*** |

## 2. Drag to select inside a cell

> **EXPECT:** press in one word of the **Bold** cell and drag a few letters: the
> text between is selected, nothing outside the cell is, and the cell shows its
> Markdown.
> **FAIL IF:** the selection covers other cells, or nothing is selected.

## 3. Format a selection in a cell

> **EXPECT:** select two words in the **Name** column of the table below, use the
> formatting bar's bold button: those words become `**...**` in that cell only.
> The neighbouring cell `Same` is unchanged, and so is the paragraph above the table.
> **FAIL IF:** another cell or the paragraph changes, or the bold goes to the wrong text.

Paragraph above the table, which must stay as it is.

| Name | Other |
| --- | --- |
| Ada Lovelace | Same |
| Grace Hopper | Same |

## 4. Link and keyboard formatting in a cell

> **EXPECT:** select a word in a cell, press **⌘B** (bold) or **⌘I** (italic): it is
> formatted. Choose the link button, enter an address and confirm: the word becomes a
> link in that cell. Anything you typed before pressing the shortcut is kept.
> **FAIL IF:** typing before the shortcut is lost, or the result lands in another cell.

## 5. Tab between cells

> **EXPECT:** in the table below, click the first cell and press **Tab**. The next cell
> shows its Markdown **with all of its text selected**, so typing replaces it.
> **Shift-Tab** goes back the same way, and **Enter** does what Tab does. **Tab** from the
> last cell adds a new row.
> **FAIL IF:** the next cell is shaded but nothing in it is selected. The shading is only
> the focus colour and must not be the only sign of where you are.

| One | Two | Three |
| --- | --- | --- |
| *target words* | **bold words** | plain |

## 6. Leave edit mode

> **EXPECT:** press **⌘E** again. The table shows rendered text, and the changes you
> made are still there. Nothing outside the table changed.
> **FAIL IF:** any cell loses text, or the table collapses into plain lines.

## Not covered here

- Adding or removing rows and columns, and the table toolbar's other buttons.
- Pasting a table from another app.
- Right-to-left or CJK text in cells.
- Quick Look, which does not edit.
