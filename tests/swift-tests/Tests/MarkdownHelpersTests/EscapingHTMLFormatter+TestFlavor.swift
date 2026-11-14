import Markdown
@testable import MarkdownHelpers

/// Tests that are not about the Markdown flavor format with the default one.
/// This overload lives only in the test target: the app's own callers must
/// pass `markdownFlavor`, which `EscapingHTMLFormatter.format` requires.
extension EscapingHTMLFormatter {
    static func format(_ markdown: String,
                       options: HTMLFormatterOptions = [],
                       sourceLineOffset: Int = 0,
                       sourceMarkdown: String? = nil,
                       highlightsCode: Bool = true,
                       strictLineBreaks: Bool = false) -> String {
        format(markdown,
               options: options,
               sourceLineOffset: sourceLineOffset,
               sourceMarkdown: sourceMarkdown,
               highlightsCode: highlightsCode,
               strictLineBreaks: strictLineBreaks,
               markdownFlavor: MarkdownFlavorSetting.defaultValue)
    }
}
