import XCTest
@testable import Synapse

final class MarkdownPreviewRendererTests: XCTestCase {
    private var renderer: MarkdownPreviewRenderer!

    override func setUp() {
        super.setUp()
        renderer = MarkdownPreviewRenderer()
    }

    override func tearDown() {
        renderer = nil
        super.tearDown()
    }

    func test_renderBody_rendersHeadingMarkdownLinkWikiLinkAndEmbedFromSharedModel() {
        let markdown = """
        # Title

        Read [docs](https://example.com) and [[Roadmap|Plan]] plus ![[Spec]].
        """

        let html = renderer.renderBody(from: markdown)

        XCTAssertTrue(html.contains("<h1>Title</h1>"))
        XCTAssertTrue(html.contains("<a href=\"https://example.com\">docs</a>"))
        XCTAssertTrue(html.contains("<a href=\"wikilink://Roadmap\" class=\"wikilink\">Plan</a>"))
        XCTAssertTrue(html.contains("<span class=\"embed\">Spec</span>"))
    }

    func test_renderBody_rendersBlockquoteAndFencedCodeBlock() {
        let markdown = """
        > Quoted line

        ```swift
        let answer = 42
        ```
        """

        let html = renderer.renderBody(from: markdown)

        XCTAssertTrue(html.contains("<blockquote>Quoted line</blockquote>"))
        // Check for code block with syntax highlighting (spans for keywords and numbers)
        XCTAssertTrue(html.contains("<pre><code class=\"hljs language-swift\">"))
        XCTAssertTrue(html.contains("hljs-keyword"))
        XCTAssertTrue(html.contains("let"))
        XCTAssertTrue(html.contains("hljs-number"))
        XCTAssertTrue(html.contains("42"))
        XCTAssertTrue(html.contains("</code><!-- raw-code: let answer = 42 --></pre>"))
    }

    func test_renderBody_rendersCalloutBlockquoteWithClass() {
        let markdown = "> [!NOTE] Remember this\n> Body line"

        let html = renderer.renderBody(from: markdown)

        XCTAssertTrue(html.contains("<blockquote class=\"callout callout-note\">"))
        XCTAssertTrue(html.contains("callout-title\">Remember this</div>"))
        XCTAssertTrue(html.contains("callout-body\">Body line</div>"))
    }

    func test_renderBody_rendersValidPipeTableAsTable() {
        let markdown = """
        | Name | Value |
        | --- | --- |
        | One | 1 |
        | Two | 2 |
        """

        let html = renderer.renderBody(from: markdown)

        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<th>Name</th>"))
        XCTAssertTrue(html.contains("<td>Two</td>"))
        XCTAssertTrue(html.contains("<td>2</td>"))
    }

    func test_renderBody_keepsMalformedTableAsPlainParagraphs() {
        let markdown = """
        | Name | Value |
        not a separator row
        """

        let html = renderer.renderBody(from: markdown)

        XCTAssertFalse(html.contains("<table>"))
        XCTAssertTrue(html.contains("<p>| Name | Value |</p>"))
        XCTAssertTrue(html.contains("<p>not a separator row</p>"))
    }

    func test_renderBody_taskCheckboxEmbedsCorrectAbsoluteSourceOffset() {
        // The data-offset in the rendered HTML must point at '[' in "[ ]" / "[x]"
        // so that onToggleCheckbox can do a 3-char replacement at that position.
        // Regression: read-only EditorView instances must never write through activeTextBinding
        // when onToggleCheckbox fires; this test verifies the offset itself is correct.
        let markdown = "- [ ] Ship phase A\n- [x] Ship phase B"
        let html = renderer.renderBody(from: markdown)

        // First item: "- [ ] Ship phase A" starts at offset 0.
        // marker "[ ]" begins at offset 2 (after "- ").
        let ns = markdown as NSString
        let firstBracket = ns.range(of: "[ ]").location
        XCTAssertTrue(html.contains("data-offset=\"\(firstBracket)\""),
                      "Checkbox data-offset for first item should match source offset of '[ ]'")

        // Second item: "- [x] Ship phase B" starts after the newline.
        let secondBracket = ns.range(of: "[x]").location
        XCTAssertTrue(html.contains("data-offset=\"\(secondBracket)\""),
                      "Checkbox data-offset for second item should match source offset of '[x]'")
    }
    
    func test_renderBody_rendersHighlightSyntaxAsMarkElement() {
        let markdown = "This is ==highlighted text== in a paragraph."

        let html = renderer.renderBody(from: markdown)

        XCTAssertTrue(html.contains("<mark>highlighted text</mark>"))
    }

    func test_renderBody_rendersHighlightWithOtherInlineFormatting() {
        let markdown = "**==bold and highlighted==** and ==highlighted with *italic* inside=="

        let html = renderer.renderBody(from: markdown)

        XCTAssertTrue(html.contains("<mark>bold and highlighted</mark>"))
        XCTAssertTrue(html.contains("<mark>highlighted with <em>italic</em> inside</mark>"))
    }

    func test_renderBody_ignoresEmptyHighlight() {
        let markdown = "This ==== is not a highlight."

        let html = renderer.renderBody(from: markdown)

        XCTAssertFalse(html.contains("<mark>"))
        XCTAssertTrue(html.contains("<p>This ==== is not a highlight.</p>"))
    }

    func test_renderBody_rendersUnclosedHighlightAsLiteral() {
        let markdown = "This ==is not closed"

        let html = renderer.renderBody(from: markdown)

        XCTAssertFalse(html.contains("<mark>"))
        XCTAssertTrue(html.contains("==is not closed"))
    }
}
