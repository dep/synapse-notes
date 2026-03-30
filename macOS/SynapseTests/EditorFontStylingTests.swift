import XCTest
@testable import Synapse

/// Tests for editor font styling based on SettingsManager preferences
/// Issue #139: Font settings should apply to editor with proportional scaling
final class EditorFontStylingTests: XCTestCase {
    var settings: SettingsManager!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let configPath = tempDir.appendingPathComponent("settings.yml").path
        settings = SettingsManager(configPath: configPath)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        settings = nil
        super.tearDown()
    }

    // MARK: - MarkdownTheme Font Tests

    func test_bodyFont_returnsCorrectFont() {
        settings.editorFontSize = 16
        let font = MarkdownTheme.bodyFont(for: settings)

        XCTAssertEqual(font.pointSize, 16,
                       "Body font should match editorFontSize")
    }

    func test_monoFont_returnsCorrectFont() {
        settings.editorFontSize = 16
        let font = MarkdownTheme.monoFont(for: settings)

        // Mono font uses phi-based scaling: max(10, baseSize / phi)
        // For base 16: max(10, 16 / 1.618) = max(10, 9.89) = 10
        XCTAssertEqual(font.pointSize, 10,
                       "Mono font should use phi-based scaling from base size")
    }

    func test_monoFont_minimum10() {
        settings.editorFontSize = 8
        let font = MarkdownTheme.monoFont(for: settings)

        XCTAssertEqual(font.pointSize, 10,
                       "Mono font should have minimum of 10 points")
    }

    func test_h1Font_proportionalScaling() {
        settings.editorFontSize = 15
        let font = MarkdownTheme.h1Font(for: settings)

        // H1 uses phi² scaling: round(base * phi * phi) where phi² ≈ 2.618
        let expectedSize: CGFloat = round(15 * SynapseTheme.Layout.phi * SynapseTheme.Layout.phi)
        XCTAssertEqual(font.pointSize, expectedSize,
                       "H1 font should scale proportionally from base size using phi²")
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.bold),
                      "H1 font should be bold")
    }

    func test_h2Font_proportionalScaling() {
        settings.editorFontSize = 15
        let font = MarkdownTheme.h2Font(for: settings)

        // H2 uses phi scaling: round(base * phi) where phi ≈ 1.618
        let expectedSize: CGFloat = round(15 * SynapseTheme.Layout.phi)
        XCTAssertEqual(font.pointSize, expectedSize,
                       "H2 font should scale proportionally from base size using phi")
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.bold),
                      "H2 font should be bold")
    }

    func test_h3Font_proportionalScaling() {
        settings.editorFontSize = 15
        let font = MarkdownTheme.h3Font(for: settings)

        // H3 uses phi*0.8 scaling: round(base * phi * 0.8) where phi*0.8 ≈ 1.294
        let expectedSize: CGFloat = round(15 * SynapseTheme.Layout.phi * 0.8)
        XCTAssertEqual(font.pointSize, expectedSize,
                       "H3 font should scale proportionally from base size using phi*0.8")
        // On macOS, semibold is represented as bold trait with additional weight info
        // We just verify it's not the regular body font
        let bodyFont = MarkdownTheme.bodyFont(for: settings)
        XCTAssertNotEqual(font, bodyFont, "H3 font should be different from body font")
    }

    func test_h4Font_proportionalScaling() {
        settings.editorFontSize = 15
        let font = MarkdownTheme.h4Font(for: settings)

        // H4 should be 1.07x base (16/15 ≈ 1.07)
        let expectedSize: CGFloat = round(15 * 1.07)
        XCTAssertEqual(font.pointSize, expectedSize,
                       "H4 font should scale proportionally from base size")
        // On macOS, semibold is represented as bold trait with additional weight info
        // We just verify it's not the regular body font
        let bodyFont = MarkdownTheme.bodyFont(for: settings)
        XCTAssertNotEqual(font, bodyFont, "H4 font should be different from body font")
    }

    func test_boldFont_sameSizeAsBody() {
        settings.editorFontSize = 18
        let font = MarkdownTheme.boldFont(for: settings)

        XCTAssertEqual(font.pointSize, 18,
                       "Bold font should be same size as body")
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.bold),
                      "Bold font should have bold weight")
    }

    func test_italicFont_sameSizeAsBody() {
        settings.editorFontSize = 18
        let font = MarkdownTheme.italicFont(for: settings)

        XCTAssertEqual(font.pointSize, 18,
                       "Italic font should be same size as body")
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.italic),
                      "Italic font should have italic traits")
    }

    func test_fontScalingWithCustomBaseSize() {
        settings.editorFontSize = 20

        let body = MarkdownTheme.bodyFont(for: settings)
        let h1 = MarkdownTheme.h1Font(for: settings)
        let mono = MarkdownTheme.monoFont(for: settings)

        XCTAssertEqual(body.pointSize, 20, "Body should be base size")
        // H1 uses phi² scaling: round(20 * 2.618) = 52
        XCTAssertEqual(h1.pointSize, round(20 * SynapseTheme.Layout.phi * SynapseTheme.Layout.phi), "H1 should scale from new base using phi²")
        // Mono uses phi-based scaling: max(10, 20 / 1.618) = max(10, 12.36) = 12.36
        XCTAssertEqual(mono.pointSize, max(10, 20 / SynapseTheme.Layout.phi), "Mono should use phi-based scaling from base size")
    }

    func test_defaultFontSize15() {
        // Default settings (no changes)
        let body = MarkdownTheme.bodyFont(for: settings)
        let mono = MarkdownTheme.monoFont(for: settings)
        let h1 = MarkdownTheme.h1Font(for: settings)

        XCTAssertEqual(body.pointSize, 15, "Default body size should be 15")
        // Mono uses phi-based scaling: max(10, 15 / 1.618) = max(10, 9.27) = 10
        XCTAssertEqual(mono.pointSize, 10, "Default mono size should use phi-based scaling")
        // H1 uses phi² scaling: round(15 * 2.618) = 39
        XCTAssertEqual(h1.pointSize, round(15 * SynapseTheme.Layout.phi * SynapseTheme.Layout.phi), "Default H1 should scale from 15 using phi²")
    }

    func test_lineHeightMultiple_usesSettingsValue() {
        settings.editorLineHeight = 1.9

        XCTAssertEqual(MarkdownTheme.lineHeightMultiple(for: settings), 1.9, accuracy: 0.001)
    }
}
