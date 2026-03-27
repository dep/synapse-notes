import XCTest
@testable import Synapse

// MARK: - AppTheme model tests

final class AppThemeTests: XCTestCase {

    // MARK: Built-in themes exist

    func test_builtInThemes_containsExpectedNames() {
        let names = AppTheme.builtInThemes.map(\.name)
        XCTAssertTrue(names.contains("Synapse (Dark)"))
        XCTAssertTrue(names.contains("Synapse (Light)"))
        XCTAssertTrue(names.contains("Solarized (Dark)"))
        XCTAssertTrue(names.contains("Dracula (Dark)"))
        XCTAssertTrue(names.contains("GitHub (Dark)"))
        XCTAssertTrue(names.contains("Minimalist (Dark)"))
        XCTAssertTrue(names.contains("Cyberpunk (Dark)"))
        XCTAssertTrue(names.contains("Rainbow (Light)"))
        XCTAssertTrue(names.contains("Rainbow (Dark)"))
        XCTAssertTrue(names.contains("Protanopia (Dark)"))
        XCTAssertTrue(names.contains("Deuteranopia (Dark)"))
    }

    func test_builtInThemes_containsElevenThemes() {
        XCTAssertEqual(AppTheme.builtInThemes.count, 11)
    }

    func test_minimalistDark_usesReadableSelectionAccentTokens() {
        XCTAssertEqual(AppTheme.minimalistDark.colors["accent"], "#5E5E5E")
        XCTAssertEqual(AppTheme.minimalistDark.colors["accent.soft"], "#3F3F3F")
    }

    func test_colorblindDarkThemes_useDistinctNonRedGreenSignals() {
        XCTAssertEqual(AppTheme.protanopiaDark.colors["accent"], "#5AA9FF")
        XCTAssertEqual(AppTheme.protanopiaDark.colors["success"], "#7FDBFF")
        XCTAssertEqual(AppTheme.protanopiaDark.colors["error"], "#FFB86B")

        XCTAssertEqual(AppTheme.deuteranopiaDark.colors["accent"], "#2F6E9F")
        XCTAssertEqual(AppTheme.deuteranopiaDark.colors["success"], "#FFD166")
        XCTAssertEqual(AppTheme.deuteranopiaDark.colors["error"], "#FF8FAB")
    }

    func test_builtInThemes_synapseDarkIsDefault() {
        XCTAssertEqual(AppTheme.builtInThemes.first?.name, "Synapse (Dark)")
    }

    func test_builtInThemes_haveRequiredColorKeys() {
        let requiredKeys: Set<String> = [
            "background.primary",
            "background.secondary",
            "background.elevated",
            "text.primary",
            "text.secondary",
            "text.muted",
            "accent",
            "accent.soft",
            "border",
            "divider",
            "row",
            "success",
            "error",
        ]
        for theme in AppTheme.builtInThemes {
            for key in requiredKeys {
                XCTAssertNotNil(theme.colors[key], "Theme '\(theme.name)' missing color key '\(key)'")
            }
        }
    }

    func test_builtInThemes_colorValuesAreValidHex() {
        for theme in AppTheme.builtInThemes {
            for (key, value) in theme.colors {
                XCTAssertTrue(
                    value.hasPrefix("#") && (value.count == 7 || value.count == 9),
                    "Theme '\(theme.name)' key '\(key)' has invalid hex '\(value)'"
                )
            }
        }
    }

    // MARK: AppTheme Codable round-trip

    func test_appTheme_encodesAndDecodesFromJSON() throws {
        let original = AppTheme(
            name: "My Theme",
            colors: ["background.primary": "#1e1e2e", "accent": "#89b4fa"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppTheme.self, from: data)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.colors, original.colors)
    }

