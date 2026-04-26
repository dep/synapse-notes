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
        let mult: CGFloat
        switch level {
        case 1: mult = SynapseTheme.Editor.headingH1Multiplier
        case 2: mult = SynapseTheme.Editor.headingH2Multiplier
        case 3: mult = SynapseTheme.Editor.headingH3Multiplier
        case 4: mult = SynapseTheme.Editor.headingH4Multiplier
        case 5: mult = SynapseTheme.Editor.headingH5Multiplier
        default: mult = SynapseTheme.Editor.headingH6Multiplier
        }
        let value = round(base * mult)
        return Int(max(level >= 6 ? 12 : 8, value))
    }

    private static func escape(_ fontFamily: String) -> String {
        fontFamily
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
