import SwiftUI

// MARK: - AppTheme

/// A named collection of color tokens that defines the visual appearance of Synapse.
/// Colors are stored as hex strings (e.g. "#1e1e2e") for portability and JSON export/import.
struct AppTheme: Codable, Equatable, Identifiable {
    var name: String
    var colors: [String: String]

    // Stable id for SwiftUI list identity
    var id: String { name }

    init(name: String, colors: [String: String]) {
        self.name = name
        self.colors = colors
    }

    // MARK: - Helpers

    /// Whether this theme is one of the built-in presets (identified by matching name).
    var isBuiltIn: Bool {
        AppTheme.builtInThemeNames.contains(name)
    }

    /// Return a SwiftUI `Color` for the given token key, or nil if absent / invalid.
    func swiftUIColor(for key: String) -> Color? {
        guard let hex = colors[key] else { return nil }
        return Color(hex: hex)  // uses Color(hex:) defined below
    }

    /// Return an `NSColor` for the given token key, or nil if absent / invalid.
    func nsColor(for key: String) -> NSColor? {
        guard let hex = colors[key] else { return nil }
        return NSColor(hexString: hex)
    }
}

// MARK: - Built-in Themes

extension AppTheme {

    static let builtInThemeNames: Set<String> = [
        "Synapse (Dark)", "Synapse (Light)", "Solarized (Dark)", "Dracula (Dark)",
        "GitHub (Dark)", "Minimalist (Dark)", "Cyberpunk (Dark)", "Rainbow (Light)", "Rainbow (Dark)",
        "Protanopia (Dark)", "Deuteranopia (Dark)"
    ]

    // Canonical ordered list — first entry is the default.
    static let builtInThemes: [AppTheme] = [
        .synapseDark,
        .synapseLight,
        .solarized,
        .dracula,
        .githubDark,
        .minimalistDark,
        .cyberpunk,
        .rainbow,
        .rainbowDark,
        .protanopiaDark,
        .deuteranopiaDark,
    ]

    // MARK: Synapse (Dark) (current/default)
    static let synapseDark = AppTheme(
        name: "Synapse (Dark)",
        colors: [
            "background.primary":   "#0D0D0D",
            "background.secondary": "#121212",
            "background.elevated":  "#1A1A1A",
            "text.primary":         "#EBEBEB",
            "text.secondary":       "#ADADAD",
            "text.muted":           "#737373",
            "accent":               "#47A8FA",
            "accent.soft":          "#337AE3",
            "border":               "#141414",
            "divider":              "#0F0F0F",
            "row":                  "#0A0A0A",
            "success":              "#5ED499",
            "error":                "#F24D4D",
        ]
    )

    // MARK: Synapse (Light)
    static let synapseLight = AppTheme(
        name: "Synapse (Light)",
        colors: [
            "background.primary":   "#F5F5F5",
            "background.secondary": "#EBEBEB",
            "background.elevated":  "#FFFFFF",
            "text.primary":         "#1A1A1A",
            "text.secondary":       "#4A4A4A",
            "text.muted":           "#8A8A8A",
            "accent":               "#1A74D4",
            "accent.soft":          "#2F80D4",
            "border":               "#D0D0D0",
            "divider":              "#E0E0E0",
            "row":                  "#F0F0F0",
            "success":              "#2E9E5B",
            "error":                "#D13030",
        ]
    )

    // MARK: Solarized (Dark)
    static let solarized = AppTheme(
        name: "Solarized (Dark)",
        colors: [
            "background.primary":   "#002B36",
            "background.secondary": "#073642",
            "background.elevated":  "#0D4050",
            "text.primary":         "#93A1A1",
            "text.secondary":       "#657B83",
            "text.muted":           "#586E75",
            "accent":               "#268BD2",
            "accent.soft":          "#2176AE",
            "border":               "#0A3541",
            "divider":              "#073642",
            "row":                  "#00323E",
            "success":              "#859900",
            "error":                "#DC322F",
        ]
    )