    func test_appTheme_jsonExportFormat() throws {
        let theme = AppTheme(
            name: "My Custom Theme",
            colors: [
                "background.primary": "#1e1e2e",
                "accent": "#89b4fa",
            ]
        )
        let data = try JSONEncoder().encode(theme)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["name"] as? String, "My Custom Theme")
        let colors = json["colors"] as? [String: String]
        XCTAssertEqual(colors?["background.primary"], "#1e1e2e")
        XCTAssertEqual(colors?["accent"], "#89b4fa")
    }

    func test_appTheme_importFromJSONData() throws {
        let json = """
        {
            "name": "My Custom Theme",
            "colors": {
                "background.primary": "#1e1e2e",
                "background.secondary": "#181825",
                "text.primary": "#cdd6f4",
                "text.muted": "#a6adc8",
                "accent": "#89b4fa",
                "border": "#313244"
            }
        }
        """
        let data = json.data(using: .utf8)!
        let theme = try JSONDecoder().decode(AppTheme.self, from: data)
        XCTAssertEqual(theme.name, "My Custom Theme")
        XCTAssertEqual(theme.colors["accent"], "#89b4fa")
    }

    // MARK: isBuiltIn

    func test_appTheme_builtInThemesAreNotCustom() {
        for theme in AppTheme.builtInThemes {
            XCTAssertTrue(theme.isBuiltIn, "'\(theme.name)' should be considered built-in")
        }
    }

    func test_appTheme_customThemeIsNotBuiltIn() {
        let custom = AppTheme(name: "My Theme", colors: [:])
        XCTAssertFalse(custom.isBuiltIn)
    }

    // MARK: SwiftUI Color conversion

    func test_appTheme_colorForKeyReturnsNilForMissingKey() {
        let theme = AppTheme(name: "T", colors: ["accent": "#89b4fa"])
        XCTAssertNil(theme.swiftUIColor(for: "background.primary"))
    }

    func test_appTheme_colorForKeyReturnsColorForPresentKey() {
        let theme = AppTheme(name: "T", colors: ["accent": "#89b4fa"])
        XCTAssertNotNil(theme.swiftUIColor(for: "accent"))
    }
}

// MARK: - AppThemeExporter tests

final class AppThemeExporterTests: XCTestCase {

    func test_exportTheme_producesValidJSON() throws {
        let theme = AppTheme.builtInThemes.first!
        let data = try AppThemeExporter.exportData(for: theme)
        let decoded = try JSONDecoder().decode(AppTheme.self, from: data)
        XCTAssertEqual(decoded.name, theme.name)
        XCTAssertEqual(decoded.colors, theme.colors)
    }

    func test_exportTheme_jsonIsPrettyPrinted() throws {
        let theme = AppTheme.builtInThemes.first!
        let data = try AppThemeExporter.exportData(for: theme)
        let str = String(data: data, encoding: .utf8)!
        // Pretty-printed JSON has newlines
        XCTAssertTrue(str.contains("\n"), "Exported JSON should be pretty-printed")
    }
}

// MARK: - AppThemeImporter tests

final class AppThemeImporterTests: XCTestCase {

    func test_importTheme_validJSONSucceeds() throws {
        let json = """
        {
            "name": "Midnight",
            "colors": {
                "background.primary": "#0d0d0d",
                "accent": "#ff5f87"
            }
        }
        """
        let theme = try AppThemeImporter.importTheme(from: json.data(using: .utf8)!)
        XCTAssertEqual(theme.name, "Midnight")
        XCTAssertEqual(theme.colors["accent"], "#ff5f87")
    }

    func test_importTheme_invalidJSONThrows() {
        let bad = "not json".data(using: .utf8)!
        XCTAssertThrowsError(try AppThemeImporter.importTheme(from: bad))
    }

    func test_importTheme_missingNameThrows() {
        let json = """
        {
            "colors": { "accent": "#ff5f87" }
        }
        """
        XCTAssertThrowsError(try AppThemeImporter.importTheme(from: json.data(using: .utf8)!))
    }

    func test_importTheme_emptyNameThrows() {
        let json = """
        {
            "name": "",
            "colors": { "accent": "#ff5f87" }
        }
        """
        XCTAssertThrowsError(try AppThemeImporter.importTheme(from: json.data(using: .utf8)!))
    }

    func test_importTheme_builtInNameThrows() {
        let json = """
        {
            "name": "Synapse (Dark)",
            "colors": { "accent": "#ff5f87" }
        }
        """
        XCTAssertThrowsError(try AppThemeImporter.importTheme(from: json.data(using: .utf8)!)) { error in
            if case AppThemeImportError.conflictsWithBuiltIn = error {
                // expected
            } else {
                XCTFail("Expected conflictsWithBuiltIn error, got \(error)")
            }
        }
    }
}
