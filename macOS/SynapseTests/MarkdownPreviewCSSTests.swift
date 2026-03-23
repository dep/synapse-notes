import XCTest
@testable import Synapse

final class MarkdownPreviewCSSTests: XCTestCase {
    func test_bodyFontStack_usesSystemStackByDefault() {
        XCTAssertEqual(
            MarkdownPreviewCSS.bodyFontStack(for: "System"),
            "-apple-system, BlinkMacSystemFont, \"Segoe UI\", Roboto, sans-serif"
        )
    }

    func test_bodyFontStack_quotesCustomFontFamily() {
        XCTAssertEqual(
            MarkdownPreviewCSS.bodyFontStack(for: "Chalkboard SE"),
            "\"Chalkboard SE\", sans-serif"
        )
    }

    func test_monoFontStack_usesSystemMonospaceByDefault() {
        XCTAssertEqual(
            MarkdownPreviewCSS.monoFontStack(for: "System Monospace"),
            "\"SF Mono\", Monaco, \"Cascadia Code\", Menlo, monospace"
        )
    }

    func test_codeFontSize_tracksBaseSize() {
        XCTAssertEqual(MarkdownPreviewCSS.codeFontSize(for: 18), 16)
        XCTAssertEqual(MarkdownPreviewCSS.codeFontSize(for: 8), 10)
    }

    func test_lineHeight_clampsReasonableRange() {
        XCTAssertEqual(MarkdownPreviewCSS.lineHeight(for: 1.8), 1.8, accuracy: 0.001)
        XCTAssertEqual(MarkdownPreviewCSS.lineHeight(for: 0.2), 0.8, accuracy: 0.001)
    }

    func test_headingFontSize_scalesFromBaseSize() {
        XCTAssertEqual(MarkdownPreviewCSS.headingFontSize(level: 1, baseSize: 15), 28)
        XCTAssertEqual(MarkdownPreviewCSS.headingFontSize(level: 2, baseSize: 15), 22)
        XCTAssertEqual(MarkdownPreviewCSS.headingFontSize(level: 3, baseSize: 15), 18)
        XCTAssertEqual(MarkdownPreviewCSS.headingFontSize(level: 4, baseSize: 15), 16)
    }
}
