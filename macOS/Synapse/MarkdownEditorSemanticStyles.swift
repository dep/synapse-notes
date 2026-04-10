import Foundation

struct MarkdownEditorSemanticStyles {
    struct Heading: Equatable {
        let level: Int
        let range: NSRange
        let markerRange: NSRange
    }

    struct Frontmatter: Equatable {
        let range: NSRange
        let contentRange: NSRange
    }

    struct Callout: Equatable {
        let range: NSRange
        let markerRange: NSRange
        let titleRange: NSRange?
        let kind: String
    }

    let headings: [Heading]
    let blockquotes: [NSRange]
    let codeBlocks: [NSRange]
    let thematicBreaks: [NSRange]
    let frontmatter: Frontmatter?
    let callouts: [Callout]

    static func make(from source: String, parser: MarkdownDocumentParser = MarkdownDocumentParser()) -> MarkdownEditorSemanticStyles {
        make(from: parser.parse(source))
    }

    static func make(from document: MarkdownDocument) -> MarkdownEditorSemanticStyles {
        let nsSource = document.source as NSString

        var headings: [Heading] = []
        var blockquotes: [NSRange] = []
        var codeBlocks: [NSRange] = []
        var thematicBreaks: [NSRange] = []
        var frontmatter: Frontmatter?
        var callouts: [Callout] = []

        for block in document.blocks {
            switch block.kind {
            case .frontmatter:
                frontmatter = Frontmatter(range: block.range, contentRange: block.contentRange)
            case let .heading(level):
                let line = nsSource.substring(with: block.range)
                let markerLength = line.prefix { $0 == "#" }.count + 1
                headings.append(Heading(
                    level: level,
                    range: block.range,
                    markerRange: NSRange(location: block.range.location, length: min(markerLength, block.range.length))
                ))
            case .blockquote:
                blockquotes.append(block.range)
                if let callout = MarkdownCalloutDetector.detect(in: block, source: document.source) {
                    callouts.append(Callout(range: callout.blockRange, markerRange: callout.markerRange, titleRange: callout.titleRange, kind: callout.kind))
                }
            case .fencedCodeBlock:
                codeBlocks.append(block.range)
            case .thematicBreak:
                thematicBreaks.append(block.range)
            default:
                break
            }
        }

        return MarkdownEditorSemanticStyles(
            headings: headings,
            blockquotes: blockquotes,
            codeBlocks: codeBlocks,
            thematicBreaks: thematicBreaks,
            frontmatter: frontmatter,
            callouts: callouts
        )
    }
}
