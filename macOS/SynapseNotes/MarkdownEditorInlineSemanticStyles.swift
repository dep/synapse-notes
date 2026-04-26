import Foundation

struct MarkdownEditorInlineSemanticStyles {
    struct Entry: Equatable {
        let kind: Kind
        let range: NSRange
        let contentRange: NSRange
    }

    enum Kind: Equatable {
        case markdownLink(destination: String)
        case wikiLink(rawTarget: String, destination: String, alias: String?)
        case embed(rawTarget: String)
        case highlight
    }

    let entries: [Entry]

    static func make(from source: String, parser: MarkdownDocumentParser = MarkdownDocumentParser()) -> MarkdownEditorInlineSemanticStyles {
        make(from: parser.parse(source))
    }

    static func make(from document: MarkdownDocument) -> MarkdownEditorInlineSemanticStyles {
        let entries = document.blocks.flatMap { block in
            block.inlineTokens.compactMap { token -> Entry? in
                switch token.kind {
                case let .markdownLink(destination):
                    return Entry(kind: .markdownLink(destination: destination), range: token.range, contentRange: token.contentRange)
                case .markdownImage:
                    return nil
                case let .wikiLink(destination, alias):
                    let rawTarget = rawInnerText(from: token.rawText, prefixLength: 2, suffixLength: 2)
                    return Entry(kind: .wikiLink(rawTarget: rawTarget, destination: destination, alias: alias), range: token.range, contentRange: token.contentRange)
                case .embed:
                    let rawTarget = rawInnerText(from: token.rawText, prefixLength: 3, suffixLength: 2)
                    return Entry(kind: .embed(rawTarget: rawTarget), range: token.range, contentRange: token.contentRange)
                case .highlight:
                    return Entry(kind: .highlight, range: token.range, contentRange: token.contentRange)
                }
            }
        }
        return MarkdownEditorInlineSemanticStyles(entries: entries)
    }

    private static func rawInnerText(from rawText: String, prefixLength: Int, suffixLength: Int) -> String {
        let ns = rawText as NSString
        let length = max(0, ns.length - prefixLength - suffixLength)
        guard length > 0 else { return "" }
        return ns.substring(with: NSRange(location: prefixLength, length: length))
    }
}
