Belvedere test kit
==================

A copy of the Swift tests and the sources they build, for running on another
Mac. Nothing here changes the Mac it runs on, except that swift test builds
into tests/swift-tests/.build inside this folder.

Needs: Xcode (or the Command Line Tools), and network access to GitHub on the
first run, to fetch the swift-markdown package.

Run it from inside this folder:

    ./run-tests.sh

That runs only the three editor suites. Add --all for everything, --gist to
publish the summary as a secret GitHub gist (needs the gh tool signed in), or
--help for the rest.

Then send back results/summary.md and results/failures.md: paste them into a
GitHub issue or gist. They contain the macOS and Xcode versions and the test
failures, with user, computer and temp-folder names removed. results/full.log
is not redacted, so it is not meant to leave the machine.

What we are comparing against
-----------------------------
On the development Mac (macOS 27.0.1), these 10 tests fail, and they fail the
same way on unmodified upstream code, so the question is whether they also fail
on macOS 26:

  EditorFormattingTests testFormattingMissingTableCellsDoesNotTargetBodySelection
  EditorFormattingTests testFormattingToolbarTargetsTableCellSelectionAfterBlur
  EditorFormattingTests testTableClickAnchorsBeforeRevealingSyntax
  EditorFormattingTests testTableFormattingMapsPendingPipesWhitespaceUnicodeAndEmptyCells
  EditorFormattingTests testTableFormattingRejectsTargetAfterDocumentReplacement
  EditorFormattingTests testTableLinkPopoverAndKeyboardFormattingPreservePendingTyping
  EditorFormattingTests testTablePointerSelectionKeepsNativeTextRangeAndFormattingTarget
  EditorPreviewLayoutTests testCompleteMixedFormattingDocument
  EditorScrollAnchorTests testTableInlineCodeRendersAndPreservesMarkdownWhileEditing
  EditorScrollAnchorTests testTableInlineFormattingOnlyShowsSourceInFocusedCell

All 10 passing on macOS 26 points at the newer WebKit. The same failures there
point at the tests or the editor bundle.
