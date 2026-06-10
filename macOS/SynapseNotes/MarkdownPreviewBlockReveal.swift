import Foundation

/// Computes the set of previously-hidden markdown syntax ranges to *reveal* for the
/// single parsed block the caret is currently inside, when hide-markdown-while-typing
/// is active. This is the inverse of the hide pass in `applyPreviewStyling`: it reuses
/// `MarkdownPreviewSemanticHiding` for structural/inline tokens and the same
/// bold/italic/inline-code delimiter regexes, then intersects everything with the
/// caret's block range so only the current block reveals.
struct MarkdownPreviewBlockReveal {
    let revealedRanges: [NSRange]
    /// The range of the block the caret is in (nil when the caret is in no block).
    /// Callers use this to skip recomputation while the caret stays in one block.
    let blockRange: NSRange?

    static func make(from source: String, cursorLocation: Int, isEditable: Bool, parser: MarkdownDocumentParser = MarkdownDocumentParser()) -> MarkdownPreviewBlockReveal {
        guard isEditable, cursorLocation != NSNotFound else {
            return MarkdownPreviewBlockReveal(revealedRanges: [], blockRange: nil)
        }
        return make(document: parser.parse(source), cursorLocation: cursorLocation, isEditable: isEditable)
    }

    /// Variant for callers that already hold a parse of the current text (e.g. the
    /// per-caret-move reveal path, which memoizes the document across selection changes).
    static func make(document: MarkdownDocument, cursorLocation: Int, isEditable: Bool) -> MarkdownPreviewBlockReveal {
        guard isEditable, cursorLocation != NSNotFound else {
            return MarkdownPreviewBlockReveal(revealedRanges: [], blockRange: nil)
        }

        let ns = document.source as NSString

        // Find the block containing the caret. A caret exactly at a block's end
        // boundary still counts as inside that block (matches the inline-reveal rule).
        guard let block = document.blocks.first(where: { block in
            cursorLocation >= block.range.location &&
            cursorLocation <= block.range.location + block.range.length
        }) else {
            return MarkdownPreviewBlockReveal(revealedRanges: [], blockRange: nil)
        }

        var ranges: [NSRange] = []

        // 1. Structural + inline-token hidden ranges (headings, blockquote markers,
        //    fence lines, frontmatter fences, link/wikilink/embed/highlight delimiters).
        let hiding = MarkdownPreviewSemanticHiding.make(from: document, isEditable: isEditable)
        for range in hiding.hiddenRanges where NSIntersectionRange(range, block.range).length > 0 {
            ranges.append(range)
        }

        // 2. Bold/italic/inline-code delimiter ranges (NOT part of hiddenRanges; the hide
        //    pass applies these via regex). Same patterns as applyPreviewStyling, scoped
        //    to the block range so we only reveal the caret's block.
        let blockText = ns.substring(with: block.range)
        let base = block.range.location

        func appendGroup(_ pattern: String, group: Int) {
            guard let regex = cachedRegex(pattern) else { return }
            let blockNS = blockText as NSString
            regex.enumerateMatches(in: blockText, options: [], range: NSRange(location: 0, length: blockNS.length)) { match, _, _ in
                guard let match, match.numberOfRanges > group else { return }
                let r = match.range(at: group)
                guard r.location != NSNotFound else { return }
                ranges.append(NSRange(location: base + r.location, length: r.length))
            }
        }

        // Bold **text** / __text__
        appendGroup("(\\*\\*)(.+?)(\\*\\*)", group: 1)
        appendGroup("(\\*\\*)(.+?)(\\*\\*)", group: 3)
        appendGroup("(__)(.+?)(__)", group: 1)
        appendGroup("(__)(.+?)(__)", group: 3)
        // Italic *text* (not **)
        appendGroup("(?<!\\*)(\\*)(?!\\*)(.+?)(?<!\\*)(\\*)(?!\\*)", group: 1)
        appendGroup("(?<!\\*)(\\*)(?!\\*)(.+?)(?<!\\*)(\\*)(?!\\*)", group: 3)
        // Inline code `code` (skip when the block IS a fenced code block — its content
        // is shown verbatim and the fences are already covered by hiddenRanges above).
        if case .fencedCodeBlock = block.kind {
            // no inline-code delimiters to reveal inside a code block
        } else {
            appendGroup("(`)((?:[^`\\n])+)(`)", group: 1)
            appendGroup("(`)((?:[^`\\n])+)(`)", group: 3)
        }

        return MarkdownPreviewBlockReveal(revealedRanges: dedupe(ranges), blockRange: block.range)
    }

    /// Compiled-once regex cache — this runs on every caret-driven block reveal, and
    /// recompiling the eight delimiter patterns per call dominated its cost.
    private static var regexCache: [String: NSRegularExpression] = [:]

    private static func cachedRegex(_ pattern: String) -> NSRegularExpression? {
        if let cached = regexCache[pattern] { return cached }
        guard let compiled = try? NSRegularExpression(pattern: pattern) else { return nil }
        regexCache[pattern] = compiled
        return compiled
    }

    private static func dedupe(_ ranges: [NSRange]) -> [NSRange] {
        var seen: Set<String> = []
        var result: [NSRange] = []
        for range in ranges where range.location != NSNotFound && range.length > 0 {
            let key = "\(range.location):\(range.length)"
            if seen.insert(key).inserted { result.append(range) }
        }
        return result
    }
}
