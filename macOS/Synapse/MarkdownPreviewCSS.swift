import Foundation

struct MarkdownPreviewCSS {
    static func bodyFontStack(for fontFamily: String) -> String {
        if fontFamily.isEmpty || fontFamily == "System" {
            return "-apple-system, BlinkMacSystemFont, \"Segoe UI\", Roboto, sans-serif"
        }

        return "\"\(escape(fontFamily))\", sans-serif"
    }

    static func monoFontStack(for fontFamily: String) -> String {
        if fontFamily.isEmpty || fontFamily == "System Monospace" {
            return "\"SF Mono\", Monaco, \"Cascadia Code\", Menlo, monospace"
        }

        return "\"\(escape(fontFamily))\", monospace"
    }

    static func bodyFontSize(for baseSize: Int) -> Int {
        max(8, baseSize)
    }

    static func tableFontSize(for baseSize: Int) -> Int {
        max(12, baseSize - 1)
    }

    static func codeFontSize(for baseSize: Int) -> Int {
        max(10, baseSize - 2)
    }

    static func lineHeight(for value: Double) -> Double {
        max(0.8, min(3.0, value))
    }

    static func headingFontSize(level: Int, baseSize: Int) -> Int {
        let base = CGFloat(bodyFontSize(for: baseSize))
        let value: CGFloat

        switch level {
        case 1: value = round(base * 1.87)
        case 2: value = round(base * 1.47)
        case 3: value = round(base * 1.2)
        case 4: value = round(base * 1.07)
        case 5: value = round(base)
        default: value = max(12, round(base * 0.93))
        }

        return Int(value)
    }

    private static func escape(_ fontFamily: String) -> String {
        fontFamily
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
