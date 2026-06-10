import AppKit

// MARK: - HTML to Markdown Converter

/// Converts HTML content to Markdown using NSAttributedString for correct parsing,
/// then walks the attribute runs to emit Markdown syntax.
struct HTMLToMarkdownConverter {

    static func convert(_ html: String) -> String {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Wrap in a minimal HTML document so NSAttributedString's HTML renderer
        // uses the correct charset and a neutral sans-serif stylesheet. Without
        // the wrapper the renderer can misdetect encoding and apply a monospace /
        // code-block stylesheet to the entire content.
        let wrapped: String
        if trimmed.lowercased().hasPrefix("<!doctype") || trimmed.lowercased().hasPrefix("<html") {
            wrapped = trimmed
        } else {
            wrapped = """
            <!DOCTYPE html>
            <html><head><meta charset="UTF-8">
            <style>body { font-family: -apple-system, sans-serif; font-size: 13px; }</style>
            </head><body>\(trimmed)</body></html>
            """
        }

        guard let data = wrapped.data(using: .utf8) else { return trimmed }

        let opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]

        guard let attrStr = try? NSAttributedString(data: data, options: opts, documentAttributes: nil) else {
            return trimmed
        }

        return markdownFromAttributedString(attrStr)
    }

    // MARK: - Attributed string → Markdown

    private static func markdownFromAttributedString(_ attrStr: NSAttributedString) -> String {
        let fullString = attrStr.string
        var output = ""

        let nsString = fullString as NSString
        var paraStart = 0

        while paraStart < nsString.length {
            var paraEnd = 0
            var contentsEnd = 0
            nsString.getParagraphStart(nil, end: &paraEnd, contentsEnd: &contentsEnd,
                                       for: NSRange(location: paraStart, length: 0))

            let contentsRange = NSRange(location: paraStart, length: contentsEnd - paraStart)

            // Grab first-character attributes to classify the paragraph.
            let attrs = (paraEnd > paraStart)
                ? attrStr.attributes(at: paraStart, effectiveRange: nil)
                : [:]

            let paraStyle = attrs[.paragraphStyle] as? NSParagraphStyle
            let font      = attrs[.font] as? NSFont
            let fontSize  = font?.pointSize ?? 12
            let headingLevel = headingLevelForFontSize(fontSize)
            let isListItem   = isListItemParagraph(paraStyle)
            let isOrdered    = isOrderedListItem(attrStr, range: contentsRange)

            // Build inline content, suppressing bold on headings (NSAttributedString
            // makes heading text bold by default — that would double-format it).
            let inlineContent = inlineMarkdown(attrStr, range: contentsRange,
                                               suppressBold: headingLevel > 0)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if inlineContent.isEmpty {
                if !output.isEmpty { output += "\n" }
            } else if headingLevel > 0 {
                let hashes = String(repeating: "#", count: headingLevel)
                output += "\(hashes) \(inlineContent)\n\n"
            } else if isListItem {
                let marker = isOrdered ? "1." : "-"
                let indent = indentForParagraphStyle(paraStyle)
                output += "\(indent)\(marker) \(inlineContent)\n"
            } else {
                output += "\(inlineContent)\n\n"
            }

            paraStart = paraEnd
        }

        return output
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Inline span rendering

    private static func inlineMarkdown(_ attrStr: NSAttributedString, range: NSRange,
                                       suppressBold: Bool = false) -> String {
        guard range.length > 0 else { return "" }

        var output = ""

        attrStr.enumerateAttributes(in: range, options: []) { attrs, spanRange, _ in
            let text = (attrStr.string as NSString).substring(with: spanRange)

            // Strip tabs (list marker column) and Unicode bullets NSAttributedString
            // inserts for <ul> items (U+2022 •, U+25E6 ◦, U+25AA ▪, etc.)
            var cleaned = text.replacingOccurrences(of: "\t", with: "")
            cleaned = cleaned.unicodeScalars.filter { scalar in
                // Drop Unicode list-marker bullet characters
                ![0x2022, 0x25E6, 0x25AA, 0x25AB, 0x2023, 0x2043].contains(scalar.value)
            }.reduce("") { $0 + String($1) }

            guard !cleaned.isEmpty else { return }

            let font    = attrs[.font] as? NSFont
            let isBold  = !suppressBold && (font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)
            let isItalic = font?.fontDescriptor.symbolicTraits.contains(.italic) ?? false
            let isMono  = font?.fontDescriptor.symbolicTraits.contains(.monoSpace) ?? false
            let link    = attrs[.link] as? URL
                       ?? (attrs[.link] as? String).flatMap { URL(string: $0) }

            var span = cleaned

            if isMono {
                span = "`\(span)`"
            } else {
                if isBold && isItalic { span = "***\(span)***" }
                else if isBold        { span = "**\(span)**" }
                else if isItalic      { span = "_\(span)_" }
            }

            if let url = link, !isMono {
                span = "[\(cleaned)](\(url.absoluteString))"
            }

            output += span
        }

        return output
    }

    // MARK: - Helpers

    /// Map NSAttributedString's rendered font sizes back to heading levels.
    /// Empirical values on macOS 14/15 with default system HTML stylesheet:
    ///   h1 → ~24pt, h2 → ~18pt, h3 → ~14pt bold, h4-h6 → 12pt bold
    private static func headingLevelForFontSize(_ size: CGFloat) -> Int {
        switch size {
        case 22...: return 1
        case 17..<22: return 2
        case 14..<17: return 3
        default: return 0
        }
    }

    private static func isListItemParagraph(_ style: NSParagraphStyle?) -> Bool {
        guard let style else { return false }
        return style.headIndent > 0 && !style.tabStops.isEmpty
    }

    private static func isOrderedListItem(_ attrStr: NSAttributedString, range: NSRange) -> Bool {
        guard range.length > 0 else { return false }
        let raw = (attrStr.string as NSString).substring(with: range)
        // Ordered items start with a tab followed by a digit and a period.
        return raw.hasPrefix("\t") && raw.dropFirst().first?.isNumber == true
    }

    private static func indentForParagraphStyle(_ style: NSParagraphStyle?) -> String {
        guard let style, style.headIndent > 36 else { return "" }
        let extraLevels = Int((style.headIndent - 18) / 18)
        return String(repeating: "    ", count: max(0, extraLevels))
    }
}
