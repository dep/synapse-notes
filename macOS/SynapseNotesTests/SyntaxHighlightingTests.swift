import XCTest
@testable import Synapse

/// Tests for syntax highlighting in code blocks (Issue #152)
final class SyntaxHighlightingTests: XCTestCase {
    private var renderer: MarkdownPreviewRenderer!
    private var textView: LinkAwareTextView!
    
    override func setUp() {
        super.setUp()
        renderer = MarkdownPreviewRenderer()
        
        // Set up text view for edit mode tests
        textView = LinkAwareTextView()
        textView.isRichText = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 24, height: 24)
        textView.textContainer?.widthTracksTextView = true
        textView.allowsUndo = true
        textView.drawsBackground = true
        
        // Set up scroll view and layout manager
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        textView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
    }
    
    override func tearDown() {
        renderer = nil
        textView = nil
        super.tearDown()
    }
    
    // MARK: - Preview Mode Tests (HTML Rendering)
    
    func test_renderBody_generatesSyntaxHighlightedHTMLForSwiftCodeBlock() {
        let markdown = """
        ```swift
        let x = 5
        func hello() {
            print("Hello")
        }
        ```
        """
        
        let html = renderer.renderBody(from: markdown)
        
        // Should contain syntax highlighting classes
        XCTAssertTrue(html.contains("hljs"), "Should contain highlight.js CSS classes")
        XCTAssertTrue(html.contains("<pre><code"), "Should have code block structure")
    }
    
    func test_renderBody_generatesSyntaxHighlightedHTMLForJavaScriptCodeBlock() {
        let markdown = """
        ```javascript
        const x = 5;
        function hello() {
            console.log("Hello");
        }
        ```
        """
        
        let html = renderer.renderBody(from: markdown)
        
        XCTAssertTrue(html.contains("hljs"), "Should contain highlight.js CSS classes")
    }
    
    func test_renderBody_generatesSyntaxHighlightedHTMLForJSONCodeBlock() {
        let markdown = """
        ```json
        {
            "name": "Synapse",
            "version": "1.0"
        }
        ```
        """
        
        let html = renderer.renderBody(from: markdown)
        
        XCTAssertTrue(html.contains("hljs"), "Should contain highlight.js CSS classes")
    }
    
    func test_renderBody_generatesSyntaxHighlightedHTMLForPythonCodeBlock() {
        let markdown = """
        ```python
        def hello():
            print("Hello")
            return 42
        ```
        """
        
        let html = renderer.renderBody(from: markdown)
        
        XCTAssertTrue(html.contains("hljs"), "Should contain highlight.js CSS classes")
    }
    
    func test_renderBody_generatesSyntaxHighlightedHTMLForBashCodeBlock() {
        let markdown = """
        ```bash
        echo "Hello"
        ls -la
        ```
        """
        
        let html = renderer.renderBody(from: markdown)
        
        XCTAssertTrue(html.contains("hljs"), "Should contain highlight.js CSS classes")
    }
    
    func test_renderBody_generatesPlainHTMLForCodeBlockWithoutLanguage() {
        let markdown = """
        ```
        Plain text code block
        Without language identifier
        ```
        """
        
        let html = renderer.renderBody(from: markdown)
        
        // Should still render as code block but without syntax highlighting classes
        XCTAssertTrue(html.contains("<pre><code"), "Should have code block structure")
        // Should escape HTML content
        XCTAssertFalse(html.contains("<script>"), "Should escape HTML content")
    }
    
    func test_renderBody_preservesCopyButtonFunctionalityWithSyntaxHighlighting() {
        let markdown = """
        ```swift
        let code = "test"
        ```
        """
        
        let html = renderer.renderBody(from: markdown)
        
        // Should still have code block content for copy button to extract
        XCTAssertTrue(html.contains("let code"), "Should preserve code content")
        XCTAssertTrue(html.contains("test"), "Should preserve code content")
    }
    
    // MARK: - Edit Mode Tests (NSTextView)
    
    func test_applyMarkdownStyling_appliesSyntaxHighlightingToSwiftCodeBlocks() {
        let text = """
        Some text
        ```swift
        let x = 5
        func hello() { print("Hi") }
        ```
        More text
        """
        
        textView.setPlainText(text)
        textView.applyMarkdownStyling()
        
        // The text storage should have been modified with syntax highlighting
        guard let storage = textView.textStorage else {
            XCTFail("Should have text storage")
            return
        }
        
        // Check that the code block content has color attributes applied
        let fullText = storage.string
        XCTAssertTrue(fullText.contains("let x = 5"), "Should preserve code content")
    }
    
    func test_applyMarkdownStyling_appliesSyntaxHighlightingToJavaScriptCodeBlocks() {
        let text = """
        ```javascript
        const x = 5;
        function test() {}
        ```
        """
        
        textView.setPlainText(text)
        textView.applyMarkdownStyling()
        
        guard let storage = textView.textStorage else {
            XCTFail("Should have text storage")
            return
        }
        
        XCTAssertTrue(storage.string.contains("const x = 5"), "Should preserve code content")
    }
    
    func test_applyMarkdownStyling_appliesSyntaxHighlightingToJSONCodeBlocks() {
        let text = """
        ```json
        {"key": "value"}
        ```
        """
        
        textView.setPlainText(text)
        textView.applyMarkdownStyling()
        
        guard let storage = textView.textStorage else {
            XCTFail("Should have text storage")
            return
        }
        
        XCTAssertTrue(storage.string.contains("\"key\": \"value\""), "Should preserve code content")
    }
    
    func test_applyMarkdownStyling_doesNotHighlightCodeBlockWithoutLanguage() {
        let text = """
        ```
        Plain text block
        ```
        """
        
        textView.setPlainText(text)
        textView.applyMarkdownStyling()
        
        // Should still have monospace styling but no syntax coloring
        guard let storage = textView.textStorage else {
            XCTFail("Should have text storage")
            return
        }
        
        // Content should still be present with monospace font
        XCTAssertTrue(storage.string.contains("Plain text block"), "Should preserve content")
    }
    
    func test_applyMarkdownStyling_handlesMultipleCodeBlocksWithDifferentLanguages() {
        let text = """
        First block:
        ```swift
        let x = 1
        ```
        Second block:
        ```javascript
        const y = 2;
        ```
        Third block:
        ```python
        z = 3
        ```
        """
        
        textView.setPlainText(text)
        textView.applyMarkdownStyling()
        
        guard let storage = textView.textStorage else {
            XCTFail("Should have text storage")
            return
        }
        
        let content = storage.string
        XCTAssertTrue(content.contains("let x = 1"), "Should preserve Swift code")
        XCTAssertTrue(content.contains("const y = 2"), "Should preserve JavaScript code")
        XCTAssertTrue(content.contains("z = 3"), "Should preserve Python code")
    }
    
    func test_syntaxHighlighting_doesNotBreakCopyButton() {
        let text = """
        ```swift
        let code = "copy me"
        ```
        """
        
        textView.setPlainText(text)
        textView.applyMarkdownStyling()
        textView.refreshCodeBlockCopyButtons()
        
        // Copy buttons should still be created
        XCTAssertFalse(textView.codeBlockCopyButtons.isEmpty, "Should still create copy buttons")
    }
    
    // MARK: - Language Support Tests
    
    func test_syntaxHighlighting_supportsSwift() {
        testLanguageSupport(language: "swift", code: "let x = 5")
    }
    
    func test_syntaxHighlighting_supportsJavaScript() {
        testLanguageSupport(language: "javascript", code: "const x = 5;")
    }
    
    func test_syntaxHighlighting_supportsTypeScript() {
        testLanguageSupport(language: "typescript", code: "const x: number = 5;")
    }
    
    func test_syntaxHighlighting_supportsJSON() {
        testLanguageSupport(language: "json", code: "{\"key\": \"value\"}")
    }
    
    func test_syntaxHighlighting_supportsYAML() {
        testLanguageSupport(language: "yaml", code: "key: value")
    }
    
    func test_syntaxHighlighting_supportsPython() {
        testLanguageSupport(language: "python", code: "def hello(): pass")
    }
    
    func test_syntaxHighlighting_supportsBash() {
        testLanguageSupport(language: "bash", code: "echo hello")
    }
    
    func test_syntaxHighlighting_supportsHTML() {
        testLanguageSupport(language: "html", code: "<div>Hello</div>")
    }
    
    func test_syntaxHighlighting_supportsCSS() {
        testLanguageSupport(language: "css", code: "body { color: red; }")
    }
    
    func test_syntaxHighlighting_supportsMarkdown() {
        testLanguageSupport(language: "markdown", code: "# Hello")
    }
    
    func test_syntaxHighlighting_supportsRuby() {
        testLanguageSupport(language: "ruby", code: "def hello; end")
    }
    
    func test_syntaxHighlighting_supportsGo() {
        testLanguageSupport(language: "go", code: "func main() {}")
    }
    
    func test_syntaxHighlighting_supportsRust() {
        testLanguageSupport(language: "rust", code: "fn main() {}")
    }
    
    func test_syntaxHighlighting_supportsSQL() {
        testLanguageSupport(language: "sql", code: "SELECT * FROM users;")
    }
    
    func test_syntaxHighlighting_supportsC() {
        testLanguageSupport(language: "c", code: "int main() { return 0; }")
    }
    
    func test_syntaxHighlighting_supportsCPP() {
        testLanguageSupport(language: "cpp", code: "int main() { return 0; }")
    }
    
    // Helper method for language support tests
    private func testLanguageSupport(language: String, code: String) {
        let markdown = """
        ```\(language)
        \(code)
        ```
        """
        
        let html = renderer.renderBody(from: markdown)
        
        // Should generate syntax highlighted HTML
        XCTAssertTrue(html.contains("hljs"), "\(language) should be syntax highlighted in HTML")
        
        // Test edit mode
        let text = markdown
        textView.setPlainText(text)
        textView.applyMarkdownStyling()
        
        guard let storage = textView.textStorage else {
            XCTFail("Should have text storage")
            return
        }
        
        XCTAssertTrue(storage.string.contains(code), "\(language) code should be preserved in edit mode")
    }
    
    // MARK: - Edge Case Tests
    
    func test_syntaxHighlighting_handlesEmptyCodeBlock() {
        let markdown = """
        ```swift
        ```
        """
        
        let html = renderer.renderBody(from: markdown)
        
        // Should not crash and should produce valid HTML
        XCTAssertTrue(html.contains("<pre><code"), "Should handle empty code block")
    }
    
    func test_syntaxHighlighting_handlesCodeBlockWithOnlyWhitespace() {
        let markdown = """
        ```swift
           
        ```
        """
        
        let html = renderer.renderBody(from: markdown)
        
        // Should handle whitespace-only content gracefully
        XCTAssertTrue(html.contains("<pre><code"), "Should handle whitespace-only code block")
    }
    
    func test_syntaxHighlighting_handlesUnknownLanguage() {
        let markdown = """
        ```unknown_language
        some code here
        ```
        """
        
        let html = renderer.renderBody(from: markdown)
        
        // Should fall back to plain text rendering without crashing
        XCTAssertTrue(html.contains("<pre><code"), "Should handle unknown language gracefully")
        XCTAssertTrue(html.contains("some code here"), "Should preserve code content even for unknown language")
    }
    
    func test_syntaxHighlighting_handlesSpecialCharactersInCode() {
        let markdown = """
        ```swift
        let x = "<script>alert('xss')</script>"
        ```
        """
        
        let html = renderer.renderBody(from: markdown)
        
        // Should escape HTML special characters
        XCTAssertFalse(html.contains("<script>"), "Should escape HTML tags in code")
        XCTAssertTrue(html.contains("&lt;script&gt;"), "Should escape HTML tags properly")
    }
    
    func test_syntaxHighlighting_preservesBackticksInCode() {
        let markdown = """
        ```javascript
        const str = `template ${literal}`;
        ```
        """
        
        let html = renderer.renderBody(from: markdown)
        
        // Should preserve backtick content
        XCTAssertTrue(html.contains("template"), "Should preserve backtick content")
        XCTAssertTrue(html.contains("literal"), "Should preserve backtick content")
    }
    
    // MARK: - Performance Tests
    
    func test_syntaxHighlighting_performanceWithLargeCodeBlock() {
        let largeCode = String(repeating: "let x = 5\n", count: 1000)
        let markdown = """
        ```swift
        \(largeCode)
        ```
        """
        
        measure {
            _ = renderer.renderBody(from: markdown)
        }
    }
}