    // MARK: Dracula (Dark)
    static let dracula = AppTheme(
        name: "Dracula (Dark)",
        colors: [
            "background.primary":   "#282A36",
            "background.secondary": "#21222C",
            "background.elevated":  "#343746",
            "text.primary":         "#F8F8F2",
            "text.secondary":       "#BFBFBF",
            "text.muted":           "#6272A4",
            "accent":               "#BD93F9",
            "accent.soft":          "#9F7FD6",
            "border":               "#3D3F52",
            "divider":              "#343746",
            "row":                  "#2D2F40",
            "success":              "#50FA7B",
            "error":                "#FF5555",
        ]
    )

    // MARK: GitHub (Dark)
    static let githubDark = AppTheme(
        name: "GitHub (Dark)",
        colors: [
            "background.primary":   "#0D1117",
            "background.secondary": "#161B22",
            "background.elevated":  "#21262D",
            "text.primary":         "#E6EDF3",
            "text.secondary":       "#9DA7B3",
            "text.muted":           "#7D8590",
            "accent":               "#2F81F7",
            "accent.soft":          "#1F6FEB",
            "border":               "#30363D",
            "divider":              "#21262D",
            "row":                  "#161B22",
            "success":              "#3FB950",
            "error":                "#F85149",
        ]
    )

    // MARK: Minimalist (Dark)
    static let minimalistDark = AppTheme(
        name: "Minimalist (Dark)",
        colors: [
            "background.primary":   "#111111",
            "background.secondary": "#171717",
            "background.elevated":  "#1E1E1E",
            "text.primary":         "#F2F2F2",
            "text.secondary":       "#C7C7C7",
            "text.muted":           "#8E8E8E",
            "accent":               "#5E5E5E",
            "accent.soft":          "#3F3F3F",
            "border":               "#2A2A2A",
            "divider":              "#202020",
            "row":                  "#151515",
            "success":              "#9AD68A",
            "error":                "#E57373",
        ]
    )

    // MARK: Cyberpunk (Dark)
    static let cyberpunk = AppTheme(
        name: "Cyberpunk (Dark)",
        colors: [
            "background.primary":   "#0B0A16",
            "background.secondary": "#121028",
            "background.elevated":  "#19163A",
            "text.primary":         "#F7F36B",
            "text.secondary":       "#F3A8FF",
            "text.muted":           "#8D88C7",
            "accent":               "#00F5D4",
            "accent.soft":          "#00C2A8",
            "border":               "#2A245E",
            "divider":              "#1E1A45",
            "row":                  "#14112E",
            "success":              "#72F1B8",
            "error":                "#FF4D9A",
        ]
    )

    // MARK: Rainbow (Light)
    static let rainbow = AppTheme(
        name: "Rainbow (Light)",
        colors: [
            "background.primary":   "#FFF7FB",
            "background.secondary": "#F8EEFF",
            "background.elevated":  "#FFFFFF",
            "text.primary":         "#2B1F3B",
            "text.secondary":       "#59457A",
            "text.muted":           "#8C76A8",
            "accent":               "#FF5FA2",
            "accent.soft":          "#7C5CFF",
            "border":               "#E5D7F4",
            "divider":              "#EEDFF8",
            "row":                  "#FDF1FF",
            "success":              "#22B573",
            "error":                "#FF5A6B",
        ]
    )

    // MARK: Rainbow (Dark)
    static let rainbowDark = AppTheme(
        name: "Rainbow (Dark)",
        colors: [
            "background.primary":   "#151226",
            "background.secondary": "#1B1733",
            "background.elevated":  "#251E45",
            "text.primary":         "#F7F1FF",
            "text.secondary":       "#D8C6FF",
            "text.muted":           "#9F8FC9",
            "accent":               "#FF5FA2",
            "accent.soft":          "#7C5CFF",
            "border":               "#362E63",
            "divider":              "#2B2350",
            "row":                  "#1F1A3C",
            "success":              "#41D98B",
            "error":                "#FF6B7A",
        ]
    )

