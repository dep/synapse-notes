import AppKit
import Foundation

struct SyntaxHighlighter {
    enum TokenType {
        case comment
        case string
        case keyword
        case number
        case function
        case property
        case type
    }

    struct HighlightSpan {
        let type: TokenType
        let range: NSRange
    }

    private static let aliasMap: [String: String] = [
        "js": "javascript",
        "ts": "typescript",
        "py": "python",
        "rb": "ruby",
        "sh": "bash",
        "zsh": "bash",
        "shell": "bash",
        "yml": "yaml",
        "md": "markdown",
        "c++": "cpp",
        "cplusplus": "cpp",
    ]

    static let supportedLanguages: Set<String> = [
        "swift", "javascript", "typescript", "json", "yaml", "python",
        "bash", "html", "css", "markdown", "ruby", "go", "rust",
        "sql", "c", "cpp",
    ]

    static func canonicalLanguage(_ language: String?) -> String? {
        guard let raw = language?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else {
            return nil
        }
        return aliasMap[raw] ?? raw
    }

    static func isSupportedLanguage(_ language: String?) -> Bool {
        guard let canonical = canonicalLanguage(language) else { return false }
        return supportedLanguages.contains(canonical)
    }

    static func highlightedHTML(for code: String, language: String?) -> String {
        guard let canonical = canonicalLanguage(language), supportedLanguages.contains(canonical) else {
            return escapeHTML(code)
        }

        return renderHTML(code: code, spans: highlightSpans(in: code, language: canonical))
    }

    static func apply(
        to storage: NSTextStorage,
        codeRange: NSRange,
        language: String?,
        baseFont: NSFont,
        isDarkMode: Bool
    ) {
        guard let canonical = canonicalLanguage(language), supportedLanguages.contains(canonical) else {
            return
        }
        guard codeRange.location != NSNotFound, codeRange.length > 0, NSMaxRange(codeRange) <= storage.length else {
            return
        }

        let code = (storage.string as NSString).substring(with: codeRange)
        let palette = isDarkMode ? SyntaxHighlightTheme.dark : SyntaxHighlightTheme.light

        for span in highlightSpans(in: code, language: canonical) {
            let adjustedRange = NSRange(location: codeRange.location + span.range.location, length: span.range.length)
            guard NSMaxRange(adjustedRange) <= storage.length else { continue }
            storage.addAttributes([
                .font: baseFont,
                .foregroundColor: palette.color(for: span.type),
            ], range: adjustedRange)
        }
    }

    private static func highlightSpans(in code: String, language: String) -> [HighlightSpan] {
        let nsCode = code as NSString
        let fullRange = NSRange(location: 0, length: nsCode.length)
        var spans: [HighlightSpan] = []

        for rule in rules(for: language) {
            rule.regex.enumerateMatches(in: code, options: [], range: fullRange) { match, _, _ in
                guard let match else { return }
                let range = rule.captureGroup.flatMap { group -> NSRange? in
                    guard match.numberOfRanges > group else { return nil }
                    let candidate = match.range(at: group)
                    return candidate.location == NSNotFound ? nil : candidate
                } ?? match.range(at: 0)

                guard range.location != NSNotFound, range.length > 0 else { return }
                guard !spans.contains(where: { NSIntersectionRange($0.range, range).length > 0 }) else { return }
                spans.append(HighlightSpan(type: rule.type, range: range))
            }
        }

        return spans.sorted { lhs, rhs in
            if lhs.range.location == rhs.range.location {
                return lhs.range.length < rhs.range.length
            }
            return lhs.range.location < rhs.range.location
        }
    }

    private struct Rule {
        let type: TokenType
        let regex: NSRegularExpression
        let captureGroup: Int?
    }

