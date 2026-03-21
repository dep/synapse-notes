import XCTest
@testable import Synapse

final class HTMLToMarkdownTests: XCTestCase {

    // MARK: - Basic Text Conversion

    func test_plainTextReturnsUnchanged() {
        let html = "Just some plain text"
        let result = HTMLToMarkdownConverter.convert(html)
        XCTAssertEqual(result, "Just some plain text")
    }

    func test_emptyStringReturnsEmpty() {
        let html = ""
        let result = HTMLToMarkdownConverter.convert(html)
        XCTAssertEqual(result, "")
    }

    func test_whitespaceOnlyReturnsEmpty() {
        let html = "   \n\t  "
        let result = HTMLToMarkdownConverter.convert(html)
        XCTAssertEqual(result, "")
    }

    // MARK: - Headings Conversion

    func test_h1ConvertsToMarkdownHeading() {
        let html = "<h1>Heading 1</h1>"
        let result = HTMLToMarkdownConverter.convert(html)
        XCTAssertEqual(result, "# Heading 1")
    }

    func test_h2ConvertsToMarkdownHeading() {
        let html = "<h2>Heading 2</h2>"
        let result = HTMLToMarkdownConverter.convert(html)
        XCTAssertEqual(result, "## Heading 2")
    }

    func test_h3ConvertsToMarkdownHeading() {
        let html = "<h3>Heading 3</h3>"
        let result = HTMLToMarkdownConverter.convert(html)
        XCTAssertEqual(result, "### Heading 3")
    }

    func test_h4ConvertsToMarkdownHeading() {
        let html = "<h4>Heading 4</h4>"
        let result = HTMLToMarkdownConverter.convert(html)
        XCTAssertEqual(result, "#### Heading 4")
    }

    func test_h5ConvertsToMarkdownHeading() {
        let html = "<h5>Heading 5</h5>"
        let result = HTMLToMarkdownConverter.convert(html)
        XCTAssertEqual(result, "##### Heading 5")
    }

    func test_h6ConvertsToMarkdownHeading() {
        let html = "<h6>Heading 6</h6>"
        let result = HTMLToMarkdownConverter.convert(html)
        XCTAssertEqual(result, "###### Heading 6")
    }

    // MARK: - Text Formatting

    func test_strongConvertsToBold() {
        let html = "<strong>bold text</strong>"
        let result = HTMLToMarkdownConverter.convert(html)
        XCTAssertEqual(result, "**bold text**")
    }

    func test_bConvertsToBold() {
        let html = "<b>bold text</b>"
        let result = HTMLToMarkdownConverter.convert(html)
        XCTAssertEqual(result, "**bold text**")
    }

    func test_emConvertsToItalic() {
        let html = "<em>italic text</em>"
        let result = HTMLToMarkdownConverter.convert(html)
        XCTAssertEqual(result, "_italic text_")
    }

    func test_iConvertsToItalic() {
        let html = "<i>italic text</i>"
        let result = HTMLToMarkdownConverter.convert(html)
        XCTAssertEqual(result, "_italic text_")
    }

    // MARK: - Links

    func test_anchorConvertsToMarkdownLink() {
        let html = "<a href=\"https://example.com\">Example</a>"
        let result = HTMLToMarkdownConverter.convert(html)
        XCTAssertEqual(result, "[Example](https://example.com)")
    }

    // MARK: - Images

    func test_imgConvertsToMarkdownImage() {
        let html = "<img src=\"image.png\" alt=\"Description\">"
        let result = HTMLToMarkdownConverter.convert(html)
        XCTAssertEqual(result, "![Description](image.png)")
    }

    func test_imgWithoutAltConvertsToMarkdownImage() {
        let html = "<img src=\"image.png\">"
        let result = HTMLToMarkdownConverter.convert(html)
        XCTAssertEqual(result, "![](image.png)")
    }

    // MARK: - Lists

    func test_unorderedListConvertsToMarkdown() {
        let html = "<ul><li>Item 1</li><li>Item 2</li><li>Item 3</li></ul>"
        let result = HTMLToMarkdownConverter.convert(html)
        XCTAssertEqual(result, "- Item 1\n- Item 2\n- Item 3")
    }

