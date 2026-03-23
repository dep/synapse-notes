import AppKit

/// Utility to enumerate system fonts for the font picker
class FontEnumerator {
    /// Returns all available font family names on the system, sorted alphabetically
    static func allSystemFonts() -> [String] {
        let fontFamilies = NSFontManager.shared.availableFontFamilies
        // Sort alphabetically, case-insensitive
        return fontFamilies.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    /// Returns only monospace font families
    static func monospaceFonts() -> [String] {
        let allFonts = allSystemFonts()
        return allFonts.filter { fontFamily in
            // Get the first font in this family and check if it's monospace
            if let font = NSFont(name: fontFamily, size: 12) ?? NSFont(name: "\(fontFamily)-Regular", size: 12) {
                let traits = font.fontDescriptor.symbolicTraits
                return traits.contains(.monoSpace)
            }
            return false
        }
    }
    
    /// Returns font families suitable for body text (excludes decorative/symbol fonts)
    static func bodyFonts() -> [String] {
        let allFonts = allSystemFonts()
        let excludedPrefixes = [
            "Apple Symbols",
            "Webdings",
            "Wingdings",
            "Zapf Dingbats",
            "Symbols",
            "Emoji"
        ]
        
        return allFonts.filter { fontFamily in
            // Check if font starts with any excluded prefix
            for prefix in excludedPrefixes {
                if fontFamily.hasPrefix(prefix) {
                    return false
                }
            }
            return true
        }
    }
    
    /// Get display name for a font, handling the "System" option
    static func displayName(for fontFamily: String, isMonospace: Bool = false) -> String {
        if fontFamily.isEmpty {
            return isMonospace ? "System Monospace" : "System"
        }
        return fontFamily
    }
}
