import Foundation

struct MarkdownPreviewCursorReveal {
    let revealedRanges: [NSRange]

    static func make(from source: String, cursorLocation: Int, isEditable: Bool, parser: MarkdownDocumentParser = MarkdownDocumentParser()) -> MarkdownPreviewCursorReveal {
        guard isEditable, cursorLocation != NSNotFound else {
            return MarkdownPreviewCursorReveal(revealedRanges: [])
        }
        return make(document: parser.parse(source), cursorLocation: cursorLocation, isEditable: isEditable)
    }

    /// Variant for callers that already hold a parse of the current text (e.g. the
    /// per-caret-move reveal path, which memoizes the document across selection changes).
    static func make(document: MarkdownDocument, cursorLocation: Int, isEditable: Bool) -> MarkdownPreviewCursorReveal {
        guard isEditable, cursorLocation != NSNotFound else {
            return MarkdownPreviewCursorReveal(revealedRanges: [])
        }

        let revealedRanges = document.blocks.flatMap { block in
            block.inlineTokens.compactMap { token -> NSRange? in
                switch token.kind {
                case .markdownLink, .markdownImage, .wikiLink, .embed, .highlight:
                    let tokenStart = token.range.location
                    let tokenEnd = token.range.location + token.range.length
                    guard cursorLocation >= tokenStart, cursorLocation <= tokenEnd else { return nil }
                    return token.range
                }
            }
        }

        return MarkdownPreviewCursorReveal(revealedRanges: revealedRanges)
    }
}