    func test_orderedListConvertsToMarkdown() {
        let html = "<ol><li>First</li><li>Second</li><li>Third</li></ol>"
        let result = HTMLToMarkdownConverter.convert(html)
        XCTAssertEqual(result, "1. First\n2. Second\n3. Third")
    }

    // MARK: - Blockquotes

    func test_blockquoteConvertsToMarkdown() {
        let html = "<blockquote>This is a quote</blockquote>"
        let result = HTMLToMarkdownConverter.convert(html)
        XCTAssertEqual(result, "> This is a quote")
    }

    // MARK: - Code

    func test_inlineCodeConvertsToMarkdown() {
        let html = "<code>inline code</code>"
        let result = HTMLToMarkdownConverter.convert(html)
        XCTAssertEqual(result, "`inline code`")
    }

    // MARK: - HTML Entities

    func test_htmlEntitiesAreDecoded() {
        let html = "Text with &lt;entities&gt; and &amp; symbols"
        let result = HTMLToMarkdownConverter.convert(html)
        XCTAssertEqual(result, "Text with <entities> and & symbols")
    }

    func test_quotEntityIsDecoded() {
        let html = "He said &quot;hello&quot;"
        let result = HTMLToMarkdownConverter.convert(html)
        XCTAssertEqual(result, "He said \"hello\"")
    }

    // MARK: - Complex Documents

    func test_complexDocumentConvertsCorrectly() {
        let html = """
            <h1>Title</h1>
            <p>This is a paragraph with <strong>bold</strong> and <em>italic</em> text.</p>
            <ul>
                <li>Item 1</li>
                <li>Item 2 with <a href="https://example.com">link</a></li>
            </ul>
            <blockquote>A quoted paragraph</blockquote>
            """
        let result = HTMLToMarkdownConverter.convert(html)

        // Check that all elements are converted
        XCTAssertTrue(result.contains("# Title"))
        XCTAssertTrue(result.contains("**bold**"))
        XCTAssertTrue(result.contains("_italic_"))
        XCTAssertTrue(result.contains("- Item 1"))
        XCTAssertTrue(result.contains("[link](https://example.com)"))
        XCTAssertTrue(result.contains("> A quoted paragraph"))
    }

    func test_richTextEditorOutputConvertsCorrectly() {
        let html = "<div><p>Hello <b>world</b></p><ul><li>Point 1</li><li>Point 2</li></ul></div>"
        let result = HTMLToMarkdownConverter.convert(html)

        XCTAssertTrue(result.contains("Hello **world**"))
        XCTAssertTrue(result.contains("- Point 1"))
        XCTAssertTrue(result.contains("- Point 2"))
    }

    // MARK: - Unsupported Elements

    func test_divIsStrippedButContentPreserved() {
        let html = "<div>Content inside div</div>"
        let result = HTMLToMarkdownConverter.convert(html)
        XCTAssertEqual(result, "Content inside div")
    }

    func test_spanIsStrippedButContentPreserved() {
        let html = "<span>Content inside span</span>"
        let result = HTMLToMarkdownConverter.convert(html)
        XCTAssertEqual(result, "Content inside span")
    }

    func test_nestedUnsupportedElementsHandled() {
        let html = "<div><span>Text in </span><strong>nested</strong> elements</div>"
        let result = HTMLToMarkdownConverter.convert(html)
        XCTAssertEqual(result, "Text in **nested** elements")
    }

    // MARK: - Edge Cases

    func test_multipleParagraphs() {
        let html = "<p>First paragraph</p><p>Second paragraph</p>"
        let result = HTMLToMarkdownConverter.convert(html)
        XCTAssertTrue(result.contains("First paragraph"))
        XCTAssertTrue(result.contains("Second paragraph"))
    }

    func test_lineBreaksConverted() {
        let html = "Line 1<br>Line 2<br/>Line 3"
        let result = HTMLToMarkdownConverter.convert(html)
        XCTAssertTrue(result.contains("Line 1\nLine 2\nLine 3"))
    }
}
