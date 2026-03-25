import Foundation

struct MarkdownPreviewSemanticHiding {
    let hiddenRanges: [NSRange]
    let placeholderRanges: [NSRange]

    static func make(from source: String, isEditable: Bool, parser: MarkdownDocumentParser = MarkdownDocumentParser()) -> MarkdownPreviewSemanticHiding {
        make(from: parser.parse(source), isEditable: isEditable)
    }

    static func make(from document: MarkdownDocument, isEditable: Bool) -> MarkdownPreviewSemanticHiding {
        let nsSource = document.source as NSString
        var hiddenRanges: [NSRange] = []
        var placeholderRanges: [NSRange] = []

        for block in document.blocks {
            switch block.kind {
            case let .heading(level):
                let prefixLength = min(level + 1, block.range.length)
                hiddenRanges.append(NSRange(location: block.range.location, length: prefixLength))
            case .blockquote:
                let blockText = nsSource.substring(with: block.range)
                let lineRanges = lineRanges(in: blockText, baseLocation: block.range.location)
                for lineRange in lineRanges {
                    let line = nsSource.substring(with: lineRange)
                    let trimmedLeading = line.prefix { $0 == " " || $0 == "\t" }.count
                    let markerLength = line.dropFirst(trimmedLeading).hasPrefix("> ") ? 2 : (line.dropFirst(trimmedLeading).hasPrefix(">") ? 1 : 0)
                    if markerLength > 0 {
                        hiddenRanges.append(NSRange(location: lineRange.location + trimmedLeading, length: markerLength))
                    }
                }
                if let callout = MarkdownCalloutDetector.detect(in: block, source: document.source) {
                    hiddenRanges.append(callout.markerRange)
                }
            case let .fencedCodeBlock(fence, _):
                let blockText = nsSource.substring(with: block.range)
                let lineRanges = lineRanges(in: blockText, baseLocation: block.range.location)
                if lineRanges.count > 1,
                   let first = lineRanges.first,
                   let last = lineRanges.last,
                   last.location != first.location {
                    let lastText = nsSource.substring(with: last).trimmingCharacters(in: .whitespaces)
                    if lastText == fence {
                        hiddenRanges.append(first)
                        hiddenRanges.append(last)
                    }
                }
            case .frontmatter:
                if !isEditable {
                    let blockText = nsSource.substring(with: block.range)
                    let lineRanges = lineRanges(in: blockText, baseLocation: block.range.location)
                    if let first = lineRanges.first { hiddenRanges.append(first) }
                    if lineRanges.count > 1, let last = lineRanges.last { hiddenRanges.append(last) }
                }
            case .taskListItem:
                if isEditable {
                    let prefixLength = max(0, block.contentRange.location - block.range.location)
                    if prefixLength > 0 {
                        placeholderRanges.append(NSRange(location: block.range.location, length: prefixLength))
                    }
                }
            default:
                break
            }

            for token in block.inlineTokens {
                switch token.kind {
                case .markdownImage:
                    break
                case .markdownLink:
                    let full = token.rawText as NSString
                    hiddenRanges.append(NSRange(location: token.range.location, length: 1))
                    let suffixLocation = token.range.location + token.range.length - max(0, full.length - (token.contentRange.length + 1))
                    let suffixLength = token.range.location + token.range.length - suffixLocation
                    if suffixLength > 0 {
                        hiddenRanges.append(NSRange(location: suffixLocation, length: suffixLength))
                    }
                case let .wikiLink(_, alias):
                    hiddenRanges.append(NSRange(location: token.range.location, length: 2))
                    hiddenRanges.append(NSRange(location: token.range.location + token.range.length - 2, length: 2))
                    if alias != nil,
                       let pipeRange = rawPipePrefixRange(in: token.rawText, prefix: "[[", suffix: "]]") {
                        hiddenRanges.append(NSRange(location: token.range.location + pipeRange.location, length: pipeRange.length))
                    }
                case .embed:
                    hiddenRanges.append(NSRange(location: token.range.location, length: 3))
                    hiddenRanges.append(NSRange(location: token.range.location + token.range.length - 2, length: 2))
                case .highlight:
                    hiddenRanges.append(NSRange(location: token.range.location, length: 2))
                    hiddenRanges.append(NSRange(location: token.range.location + token.range.length - 2, length: 2))
                }
            }
        }

        return MarkdownPreviewSemanticHiding(
            hiddenRanges: dedupe(hiddenRanges),
            placeholderRanges: dedupe(placeholderRanges)
        )
    }

    private static func rawPipePrefixRange(in rawText: String, prefix: String, suffix: String) -> NSRange? {
        let inner = rawInnerText(in: rawText, prefix: prefix, suffix: suffix)
        let nsInner = inner as NSString
        let pipe = nsInner.range(of: "|")
        guard pipe.location != NSNotFound else { return nil }
        return NSRange(location: prefix.count, length: pipe.location + 1)
    }

    private static func rawInnerText(in rawText: String, prefix: String, suffix: String) -> String {
        let ns = rawText as NSString
        let length = max(0, ns.length - prefix.count - suffix.count)
        guard length > 0 else { return "" }
        return ns.substring(with: NSRange(location: prefix.count, length: length))
    }

    private static func lineRanges(in text: String, baseLocation: Int) -> [NSRange] {
        let parts = text.components(separatedBy: "\n")
        var ranges: [NSRange] = []
        var location = baseLocation
        for (index, part) in parts.enumerated() {
            let length = (part as NSString).length
            ranges.append(NSRange(location: location, length: length))
            location += length
            if index < parts.count - 1 { location += 1 }
        }
        return ranges.filter { $0.length > 0 }
    }

    private static func dedupe(_ ranges: [NSRange]) -> [NSRange] {
        var seen: Set<String> = []
        var result: [NSRange] = []
        for range in ranges where range.location != NSNotFound && range.length > 0 {
            let key = "\(range.location):\(range.length)"
            if seen.insert(key).inserted {
                result.append(range)
            }
        }
        return result.sorted { lhs, rhs in
            if lhs.location == rhs.location { return lhs.length < rhs.length }
            return lhs.location < rhs.location
        }
    }
}