    private static func rules(for language: String) -> [Rule] {
        let stringRule = rule(.string, #""(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`(?:[^`\\]|\\.)*`"#)
        let numberRule = rule(.number, #"\b(?:0[xX][0-9A-Fa-f]+|\d+(?:\.\d+)?)\b"#)

        switch language {
        case "swift":
            return [
                rule(.comment, #"//.*|/\*[\s\S]*?\*/"#),
                stringRule,
                rule(.keyword, #"\b(?:actor|as|async|await|break|case|catch|class|continue|default|defer|do|else|enum|extension|fallthrough|false|for|func|guard|if|import|in|init|let|nil|private|protocol|public|return|self|static|struct|switch|throw|throws|true|try|typealias|var|where|while)\b"#),
                numberRule,
                rule(.function, #"\b([A-Za-z_][A-Za-z0-9_]*)\s*\("#, captureGroup: 1),
                rule(.type, #"\b[A-Z][A-Za-z0-9_]*\b"#),
            ]
        case "javascript", "typescript":
            return [
                rule(.comment, #"//.*|/\*[\s\S]*?\*/"#),
                stringRule,
                rule(.keyword, #"\b(?:async|await|break|case|catch|class|const|continue|default|delete|else|export|extends|false|finally|for|from|function|if|import|in|instanceof|interface|let|new|null|return|static|super|switch|this|throw|true|try|typeof|undefined|var|while|yield|type|implements|public|private|protected|readonly)\b"#),
                numberRule,
                rule(.function, #"\b([A-Za-z_$][A-Za-z0-9_$]*)\s*\("#, captureGroup: 1),
            ]
        case "json":
            return [
                stringRule,
                rule(.property, #""([^"\\]|\\.)*"\s*:"#),
                rule(.keyword, #"\b(?:true|false|null)\b"#),
                numberRule,
            ]
        case "yaml":
            return [
                rule(.comment, #"#.*"#),
                stringRule,
                rule(.property, #"^\s*-?\s*([A-Za-z0-9_.-]+)(?=\s*:)"#, options: [.anchorsMatchLines], captureGroup: 1),
                rule(.keyword, #"\b(?:true|false|null|yes|no|on|off)\b"#),
                numberRule,
            ]
        case "python":
            return [
                rule(.comment, #"#.*"#),
                stringRule,
                rule(.keyword, #"\b(?:and|as|assert|async|await|break|class|continue|def|elif|else|except|False|finally|for|from|if|import|in|is|lambda|None|nonlocal|not|or|pass|raise|return|True|try|while|with|yield)\b"#),
                numberRule,
                rule(.function, #"\bdef\s+([A-Za-z_][A-Za-z0-9_]*)"#, captureGroup: 1),
                rule(.type, #"\b[A-Z][A-Za-z0-9_]*\b"#),
            ]
        case "bash":
            return [
                rule(.comment, #"#.*"#),
                rule(.string, #""(?:[^"\\]|\\.)*"|'[^']*'"#),
                rule(.keyword, #"\b(?:case|do|done|elif|else|esac|exit|export|fi|for|function|if|in|local|return|then|while)\b"#),
                numberRule,
            ]
        case "html":
            return [
                rule(.comment, #"<!--[\s\S]*?-->"#),
                rule(.type, #"</?[A-Za-z][^>\s/]*"#),
                rule(.property, #"\b[A-Za-z_:][-A-Za-z0-9_:.]*(?=\=)"#),
                stringRule,
            ]
        case "css":
            return [
                rule(.comment, #"/\*[\s\S]*?\*/"#),
                stringRule,
                rule(.keyword, #"@[A-Za-z-]+"#),
                rule(.property, #"\b[A-Za-z-]+(?=\s*:)"#),
                numberRule,
            ]
        case "markdown":
            return [
                rule(.comment, #"\[[^\]]+\]\([^)]+\)"#),
                rule(.keyword, #"^(?:#{1,6}|>|\s*[-*+]\s|\s*\d+\.)"#, options: [.anchorsMatchLines]),
                rule(.string, #"`[^`]+`|\*\*[^*]+\*\*|\*[^*]+\*"#),
            ]
        case "ruby":
            return [
                rule(.comment, #"#.*"#),
                stringRule,
                rule(.keyword, #"\b(?:BEGIN|END|alias|begin|break|case|class|def|do|else|elsif|end|ensure|false|for|if|in|module|next|nil|redo|rescue|retry|return|self|super|then|true|undef|unless|until|when|while|yield)\b"#),
                numberRule,
                rule(.function, #"\bdef\s+([A-Za-z_][A-Za-z0-9_]*[!?=]?)"#, captureGroup: 1),
            ]
        case "go":
            return [
                rule(.comment, #"//.*|/\*[\s\S]*?\*/"#),
                stringRule,
                rule(.keyword, #"\b(?:break|case|chan|const|continue|default|defer|else|fallthrough|for|func|go|goto|if|import|interface|map|package|range|return|select|struct|switch|type|var)\b"#),
                numberRule,
                rule(.function, #"\bfunc\s+([A-Za-z_][A-Za-z0-9_]*)"#, captureGroup: 1),
                rule(.type, #"\b[A-Z][A-Za-z0-9_]*\b"#),
            ]
        case "rust":
            return [
                rule(.comment, #"//.*|/\*[\s\S]*?\*/"#),
                stringRule,
                rule(.keyword, #"\b(?:as|async|await|break|const|continue|crate|else|enum|extern|false|fn|for|if|impl|in|let|loop|match|mod|move|mut|pub|ref|return|self|Self|static|struct|super|trait|true|type|unsafe|use|where|while)\b"#),
                numberRule,
                rule(.function, #"\bfn\s+([A-Za-z_][A-Za-z0-9_]*)"#, captureGroup: 1),
                rule(.type, #"\b[A-Z][A-Za-z0-9_]*\b"#),
            ]
        case "sql":
            return [
                rule(.comment, #"--.*|/\*[\s\S]*?\*/"#),
                stringRule,
                rule(.keyword, #"\b(?:add|alter|and|as|asc|between|by|case|create|delete|desc|distinct|drop|else|end|exists|from|group|having|in|inner|insert|into|is|join|left|like|limit|not|null|on|or|order|outer|right|select|set|table|then|union|update|values|when|where)\b"#, options: [.caseInsensitive]),
                numberRule,
            ]
        case "c", "cpp":
            return [
                rule(.comment, #"//.*|/\*[\s\S]*?\*/"#),
                stringRule,
                rule(.keyword, #"\b(?:auto|bool|break|case|char|class|const|continue|default|do|double|else|enum|extern|false|float|for|if|inline|int|long|namespace|private|protected|public|register|return|short|signed|sizeof|static|struct|switch|template|true|typedef|typename|union|unsigned|using|void|volatile|while)\b"#),
                numberRule,
                rule(.function, #"\b([A-Za-z_][A-Za-z0-9_]*)\s*\("#, captureGroup: 1),
                rule(.type, #"\b[A-Z][A-Za-z0-9_]*\b"#),
            ]
        default:
            return []
        }
    }

    private static func rule(
        _ type: TokenType,
        _ pattern: String,
        options: NSRegularExpression.Options = [],
        captureGroup: Int? = nil
    ) -> Rule {
        Rule(type: type, regex: try! NSRegularExpression(pattern: pattern, options: options), captureGroup: captureGroup)
    }

    private static func renderHTML(code: String, spans: [HighlightSpan]) -> String {
        let nsCode = code as NSString
        var html = ""
        var cursor = 0

        for span in spans {
            if span.range.location > cursor {
                html += escapeHTML(nsCode.substring(with: NSRange(location: cursor, length: span.range.location - cursor)))
            }

            let cssClass = cssClass(for: span.type)
            let tokenText = nsCode.substring(with: span.range)
            html += "<span class=\"\(cssClass)\">\(escapeHTML(tokenText))</span>"
            cursor = NSMaxRange(span.range)
        }

        if cursor < nsCode.length {
            html += escapeHTML(nsCode.substring(with: NSRange(location: cursor, length: nsCode.length - cursor)))
        }

        return html
    }

    private static func cssClass(for type: TokenType) -> String {
        switch type {
        case .comment: return "hljs-comment"
        case .string: return "hljs-string"
        case .keyword: return "hljs-keyword"
        case .number: return "hljs-number"
        case .function: return "hljs-function"
        case .property: return "hljs-property"
        case .type: return "hljs-type"
        }
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

struct SyntaxHighlightTheme {
    let plain: NSColor
    let comment: NSColor
    let string: NSColor
    let keyword: NSColor
    let number: NSColor
    let function: NSColor
    let property: NSColor
    let type: NSColor

    func color(for type: SyntaxHighlighter.TokenType) -> NSColor {
        switch type {
        case .comment: return comment
        case .string: return string
        case .keyword: return keyword
        case .number: return number
        case .function: return function
        case .property: return property
        case .type: return self.type
        }
    }

    static let light = SyntaxHighlightTheme(
        plain: NSColor(hex: "#333333"),
        comment: NSColor(hex: "#6A737D"),
        string: NSColor(hex: "#032F62"),
        keyword: NSColor(hex: "#D73A49"),
        number: NSColor(hex: "#005CC5"),
        function: NSColor(hex: "#6F42C1"),
        property: NSColor(hex: "#005CC5"),
        type: NSColor(hex: "#22863A")
    )

    static let dark = SyntaxHighlightTheme(
        plain: NSColor(hex: "#E6EDF3"),
        comment: NSColor(hex: "#8B949E"),
        string: NSColor(hex: "#A5D6FF"),
        keyword: NSColor(hex: "#FF7B72"),
        number: NSColor(hex: "#79C0FF"),
        function: NSColor(hex: "#D2A8FF"),
        property: NSColor(hex: "#79C0FF"),
        type: NSColor(hex: "#7EE787")
    )

    static func css(forDarkMode isDarkMode: Bool) -> String {
        let palette = isDarkMode ? dark : light
        return """
        .hljs { color: \(palette.plain.cssHex); }
        .hljs-comment { color: \(palette.comment.cssHex); font-style: italic; }
        .hljs-string { color: \(palette.string.cssHex); }
        .hljs-keyword { color: \(palette.keyword.cssHex); font-weight: 600; }
        .hljs-number { color: \(palette.number.cssHex); }
        .hljs-function { color: \(palette.function.cssHex); }
        .hljs-property { color: \(palette.property.cssHex); }
        .hljs-type { color: \(palette.type.cssHex); }
        """
    }
}

private extension NSColor {
    convenience init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: trimmed).scanHexInt64(&value)
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    var cssHex: String {
        let converted = usingColorSpace(.deviceRGB) ?? self
        return String(
            format: "#%02X%02X%02X",
            Int(converted.redComponent * 255),
            Int(converted.greenComponent * 255),
            Int(converted.blueComponent * 255)
        )
    }
}
