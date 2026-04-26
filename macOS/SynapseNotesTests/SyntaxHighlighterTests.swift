import XCTest
import AppKit
@testable import Synapse

/// Tests for SyntaxHighlighter — language detection, HTML escaping, and preview HTML used in code blocks.
final class SyntaxHighlighterTests: XCTestCase {

    // MARK: - Language resolution

    func test_canonicalLanguage_trimsAndLowercases() {
        XCTAssertEqual(SyntaxHighlighter.canonicalLanguage("  Swift  "), "swift")
    }

    func test_canonicalLanguage_mapsCommonAliases() {
        XCTAssertEqual(SyntaxHighlighter.canonicalLanguage("js"), "javascript")
        XCTAssertEqual(SyntaxHighlighter.canonicalLanguage("ts"), "typescript")
        XCTAssertEqual(SyntaxHighlighter.canonicalLanguage("py"), "python")
        XCTAssertEqual(SyntaxHighlighter.canonicalLanguage("yml"), "yaml")
        XCTAssertEqual(SyntaxHighlighter.canonicalLanguage("md"), "markdown")
    }

    func test_canonicalLanguage_nilOrEmpty_returnsNil() {
        XCTAssertNil(SyntaxHighlighter.canonicalLanguage(nil))
        XCTAssertNil(SyntaxHighlighter.canonicalLanguage(""))
        XCTAssertNil(SyntaxHighlighter.canonicalLanguage("   "))
    }

    func test_isSupportedLanguage_knownLanguages() {
        XCTAssertTrue(SyntaxHighlighter.isSupportedLanguage("swift"))
        XCTAssertTrue(SyntaxHighlighter.isSupportedLanguage("json"))
        XCTAssertTrue(SyntaxHighlighter.isSupportedLanguage("bash"))
    }

    func test_isSupportedLanguage_unknown_returnsFalse() {
        XCTAssertFalse(SyntaxHighlighter.isSupportedLanguage("brainfuck"))
        XCTAssertFalse(SyntaxHighlighter.isSupportedLanguage(nil))
    }

    // MARK: - highlightedHTML

    func test_highlightedHTML_unsupportedLanguage_escapesOnly() {
        let code = "a < b && c > \"x\""
        let html = SyntaxHighlighter.highlightedHTML(for: code, language: "unknown-lang")
        XCTAssertEqual(html, "a &lt; b &amp;&amp; c &gt; &quot;x&quot;")
    }

    func test_highlightedHTML_swift_wrapsKeywordsInSpans() {
        let code = "let x = 1"
        let html = SyntaxHighlighter.highlightedHTML(for: code, language: "swift")
        XCTAssertTrue(html.contains("<span class=\"hljs-keyword\">let</span>"))
        XCTAssertTrue(html.contains("<span class=\"hljs-number\">1</span>"))
    }

    func test_highlightedHTML_json_escapesPropertyNames() {
        let code = "{\"key\": \"v<a>\"}"
        let html = SyntaxHighlighter.highlightedHTML(for: code, language: "json")
        XCTAssertTrue(html.contains("&lt;"))
        XCTAssertTrue(html.contains("&gt;"))
    }

    // MARK: - apply(to:)

    func test_apply_invalidRange_doesNotMutateStorage() {
        let storage = NSTextStorage(string: "func foo() {}")
        let badRange = NSRange(location: 99, length: 5)
        SyntaxHighlighter.apply(to: storage, codeRange: badRange, language: "swift", baseFont: .monospacedSystemFont(ofSize: 13, weight: .regular), isDarkMode: true)
        let attrs = storage.attributes(at: 0, effectiveRange: nil)
        XCTAssertNil(attrs[.foregroundColor])
    }

    func test_apply_validRange_setsForegroundOnKeywordSpan() {
        let code = "let a = 2"
        let storage = NSTextStorage(string: code)
        let range = NSRange(location: 0, length: (code as NSString).length)
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        SyntaxHighlighter.apply(to: storage, codeRange: range, language: "swift", baseFont: font, isDarkMode: false)

        let keywordColor = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertNotNil(keywordColor)
        let numberColor = storage.attribute(.foregroundColor, at: 8, effectiveRange: nil) as? NSColor
        XCTAssertNotNil(numberColor)
    }

    // MARK: - SyntaxHighlightTheme.css

    func test_syntaxHighlightTheme_css_containsHljsClasses() {
        let light = SyntaxHighlightTheme.css(forDarkMode: false)
        XCTAssertTrue(light.contains(".hljs-keyword"))
        XCTAssertTrue(light.contains(".hljs-comment"))

        let dark = SyntaxHighlightTheme.css(forDarkMode: true)
        XCTAssertTrue(dark.contains(".hljs-string"))
        XCTAssertNotEqual(light, dark)
    }
}
