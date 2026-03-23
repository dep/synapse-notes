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

        XCTAssertEqual(font.pointSize, 14,
                       "Mono font should be 2 points smaller than body (16-2=14)")
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

        // H1 should be 1.87x base (28/15 ≈ 1.87)
        let expectedSize: CGFloat = round(15 * 1.87)
        XCTAssertEqual(font.pointSize, expectedSize,
                       "H1 font should scale proportionally from base size")
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.bold),
                      "H1 font should be bold")
    }

    func test_h2Font_proportionalScaling() {
        settings.editorFontSize = 15
        let font = MarkdownTheme.h2Font(for: settings)

        // H2 should be 1.47x base (22/15 ≈ 1.47)
        let expectedSize: CGFloat = round(15 * 1.47)
        XCTAssertEqual(font.pointSize, expectedSize,
                       "H2 font should scale proportionally from base size")
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.bold),
                      "H2 font should be bold")
    }

    func test_h3Font_proportionalScaling() {
        settings.editorFontSize = 15
        let font = MarkdownTheme.h3Font(for: settings)

        // H3 should be 1.2x base (18/15 = 1.2)
        let expectedSize: CGFloat = round(15 * 1.2)
        XCTAssertEqual(font.pointSize, expectedSize,
                       "H3 font should scale proportionally from base size")
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
        XCTAssertEqual(h1.pointSize, round(20 * 1.87), "H1 should scale from new base")
        XCTAssertEqual(mono.pointSize, 18, "Mono should be 2 points smaller than body")
    }

    func test_defaultFontSize15() {
        // Default settings (no changes)
        let body = MarkdownTheme.bodyFont(for: settings)
        let mono = MarkdownTheme.monoFont(for: settings)
        let h1 = MarkdownTheme.h1Font(for: settings)

        XCTAssertEqual(body.pointSize, 15, "Default body size should be 15")
        XCTAssertEqual(mono.pointSize, 13, "Default mono size should be 13 (15-2)")
        XCTAssertEqual(h1.pointSize, round(15 * 1.87), "Default H1 should scale from 15")
    }

    func test_lineHeightMultiple_usesSettingsValue() {
        settings.editorLineHeight = 1.9

        XCTAssertEqual(MarkdownTheme.lineHeightMultiple(for: settings), 1.9, accuracy: 0.001)
    }
}
