import XCTest
@testable import Synapse

final class HTMLToMarkdownTests: XCTestCase {

    // MARK: - Basic text

    func test_emptyStringReturnsEmpty() {
        XCTAssertEqual(HTMLToMarkdownConverter.convert(""), "")
    }

    func test_whitespaceOnlyReturnsEmpty() {
        XCTAssertEqual(HTMLToMarkdownConverter.convert("   \n\t  "), "")
    }

    func test_plainTextRoundtrips() {
        let result = HTMLToMarkdownConverter.convert("Just some plain text")
        XCTAssertEqual(result, "Just some plain text")
    }

    // MARK: - Headings

    func test_h1ConvertsToMarkdownHeading() {
        let result = HTMLToMarkdownConverter.convert("<h1>Heading 1</h1>")
        XCTAssertTrue(result.hasPrefix("# "), "Expected '# ' prefix, got: \(result)")
        XCTAssertTrue(result.contains("Heading 1"))
    }

    func test_h2ConvertsToMarkdownHeading() {
        let result = HTMLToMarkdownConverter.convert("<h2>Heading 2</h2>")
        XCTAssertTrue(result.hasPrefix("## "), "Expected '## ' prefix, got: \(result)")
        XCTAssertTrue(result.contains("Heading 2"))
    }

    func test_h3ConvertsToMarkdownHeading() {
        let result = HTMLToMarkdownConverter.convert("<h3>Heading 3</h3>")
        XCTAssertTrue(result.hasPrefix("### "), "Expected '### ' prefix, got: \(result)")
        XCTAssertTrue(result.contains("Heading 3"))
    }

    // MARK: - Inline formatting

    func test_strongConvertsToBold() {
        let result = HTMLToMarkdownConverter.convert("<p>Hello <strong>world</strong></p>")
        XCTAssertTrue(result.contains("**world**"), "Got: \(result)")
    }

    func test_bConvertsToBold() {
        let result = HTMLToMarkdownConverter.convert("<p>Hello <b>world</b></p>")
        XCTAssertTrue(result.contains("**world**"), "Got: \(result)")
    }

    func test_emConvertsToItalic() {
        let result = HTMLToMarkdownConverter.convert("<p>Hello <em>world</em></p>")
        XCTAssertTrue(result.contains("_world_"), "Got: \(result)")
    }

    func test_iConvertsToItalic() {
        let result = HTMLToMarkdownConverter.convert("<p>Hello <i>world</i></p>")
        XCTAssertTrue(result.contains("_world_"), "Got: \(result)")
    }

    func test_inlineCodeConvertsToMonospace() {
        let result = HTMLToMarkdownConverter.convert("<p>Run <code>make test</code> first</p>")
        XCTAssertTrue(result.contains("`make test`"), "Got: \(result)")
    }

    // MARK: - Links

    func test_anchorConvertsToMarkdownLink() {
        let result = HTMLToMarkdownConverter.convert(
            "<a href=\"https://example.com\">Example</a>"
        )
        // NSAttributedString normalises bare origins to include a trailing slash.
        XCTAssertTrue(
            result.contains("[Example](https://example.com)") ||
            result.contains("[Example](https://example.com/)"),
            "Got: \(result)"
        )
    }

    func test_listOfLinksConvertsCorrectly() {
        let html = """
            <ul>
              <li><a href="https://github.com/dep/agent-rules">agent-rules</a></li>
              <li><a href="https://github.com/dep/agent-sync">agent-sync</a></li>
            </ul>
            """
        let result = HTMLToMarkdownConverter.convert(html)
        XCTAssertTrue(result.contains("[agent-rules](https://github.com/dep/agent-rules)"),
                      "Expected Markdown link for agent-rules, got:\n\(result)")
        XCTAssertTrue(result.contains("[agent-sync](https://github.com/dep/agent-sync)"),
                      "Expected Markdown link for agent-sync, got:\n\(result)")
        XCTAssertTrue(result.contains("- "), "Expected list markers, got:\n\(result)")
    }

    // MARK: - Lists

    func test_unorderedListConvertsToMarkdown() {
        let result = HTMLToMarkdownConverter.convert(
            "<ul><li>Item 1</li><li>Item 2</li><li>Item 3</li></ul>"
        )
        XCTAssertTrue(result.contains("- Item 1"), "Got: \(result)")
        XCTAssertTrue(result.contains("- Item 2"), "Got: \(result)")
        XCTAssertTrue(result.contains("- Item 3"), "Got: \(result)")
    }

    func test_orderedListConvertsToMarkdown() {
        let result = HTMLToMarkdownConverter.convert(
            "<ol><li>First</li><li>Second</li><li>Third</li></ol>"
        )
        XCTAssertTrue(result.contains("1."), "Got: \(result)")
        XCTAssertTrue(result.contains("First"), "Got: \(result)")
        XCTAssertTrue(result.contains("Second"), "Got: \(result)")
    }

    // MARK: - HTML entities

    func test_htmlEntitiesAreDecoded() {
        let result = HTMLToMarkdownConverter.convert(
            "Text with &lt;entities&gt; and &amp; symbols"
        )
        XCTAssertTrue(result.contains("<entities>"), "Got: \(result)")
        XCTAssertTrue(result.contains("& symbols"), "Got: \(result)")
    }

    func test_quotEntityIsDecoded() {
        let result = HTMLToMarkdownConverter.convert("He said &quot;hello&quot;")
        XCTAssertTrue(result.contains("\"hello\""), "Got: \(result)")
    }

    // MARK: - Complex documents

    func test_complexDocumentConvertsCorrectly() {
        let html = """
            <h1>Title</h1>
            <p>This is a paragraph with <strong>bold</strong> and <em>italic</em> text.</p>
            <ul>
                <li>Item 1</li>
                <li>Item 2 with <a href="https://example.com">link</a></li>
            </ul>
            """
        let result = HTMLToMarkdownConverter.convert(html)

        XCTAssertTrue(result.contains("# Title"), "Got: \(result)")
        XCTAssertTrue(result.contains("**bold**"), "Got: \(result)")
        XCTAssertTrue(result.contains("_italic_"), "Got: \(result)")
        XCTAssertTrue(result.contains("- Item 1"), "Got: \(result)")
        XCTAssertTrue(
            result.contains("[link](https://example.com)") ||
            result.contains("[link](https://example.com/)"),
            "Got: \(result)"
        )
    }

    func test_richTextEditorOutputConvertsCorrectly() {
        let html = "<div><p>Hello <b>world</b></p><ul><li>Point 1</li><li>Point 2</li></ul></div>"
        let result = HTMLToMarkdownConverter.convert(html)

        XCTAssertTrue(result.contains("**world**"), "Got: \(result)")
        XCTAssertTrue(result.contains("- Point 1"), "Got: \(result)")
        XCTAssertTrue(result.contains("- Point 2"), "Got: \(result)")
    }

    // MARK: - Paragraph structure

    func test_divContentIsPreserved() {
        let result = HTMLToMarkdownConverter.convert("<div>Content inside div</div>")
        XCTAssertTrue(result.contains("Content inside div"), "Got: \(result)")
    }

    func test_multipleParagraphsPreserved() {
        let result = HTMLToMarkdownConverter.convert(
            "<p>First paragraph</p><p>Second paragraph</p>"
        )
        XCTAssertTrue(result.contains("First paragraph"), "Got: \(result)")
        XCTAssertTrue(result.contains("Second paragraph"), "Got: \(result)")
    }
}
