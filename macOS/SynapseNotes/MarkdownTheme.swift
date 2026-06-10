import AppKit

// MARK: - Markdown styling theme

struct MarkdownTheme {
    // MARK: - Font functions based on SettingsManager

    static func bodyFont(for settings: SettingsManager) -> NSFont {
        let size = CGFloat(settings.editorFontSize)
        if settings.editorBodyFontFamily.isEmpty || settings.editorBodyFontFamily == "System" {
            return NSFont.systemFont(ofSize: size)
        }
        return NSFont(name: settings.editorBodyFontFamily, size: size) ?? NSFont.systemFont(ofSize: size)
    }

    static func monoFont(for settings: SettingsManager) -> NSFont {
        let baseSize = CGFloat(settings.editorFontSize)
        let size = max(10, baseSize / SynapseTheme.Layout.phi)
        if settings.editorMonospaceFontFamily.isEmpty || settings.editorMonospaceFontFamily == "System Monospace" {
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
        return NSFont(name: settings.editorMonospaceFontFamily, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static func h1Font(for settings: SettingsManager) -> NSFont {
        let size = round(CGFloat(settings.editorFontSize) * SynapseTheme.Editor.headingH1Multiplier)
        if settings.editorBodyFontFamily.isEmpty || settings.editorBodyFontFamily == "System" {
            return NSFont.systemFont(ofSize: size, weight: .bold)
        }
        return NSFont(name: settings.editorBodyFontFamily, size: size)?.withWeight(.bold)
            ?? NSFont.systemFont(ofSize: size, weight: .bold)
    }

    static func h2Font(for settings: SettingsManager) -> NSFont {
        let size = round(CGFloat(settings.editorFontSize) * SynapseTheme.Editor.headingH2Multiplier)
        if settings.editorBodyFontFamily.isEmpty || settings.editorBodyFontFamily == "System" {
            return NSFont.systemFont(ofSize: size, weight: .bold)
        }
        return NSFont(name: settings.editorBodyFontFamily, size: size)?.withWeight(.bold)
            ?? NSFont.systemFont(ofSize: size, weight: .bold)
    }

    static func h3Font(for settings: SettingsManager) -> NSFont {
        let size = round(CGFloat(settings.editorFontSize) * SynapseTheme.Editor.headingH3Multiplier)
        if settings.editorBodyFontFamily.isEmpty || settings.editorBodyFontFamily == "System" {
            return NSFont.systemFont(ofSize: size, weight: .semibold)
        }
        return NSFont(name: settings.editorBodyFontFamily, size: size)?.withWeight(.semibold)
            ?? NSFont.systemFont(ofSize: size, weight: .semibold)
    }

    static func h4Font(for settings: SettingsManager) -> NSFont {
        let size = round(CGFloat(settings.editorFontSize) * SynapseTheme.Editor.headingH4Multiplier)
        if settings.editorBodyFontFamily.isEmpty || settings.editorBodyFontFamily == "System" {
            return NSFont.systemFont(ofSize: size, weight: .semibold)
        }
        return NSFont(name: settings.editorBodyFontFamily, size: size)?.withWeight(.semibold)
            ?? NSFont.systemFont(ofSize: size, weight: .semibold)
    }

    static func boldFont(for settings: SettingsManager) -> NSFont {
        let size = CGFloat(settings.editorFontSize)
        if settings.editorBodyFontFamily.isEmpty || settings.editorBodyFontFamily == "System" {
            return NSFont.systemFont(ofSize: size, weight: .bold)
        }
        return NSFont(name: settings.editorBodyFontFamily, size: size)?.withWeight(.bold)
            ?? NSFont.systemFont(ofSize: size, weight: .bold)
    }

    static func italicFont(for settings: SettingsManager) -> NSFont {
        let size = CGFloat(settings.editorFontSize)
        if settings.editorBodyFontFamily.isEmpty || settings.editorBodyFontFamily == "System" {
            let descriptor = NSFont.systemFont(ofSize: size).fontDescriptor.withSymbolicTraits(.italic)
            return NSFont(descriptor: descriptor, size: size) ?? NSFont.systemFont(ofSize: size)
        }
        let baseFont = NSFont(name: settings.editorBodyFontFamily, size: size) ?? NSFont.systemFont(ofSize: size)
        let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: descriptor, size: size) ?? baseFont
    }

    static func boldItalicFont(for settings: SettingsManager) -> NSFont {
        let size = CGFloat(settings.editorFontSize)
        let bold = boldFont(for: settings)
        let descriptor = bold.fontDescriptor.withSymbolicTraits([.bold, .italic])
        return NSFont(descriptor: descriptor, size: size) ?? bold
    }

    static func lineHeightMultiple(for settings: SettingsManager) -> CGFloat {
        max(0.8, min(3.0, CGFloat(settings.editorLineHeight)))
    }

    /// Paragraph style whose line box matches CSS `line-height: multiple` — i.e. a
    /// multiple of the FONT SIZE, not of the font's natural line height. NSTextView's
    /// natural line height already bakes in the font's intrinsic leading (~1.18× for
    /// SF), so multiplying that by the user's multiple over-spaced lines versus the
    /// HTML preview. We set the line box directly to `fontSize * multiple`, floored at
    /// the natural height so small multiples never clip glyphs (CSS overlaps instead of
    /// cropping; a hard maximumLineHeight below natural would crop).
    static func paragraphStyle(font: NSFont, lineHeightMultiple multiple: CGFloat) -> NSMutableParagraphStyle {
        let naturalLineHeight = font.ascender - font.descender + font.leading
        let targetLineHeight = font.pointSize * multiple
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = targetLineHeight
        style.maximumLineHeight = max(targetLineHeight, naturalLineHeight)
        style.lineSpacing = 0
        return style
    }

    // MARK: - Legacy static constants (for backward compatibility)

    static let body = NSFont.systemFont(ofSize: 15)
    static let mono = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    static let h1   = NSFont.systemFont(ofSize: round(SynapseTheme.Editor.h1FontSize), weight: .bold)
    static let h2   = NSFont.systemFont(ofSize: round(SynapseTheme.Editor.h2FontSize), weight: .bold)
    static let h3   = NSFont.systemFont(ofSize: round(SynapseTheme.Editor.h3FontSize), weight: .semibold)
    static let h4   = NSFont.systemFont(ofSize: round(SynapseTheme.Editor.h4FontSize), weight: .semibold)
    // Use static var so these read from ThemeEnvironment.shared at each call-site
    // rather than being frozen at class-load time.
    static var dimColor:            NSColor { SynapseTheme.editorMuted }
    static var tagColor:            NSColor { SynapseTheme.editorLink }
    static var linkColor:           NSColor { SynapseTheme.editorLink }
    static var unresolvedLinkColor: NSColor { SynapseTheme.editorUnresolvedLink }
    static var codeBackground:      NSColor { SynapseTheme.editorCodeBackground }
}

// Helper extension to apply font weight
private extension NSFont {
    func withWeight(_ weight: NSFont.Weight) -> NSFont {
        // Create a new font descriptor with the desired weight trait
        var traits = fontDescriptor.symbolicTraits
        // Map NSFont.Weight to NSFontDescriptor.SymbolicTraits
        if weight == .bold || weight.rawValue >= NSFont.Weight.bold.rawValue {
            traits.insert(.bold)
        } else if weight == .semibold || weight.rawValue >= NSFont.Weight.semibold.rawValue {
            traits.insert(.bold)
        }
        let descriptor = fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