    // MARK: Protanopia (Dark)
    static let protanopiaDark = AppTheme(
        name: "Protanopia (Dark)",
        colors: [
            "background.primary":   "#121820",
            "background.secondary": "#18222D",
            "background.elevated":  "#223040",
            "text.primary":         "#ECF3F9",
            "text.secondary":       "#BDD0E1",
            "text.muted":           "#89A0B6",
            "accent":               "#5AA9FF",
            "accent.soft":          "#3F82CC",
            "border":               "#2B3D50",
            "divider":              "#213243",
            "row":                  "#17222D",
            "success":              "#7FDBFF",
            "error":                "#FFB86B",
        ]
    )

    // MARK: Deuteranopia (Dark)
    static let deuteranopiaDark = AppTheme(
        name: "Deuteranopia (Dark)",
        colors: [
            "background.primary":   "#171524",
            "background.secondary": "#1E1B30",
            "background.elevated":  "#2A2542",
            "text.primary":         "#F4F2FF",
            "text.secondary":       "#D3CCF0",
            "text.muted":           "#9E97C2",
            "accent":               "#2F6E9F",
            "accent.soft":          "#234F73",
            "border":               "#38315A",
            "divider":              "#2C2647",
            "row":                  "#211D35",
            "success":              "#FFD166",
            "error":                "#FF8FAB",
        ]
    )
}

// MARK: - AppThemeExporter

enum AppThemeExporter {
    /// Encode a theme as pretty-printed JSON data suitable for saving to a .json file.
    static func exportData(for theme: AppTheme) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(theme)
    }
}

// MARK: - AppThemeImportError

enum AppThemeImportError: Error, LocalizedError {
    case invalidJSON(Error)
    case missingName
    case conflictsWithBuiltIn(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let err):
            return "Invalid JSON: \(err.localizedDescription)"
        case .missingName:
            return "The theme file is missing a name."
        case .conflictsWithBuiltIn(let name):
            return "\u{201C}\(name)\u{201D} is a built-in theme name and cannot be overwritten. Rename your theme in the JSON file and try again."
        }
    }
}

// MARK: - AppThemeImporter

enum AppThemeImporter {
    /// Decode a theme from JSON data.  Throws `AppThemeImportError` for validation failures.
    static func importTheme(from data: Data) throws -> AppTheme {
        let theme: AppTheme
        do {
            theme = try JSONDecoder().decode(AppTheme.self, from: data)
        } catch {
            throw AppThemeImportError.invalidJSON(error)
        }

        guard !theme.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppThemeImportError.missingName
        }

        if AppTheme.builtInThemeNames.contains(theme.name) {
            throw AppThemeImportError.conflictsWithBuiltIn(theme.name)
        }

        return theme
    }
}

// MARK: - Color hex helpers

extension Color {
    /// Initialize a SwiftUI Color from a hex string like "#RRGGBB".
    init?(hex: String) {
        guard let ns = NSColor(hexString: hex) else { return nil }
        self.init(ns)
    }
}

extension NSColor {
    /// Initialize an NSColor from a hex string like "#RRGGBB" or "#RRGGBBAA".
    /// Named `hexString:` to avoid conflict with the private `hex:` init in SyntaxHighlighter.swift.
    convenience init?(hexString: String) {
        var h = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h = String(h.dropFirst()) }
        guard h.count == 6 || h.count == 8 else { return nil }
        var value: UInt64 = 0
        guard Scanner(string: h).scanHexInt64(&value) else { return nil }
        let r, g, b, a: CGFloat
        if h.count == 6 {
            r = CGFloat((value >> 16) & 0xFF) / 255.0
            g = CGFloat((value >>  8) & 0xFF) / 255.0
            b = CGFloat((value      ) & 0xFF) / 255.0
            a = 1.0
        } else {
            r = CGFloat((value >> 24) & 0xFF) / 255.0
            g = CGFloat((value >> 16) & 0xFF) / 255.0
            b = CGFloat((value >>  8) & 0xFF) / 255.0
            a = CGFloat((value      ) & 0xFF) / 255.0
        }
        self.init(calibratedRed: r, green: g, blue: b, alpha: a)
    }
}
