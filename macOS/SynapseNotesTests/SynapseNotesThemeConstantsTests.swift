import XCTest
import AppKit
import SwiftUI
@testable import Synapse

/// Pins key SynapseTheme colours used across chrome, graphs, and the editor.
/// Silent drift breaks visual consistency and accessibility contrast assumptions.
///
/// Since SynapseTheme statics now delegate to ThemeEnvironment (nil in tests → Synapse Dark),
/// we verify the design tokens against AppTheme.synapseDark which is the authoritative source.
final class SynapseThemeConstantsTests: XCTestCase {

    func test_accentColor_matchesDesignToken() {
        XCTAssertEqual(AppTheme.synapseDark.colors["accent"], "#1F6FBF")
    }

    func test_accentSoftColor_matchesDesignToken() {
        XCTAssertEqual(AppTheme.synapseDark.colors["accent.soft"], "#174F8A")
    }

    func test_successAndErrorColors_matchDesignTokens() {
        XCTAssertEqual(AppTheme.synapseDark.colors["success"], "#5ED499")
        XCTAssertEqual(AppTheme.synapseDark.colors["error"],   "#F24D4D")
    }

    func test_textHierarchy_usesExpectedTokenKeys() {
        XCTAssertNotNil(AppTheme.synapseDark.colors["text.primary"])
        XCTAssertNotNil(AppTheme.synapseDark.colors["text.secondary"])
        XCTAssertNotNil(AppTheme.synapseDark.colors["text.muted"])
    }

    func test_editorNsColors_fallbacksArePresent() {
        // With no ThemeEnvironment in tests, statics fall back to hardcoded NSColor defaults.
        // Just verify they are non-nil (colour space comparisons are handled in AppThemeTests).
        XCTAssertNotNil(SynapseTheme.editorBackground)
        XCTAssertNotNil(SynapseTheme.editorForeground)
        XCTAssertNotNil(SynapseTheme.editorLink)
    }
}
