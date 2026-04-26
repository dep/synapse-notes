import Foundation

struct MarkdownPreviewCursorReveal {
    let revealedRanges: [NSRange]

    static func make(from source: String, cursorLocation: Int, isEditable: Bool, parser: MarkdownDocumentParser = MarkdownDocumentParser()) -> MarkdownPreviewCursorReveal {
        guard isEditable, cursorLocation != NSNotFound else {
            return MarkdownPreviewCursorReveal(revealedRanges: [])
        }

        let document = parser.parse(source)
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
