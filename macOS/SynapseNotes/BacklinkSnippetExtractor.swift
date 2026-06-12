import Foundation

/// One contextual mention of a wikilink inside a source note.
struct BacklinkSnippet: Equatable {
    let text: String
    let lineNumber: Int
}

enum BacklinkSnippetExtractor {
    private static let wikiLinkRegex = try? NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#)

    /// Canonical wikilink target normalization shared with AppState:
    /// alias is stripped first ("Name|alias"), then heading ("Name#Section"),
    /// then whitespace trim and lowercase.
    static func normalize(_ value: String) -> String {
        value
            .split(separator: "|", maxSplits: 1)
            .first
            .map(String.init)?
            .split(separator: "#", maxSplits: 1)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    /// Returns up to `maxSnippets` lines of `content` containing a [[wikilink]]
    /// whose normalized target equals `normalizedTarget` (already lowercased).
    /// One snippet per line, in document order.
    static func snippets(ofNormalizedTarget normalizedTarget: String,
                         in content: String,
                         maxSnippets: Int = 3,
                         maxLength: Int = 160) -> [BacklinkSnippet] {
        guard !normalizedTarget.isEmpty, let regex = wikiLinkRegex else { return [] }

        var result: [BacklinkSnippet] = []
        let lines = content.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            guard result.count < maxSnippets else { break }

            let nsLine = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            let mentionsTarget = matches.contains { match in
                normalize(nsLine.substring(with: match.range(at: 1))) == normalizedTarget
            }
            guard mentionsTarget else { continue }

            var text = line.trimmingCharacters(in: .whitespaces)
            if text.count > maxLength {
                text = String(text.prefix(maxLength - 1)) + "…"
            }
            result.append(BacklinkSnippet(text: text, lineNumber: index + 1))
        }
        return result
    }
}
